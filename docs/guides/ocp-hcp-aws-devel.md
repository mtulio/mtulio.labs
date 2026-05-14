---
title: Labs - HyperShift Development Quick Start
---

Quick-start guide for setting up a HyperShift development environment using a self-managed OCP cluster as management cluster on AWS.

## Prerequisites

- OCP self-managed cluster
- `KUBECONFIG` variable exported for the self-managed cluster
- AWS credentials with permissions to create S3 buckets, EC2 instances, and IAM roles
- Pull secret from [Red Hat Console](https://console.redhat.com/openshift/install/pull-secret)

## Building

```sh
make
```

## Environment Setup

```sh
export AWS_CREDS="$AWS_SHARED_CREDENTIALS_FILE"
export AWS_DEFAULT_REGION=us-east-1
export CLUSTER_BASE_DOMAIN=splat.devcluster.openshift.com
export PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
export SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub
export CLUSTER_PREFIX=hcp-e2e-v7
```

## Create OIDC Bucket

```sh
export OIDC_BUCKET_NAME="hcp-e2e-oidc"

bucket_policy_file=${OIDC_BUCKET_NAME}-oidc-workload-clusters_policy.json
aws s3api create-bucket --bucket ${OIDC_BUCKET_NAME}
aws s3api delete-public-access-block --bucket ${OIDC_BUCKET_NAME}
echo '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${OIDC_BUCKET_NAME}/*"
    }
  ]
}' | envsubst > ${bucket_policy_file}
aws s3api put-bucket-policy --bucket ${OIDC_BUCKET_NAME} --policy file://${bucket_policy_file}
```

## Install HyperShift Operator

```sh
./bin/hypershift install \
    --oidc-storage-provider-s3-bucket-name="${OIDC_BUCKET_NAME}" \
    --oidc-storage-provider-s3-credentials="${AWS_CREDS}" \
    --oidc-storage-provider-s3-region="${AWS_DEFAULT_REGION}" \
    --tech-preview-no-upgrade=true \
    --development
```

## Create Hosted Cluster

Choose the desired target release from the [release controller](https://openshift-release.apps.ci.l2s4.p1.openshiftapps.com/).

```sh
OCP_RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:4.21.0-ec.3-x86_64
HOSTED_CLUSTER_NAME=${CLUSTER_PREFIX}-hc1

./bin/hypershift create cluster aws \
  --name="${HOSTED_CLUSTER_NAME}" \
  --region="${AWS_DEFAULT_REGION}" \
  --node-pool-replicas=2 \
  --base-domain="${CLUSTER_BASE_DOMAIN}" \
  --pull-secret="${PULL_SECRET_FILE}" \
  --aws-creds="${AWS_CREDS}" \
  --ssh-key="${SSH_PUB_KEY_FILE}" \
  --release-image="${OCP_RELEASE_IMAGE}" \
  --feature-set=TechPreviewNoUpgrade

oc get hostedclusters -A -w
```

## Extract Kubeconfig

```sh
./bin/hypershift create kubeconfig --name ${HOSTED_CLUSTER_NAME} > kubeconfig-${HOSTED_CLUSTER_NAME}

export KUBECONFIG_MGR=$KUBECONFIG
export KUBECONFIG=$PWD/kubeconfig-${HOSTED_CLUSTER_NAME}

oc get co -w
```

## Destroy

```sh
./bin/hypershift destroy cluster aws \
  --name="${HOSTED_CLUSTER_NAME}" \
  --aws-creds="${AWS_CREDS}" \
  --region="${AWS_DEFAULT_REGION}"

bin/hypershift install render > hypershift-manifests.yaml
oc delete ns hypershift
oc delete -f hypershift-manifests.yaml
```
