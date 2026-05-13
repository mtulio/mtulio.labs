---
title: Labs - Create HostedCluster with Managed Security Groups on Ingress Routers
---

This guide includes hands-on steps to explore HyperShift to:

- Build HyperShift binary
- Build/BYO HyperShift control plane operator image for custom installs
- Install HyperShift using custom images with feature set TechPreviewNoUpgrade
- Install hosted cluster with feature set TechPreviewNoUpgrade
- Uninstall HyperShift operator


## Building

```sh
# building the binary
make

# building the operator (control-plane-operator) image
export REGISTRY=${REGISTRY:-quay.io/mrbraga}
make docker-build IMG=${REGISTRY}/hypershift-controlplane-operator:devel
```


## Create Layered Hosted Cluster

Prerequisites:
- OCP self-managed
- KUBECONFIG variable from self-managed exported

Steps to create nested cluster to allow flexibility when destroying layers:

> OCP Self Managed -> HCP operator -> Hosted -> HCP Operator -> e2e

```sh
# Globals
export AWS_CREDS="$AWS_SHARED_CREDENTIALS_FILE"
export AWS_DEFAULT_REGION=us-east-1
export CLUSTER_BASE_DOMAIN=splat.devcluster.openshift.com
export PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
export SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

# Create OIDC generic bucket
export OIDC_BUCKET_NAME="hcp-e2e-oidc"
# Setup Bucket for OIDC discovery documents
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


#> Install Hosted Cluster to be used as management cluster (Layered)
export CLUSTER_PREFIX=hcp-e2e-v5

# Hypershift operator must be stable (no TP, development, etc)
./bin/hypershift install \
    --oidc-storage-provider-s3-bucket-name="${OIDC_BUCKET_NAME}" \
    --oidc-storage-provider-s3-credentials="${AWS_CREDS}" \
    --oidc-storage-provider-s3-region="${AWS_DEFAULT_REGION}" \
    --tech-preview-no-upgrade=true


# Create hosted cluster to host the management cluster
OCP_RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:4.22.0-ec.1-x86_64

./bin/hypershift create cluster aws \
  --name="${CLUSTER_PREFIX}" \
  --region="${AWS_DEFAULT_REGION}" \
  --node-pool-replicas=2 \
  --base-domain="${CLUSTER_BASE_DOMAIN}" \
  --pull-secret="${PULL_SECRET_FILE}" \
  --aws-creds="${AWS_CREDS}" \
  --ssh-key="${SSH_PUB_KEY_FILE}" \
  --release-image="${OCP_RELEASE_IMAGE}" \
  --feature-set=TechPreviewNoUpgrade

# Wait the cluster to be installed
 oc get hostedclusters -A -w

# Extract the kubeconfig for the HC/mgr
./bin/hypershift create kubeconfig --name ${CLUSTER_PREFIX} > kubeconfig-${CLUSTER_PREFIX}

export KUBECONFIG_OLD=$KUBECONFIG
export KUBECONFIG=$PWD/kubeconfig-${CLUSTER_PREFIX}

# Ensure that the cluster is stable:
oc get co -w

```


## BYO HyperShift Images

### Step 1: Build the Control-Plane-Operator Image

```sh
export REGISTRY=${REGISTRY:-quay.io/mrbraga}
export CONTROL_PLANE_IMAGE=${REGISTRY}/hypershift-control-plane-operator:dev

podman build -f Dockerfile.control-plane -t ${CONTROL_PLANE_IMAGE} .
```

### Step 2: Push the Image to Your Registry

```sh
podman login quay.io
podman push ${CONTROL_PLANE_IMAGE}
```

### Step 3: Install HyperShift Operator with Custom Images

```sh
./bin/hypershift install \
    --oidc-storage-provider-s3-bucket-name="${OIDC_BUCKET_NAME}" \
    --oidc-storage-provider-s3-credentials="${AWS_CREDS}" \
    --oidc-storage-provider-s3-region="${AWS_DEFAULT_REGION}" \
    --tech-preview-no-upgrade=true \
    --additional-operator-env-vars CONTROL_PLANE_OPERATOR_IMAGE=${CONTROL_PLANE_IMAGE} \
    --development

# Scale up hypershift (--development flag does not start operator)
```

### Step 4: Create Layered Hosted Cluster with Custom Operator

```sh
HOSTED_CLUSTER_NAME="${CLUSTER_PREFIX}-hc1"

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

# Check the cluster information:
oc get --namespace clusters hostedclusters

# When completed, extract the credentials for workload cluster:
./bin/hypershift create kubeconfig --name ${HOSTED_CLUSTER_NAME} > kubeconfig-${HOSTED_CLUSTER_NAME}

# kubeconfig for management cluster
export KUBECONFIG_MGR=$KUBECONFIG

# kubeconfig for workload cluster
export KUBECONFIG=$PWD/kubeconfig-${HOSTED_CLUSTER_NAME}
```

## Testing

### CCM Upstream Tests

```sh
cd ${PATH_TO_CCM}
make e2e.test

./e2e.test --ginkgo.v --ginkgo.focus="loadbalancer NLB internal should be reachable with hairpinning traffic"
./e2e.test --ginkgo.v --ginkgo.focus="loadbalancer NLB should be reachable with target-node-labels"
```

### HyperShift e2e

Reference: [HyperShift e2e docs](https://hypershift-docs.netlify.app/contribute/run-tests/)

```sh
make e2e

bin/test-e2e \
    -test.v \
    -test.run=TestCCMCreateCluster/Main/When_feature_set_is_TechPreviewNoUpgrade/LoadBalancer_service_should_have_security_groups_attached \
    -test.timeout=2h \
    --e2e.aws-region=${AWS_DEFAULT_REGION} \
    --e2e.aws-credentials-file="${AWS_SHARED_CREDENTIALS_FILE}" \
    --e2e.pull-secret-file="${PULL_SECRET_FILE}" \
    --e2e.base-domain="${CLUSTER_BASE_DOMAIN}" \
    --e2e.platform=AWS \
    --e2e.latest-release-image="${OCP_RELEASE_IMAGE}" \
    --e2e.aws-oidc-s3-bucket-name="${OIDC_BUCKET_NAME}" \
    --e2e.aws-oidc-s3-region="${AWS_DEFAULT_REGION}"
```


## Destroy HyperShift Operator

```sh
# Render the manifests that were installed
bin/hypershift install render > hypershift-manifests.yaml

# delete the controller
oc delete ns hypershift

# Delete using the rendered manifests
oc delete -f hypershift-manifests.yaml
```


## Troubleshooting IAM Permissions for Control Plane Components

Extract credentials from the CCM pod to validate IAM permissions:

```sh
CCM_POD=$(oc get pod -l app=cloud-controller-manager \
  -n clusters-${HOSTED_CLUSTER_NAME} \
  -o jsonpath='{.items[0].metadata.name}')

COMPONENT_IAM_ROLE=$(oc exec ${CCM_POD} \
  -c cloud-controller-manager \
  -n clusters-${HOSTED_CLUSTER_NAME} \
  -- cat /etc/kubernetes/secrets/cloud-provider/credentials \
  | grep role_arn | awk -F"= " '{print$2}')

TOKEN_PATH=$(oc exec ${CCM_POD} \
  -c cloud-controller-manager \
  -n clusters-${HOSTED_CLUSTER_NAME} \
  -- cat /etc/kubernetes/secrets/cloud-provider/credentials \
  | grep web_identity | awk -F"= " '{print$2}')

COMPONENT_TOKEN=$(oc exec ${CCM_POD} \
  -c cloud-controller-manager \
  -n clusters-${HOSTED_CLUSTER_NAME} \
  -- cat ${TOKEN_PATH})
```

Assume the role and get temporary credentials:

```sh
aws sts assume-role-with-web-identity \
    --role-arn "${COMPONENT_IAM_ROLE}" \
    --web-identity-token "${COMPONENT_TOKEN}" \
    --role-session-name my-session \
    --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
    --output text \
    | awk '{print "[default]\naws_region = us-east-1\naws_access_key_id = "$1"\naws_secret_access_key = "$2"\naws_session_token = "$3}' \
    | tee ./workload-creds.conf
```

Verify identity and simulate permissions:

```sh
AWS_SHARED_CREDENTIALS_FILE=$PWD/workload-creds.conf \
  aws sts get-caller-identity

aws iam simulate-principal-policy \
    --policy-source-arn ${COMPONENT_IAM_ROLE} \
    --action-names \
      "elasticloadbalancing:DescribeLoadBalancers" \
      "elasticloadbalancing:DescribeTargetGroupAttributes" \
    | jq -r '(["EVAL_ACTION","EVAL_DECISION"] | (., map(length*"-"))),
             (.EvaluationResults[] | [.EvalActionName, .EvalDecision ])
             | @tsv' | column -t
```

Example output:

```
EVAL_ACTION                                         EVAL_DECISION
-----------                                         -------------
elasticloadbalancing:DescribeLoadBalancers          allowed
elasticloadbalancing:DescribeTargetGroupAttributes  implicitDeny
```
