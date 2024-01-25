# OCP Deployment in AWS

# Installing a OCP cluster in AWS with Karpenter
+# OCP Deployment in AWS
 

## Prerequisites

- Cluster with STS authentication mode
- Clients

```bash
export CLUSTER_NAME="mrbkpt"
export CLUSTER_BASE_DOMAIN="devcluster.openshift.com"
export REGION=${CLUSTER_REGION:-'us-east-1'}
export PULL_SECRET_FILE=${HOME}/.openshift/pull-secret-latest.json
export SSH_PUB_KEY_FILE="${HOME}/.ssh/id_rsa.pub"

export OUTPUT_DIR_CCO="${PWD}/${CLUSTER_NAME}-cco/"
export INSTALL_DIR="${PWD}/${CLUSTER_NAME}-installer"
```

### Installing clients

```bash
VERSION="4.13.3"
PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64
echo ">> Download Clients..."
oc adm release extract --tools ${RELEASE_IMAGE} -a ${PULL_SECRET_FILE}

tar xvfz openshift-client-linux-${VERSION}.tar.gz
tar xvfz openshift-install-linux-${VERSION}.tar.gz

oc image extract $(oc adm release info --image-for='cloud-credential-operator' $RELEASE_IMAGE) --file "/usr/bin/ccoctl"
chmod u+x ccoctl
```

### Installing with STS support

```bash
echo "> Creating install-config.yaml"
# Create a single-AZ install config
mkdir -p ${INSTALL_DIR}
cat <<EOF | envsubst > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${CLUSTER_BASE_DOMAIN}
credentialsMode: Manual
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${REGION}
    defaultMachinePlatform:
      zones:
      - ${REGION}a
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
  echo ">> install-config.yaml created: "
  cat ${INSTALL_DIR}/install-config.yaml
  ./openshift-install create manifests --dir $INSTALL_DIR --log-level=debug

echo "> CCO - Creating key-par"
mkdir -p ${OUTPUT_DIR_CCO}
./ccoctl aws create-key-pair \
--output-dir ${OUTPUT_DIR_CCO}

echo "> CCO - Creating IdP"
./ccoctl aws create-identity-provider \
--name=${CLUSTER_NAME} \
--region=${REGION} \
--public-key-file=${OUTPUT_DIR_CCO}/serviceaccount-signer.public \
--output-dir=${OUTPUT_DIR_CCO}/

echo "> CCO - Extracting CredentialsRequests from release payload"
RELEASE_IMAGE=$(./openshift-install version | awk '/release image/ {print $3}')
./oc adm release extract --credentials-requests \
--cloud=aws \
--to=${OUTPUT_DIR_CCO}/credrequests \
${RELEASE_IMAGE}


if [[ ! -d ${OUTPUT_DIR_CCO}/credrequests ]]; then
echo "ERROR directory not found: ${OUTPUT_DIR_CCO}/credrequests"
#return 1
fi

sleep 5;
AWS_IAM_OIDP_ARN=$(aws iam list-open-id-connect-providers \
    | jq -r ".OpenIDConnectProviderList[] | \
        select(.Arn | contains(\"${CLUSTER_NAME}-oidc\") ).Arn")
echo "> CCO - Creating IAM Roles for IdP [${AWS_IAM_OIDP_ARN}]"

./ccoctl aws create-iam-roles \
--name=${CLUSTER_NAME} \
--region=${REGION} \
--credentials-requests-dir=${OUTPUT_DIR_CCO}/credrequests \
--identity-provider-arn=${AWS_IAM_OIDP_ARN} \
--output-dir ${OUTPUT_DIR_CCO}

echo "> CCO - Copying manifests to Install directory"
cp -rvf ${OUTPUT_DIR_CCO}/manifests/* \
${INSTALL_DIR}/manifests
cp -rvf ${OUTPUT_DIR_CCO}/tls \
${INSTALL_DIR}/

./openshift-install create cluster --dir $INSTALL_DIR --log-level=debug
```

## Setting up karpenter

- create namespace

- create credentials

- create notification queue

- Export the vars

```bash
# Address of internal API endpoint
export CLUSTER_ENDPOINT="$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.endpoint" --output text)"

# address of IAM Role ARN
export KARPENTER_IAM_ROLE_ARN="arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-karpenter"

echo $CLUSTER_ENDPOINT $KARPENTER_IAM_ROLE_ARN


KARPENTER_IAM_POLICY=
```


- Install Karpenter

```bash
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version ${KARPENTER_VERSION} --namespace karpenter --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${KARPENTER_IAM_ROLE_ARN} \
  --set settings.aws.clusterName=${CLUSTER_NAME} \
  --set settings.aws.defaultInstanceProfile=KarpenterNodeInstanceProfile-${CLUSTER_NAME} \
  --set settings.aws.interruptionQueueName=${CLUSTER_NAME} \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait
```
