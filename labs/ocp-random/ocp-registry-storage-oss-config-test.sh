#!/bin/bash

#
# Script to validate Image Registry CRD
# References:
# - https://github.com/openshift/api/pull/1082
# - https://github.com/openshift/api/pull/1086
# - https://github.com/openshift/cluster-image-registry-operator/pull/724
#

set -e

get_oss_bucket_name() {
  echo $(oc get configs.imageregistry.operator.openshift.io/cluster -n openshift-image-registry -o jsonpath='{.spec.storage.oss.bucket}')
}
show_registry_storage() {
  echo "#> Getting current image-registry CRD storage: "
  sleep 5;
  oc get configs.imageregistry.operator.openshift.io/cluster -n openshift-image-registry -o jsonpath='{.spec.storage}' |jq .
  echo "#> Getting current image-registry deployment variables: "
  sleep 5
  oc get deployments image-registry -n openshift-image-registry -o jsonpath='{.spec.template.spec.containers[0].env}' |jq -r '.[] |select(.name=="REGISTRY_STORAGE_OSS_BUCKET")'
}
list_bucket() {
  echo "#> List bucket on OSS oss://${1}"
  sleep 5;
  ./ossutil64 ls oss://${1}
}

TS=$(date +%Y%m%d%H%M)
BASE_NAME="test-image-registry-${TS}"

echo "#> Creating buckets with prefix: ${BASE_NAME}"

echo "#> Starting... checking initial config"
show_registry_storage

echo "#> Cleaning current OSS configuration..."
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type='json' \
  -p='[{"op":"remove","path":"/spec/storage/oss"}]'

show_registry_storage
list_bucket "$(get_oss_bucket_name)"

BUCKET_NAME="${BASE_NAME}-custom"
echo "#> Creating a custom bucket with name: ${BUCKET_NAME}"
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/spec/storage/oss\",\"value\":{\"bucket\":\"${BUCKET_NAME}\"}}]"

show_registry_storage
list_bucket "${BUCKET_NAME}"

BUCKET_NAME="${BASE_NAME}-kms"
KMS_KEY_ID="be41ecd4-4124-4e85-b84c-135e5cbab113"
echo "#> Create a bucket with KMS encryption: ${BUCKET_NAME}"
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/spec/storage/oss\",\"value\":{\"bucket\":\"${BUCKET_NAME}\",\"encryption\":{\"method\":\"KMS\",\"kms\":{\"keyID\":\"${KMS_KEY_ID}\"}}}}]"

show_registry_storage
list_bucket "${BUCKET_NAME}"

BUCKET_NAME="${BASE_NAME}-aes256"
echo "#> Create a bucket with AES256 encryption: ${BUCKET_NAME}"
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/spec/storage/oss\",\"value\":{\"bucket\":\"${BUCKET_NAME}\",\"encryption\":{\"method\":\"AES256\"}}}]"

show_registry_storage
list_bucket "${BUCKET_NAME}"

echo "#> Show buckets created with prefix [${BASE_NAME}]"
./ossutil64 ls |grep ${BASE_NAME}
