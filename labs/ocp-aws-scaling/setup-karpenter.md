# Kubernetes Scaling Lab | Karpenter

[karpenter.sh](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/)
deployment steps to experiment in OpenShift clusters on AWS.

### Install OpenShift

- Export the AWS credentials

```sh
export AWS_PROFILE=lab-scaling
```

- Install OpenShift cluster

```sh
VERSION="4.14.8"
PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64
CLUSTER_NAME=kpt-p2c1
INSTALL_DIR=${HOME}/openshift-labs/$CLUSTER_NAME
CLUSTER_BASE_DOMAIN=lab-scaling.devcluster.openshift.com
SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub
REGION=us-east-1
AWS_REGION=$REGION

mkdir -p $INSTALL_DIR && cd $INSTALL_DIR

oc adm release extract \
    --tools quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64 \
    -a ${PULL_SECRET_FILE}

tar xvfz openshift-client-linux-${VERSION}.tar.gz
tar xvfz openshift-install-linux-${VERSION}.tar.gz

echo "> Creating install-config.yaml"
# Create a single-AZ install config
mkdir -p ${INSTALL_DIR}
cat <<EOF | envsubst > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${CLUSTER_BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${REGION}
    propagateUserTags: true
    userTags:
      cluster_name: $CLUSTER_NAME
      Environment: cluster
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

echo ">> install-config.yaml created: "
cp -v ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config.yaml-bkp

./openshift-install create cluster --dir $INSTALL_DIR --log-level=debug

export KUBECONFIG=$PWD/auth/kubeconfig
```

- Scale down the 3rd machineset to optimize the tests leaving two hosts for regular workloads:

```sh
oc scale machineset -n openshift-machine-api --replicas=0 $(oc get machineset -n openshift-machine-api -o jsonpath='{.items[2].metadata.name}')
```

- Create subnet tags to Karpenter discover only private subnets to spin-up nodes:

```sh
# Get the cluster VPC from existing node subnet
export CLUSTER_ID=$(oc get infrastructures cluster -o jsonpath='{.status.infrastructureName}')
export MACHINESET_NAME=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.name}')
export MACHINESET_SUBNET_NAME=$(oc get machineset -n openshift-machine-api $MACHINESET_NAME -o json | jq -r '.spec.template.spec.providerSpec.value.subnet.filters[0].values[0]')

VPC_ID=$(aws ec2 describe-subnets --region $AWS_REGION --filters Name=tag:Name,Values=$MACHINESET_SUBNET_NAME --query 'Subnets[].VpcId' --output text)

# 1) Filter subnets only with "private" in the name
# 2) Apply the tag matching the NodeClass
aws ec2 create-tags --region $AWS_REGION --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}" \
  --resources $(aws ec2 describe-subnets \
    --region $AWS_REGION \
    --filters Name=vpc-id,Values=$VPC_ID \
    | jq -r '.Subnets[] | [{"Id": .SubnetId, "Name": (.Tags[] | select(.Key=="Name").Value) }]' \
    | jq -r '.[] | select(.Name | contains("private")).Id'  | tr '\n' ' ')
```

### Install Karpenter with staic IAM user

- Setup namespace and credentials:

> TODO: decrease permissions for NS

```sh
oc apply -f deploy-karpenter/setup/base.yaml

# OR

oc create -f https://raw.githubusercontent.com/mtulio/mtulio.labs/lab-kube-scaling/labs/ocp-aws-scaling/deploy-karpenter/setup/base.yaml
```

- Deploy the csr-approver:

!!! warning "Not recommended"
    CSR approver is a quickly way to approve CSRs in the development and controlled environment.
    It is not recommended to approve all certification requests without validation of the source.

    TODO: find a better way to approve certs.

```sh
oc apply -f deploy-karpenter/setup/csr-approver.yaml

# OR

oc apply -f https://raw.githubusercontent.com/mtulio/mtulio.labs/lab-kube-scaling/labs/ocp-aws-scaling/deploy-karpenter/setup/csr-approver.yaml
```

- Export Required variables

> https://github.com/aws/karpenter-provider-aws/blob/main/charts/karpenter/README.md

```sh
export KARPENTER_NAMESPACE=karpenter
export KARPENTER_VERSION=v0.33.1
export WORKER_PROFILE=$(oc get machineset -n openshift-machine-api $(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.name}') -o json | jq -r '.spec.template.spec.providerSpec.value.iamInstanceProfile.id')
export KUBE_ENDPOINT=$(oc get infrastructures cluster -o jsonpath='{.status.apiServerInternalURI}')

cat <<EOF
KARPENTER_NAMESPACE=$KARPENTER_NAMESPACE
KARPENTER_VERSION=$KARPENTER_VERSION
CLUSTER_NAME=$CLUSTER_NAME
WORKER_PROFILE=$WORKER_PROFILE
EOF
```

- Provision the infra required by Karpenter (SQS Queues)

```sh
# Based in https://raw.githubusercontent.com/aws/karpenter-provider-aws/v0.33.1/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml
wget -qO /tmp/karpenter-template.yaml https://raw.githubusercontent.com/mtulio/mtulio.labs/lab-kube-scaling/labs/ocp-aws-scaling/deploy-karpenter/setup/cloudformation.yaml
aws cloudformation create-stack \
    --region ${AWS_REGION} \
    --stack-name karpenter-${CLUSTER_NAME} \
    --template-body file:///tmp/karpenter-template.yaml \
    --parameters \
        ParameterKey=ClusterName,ParameterValue=${CLUSTER_NAME}

aws cloudformation wait stack-create-complete \
    --region ${AWS_REGION} \
    --stack-name karpenter-${CLUSTER_NAME}
```

- Install Karpenter with helm:

> Note: do not set --wait as it is required some patches

```sh
helm upgrade --install --namespace karpenter \
  karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version $KARPENTER_VERSION \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "aws.defaultInstanceProfile=$WORKER_PROFILE" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set "settings.cluster-endpoint=$KUBE_ENDPOINT"
```

- Apply patches to fix karpenter default deployment:

```sh
#
# Patches
#

# 1) Remove custom SCC defined by karpenter inheriting from Namespace
oc patch deployment.apps/karpenter -n karpenter --type=json -p="[{'op': 'remove', 'path': '/spec/template/spec/containers/0/securityContext'}]"

# 2A) Mount volumes/creds created by CCO (CredentialsRequests)
oc set volume deployment.apps/karpenter --add -t secret -m /var/secrets/karpenter --secret-name=karpenter-aws-credentials --read-only=true

# 2B) Set env vars required to use custom credentials and OpenShift specifics
oc set env deployment.apps/karpenter LOG_LEVEL=debug AWS_REGION=$AWS_REGION AWS_SHARED_CREDENTIALS_FILE=/var/secrets/karpenter/credentials CLUSTER_ENDPOINT=$KUBE_ENDPOINT

# 3) Run karpenter on Control Plane
oc patch deployment.apps/karpenter --type=json -p '[{
    "op": "add",
    "path": "/spec/template/spec/tolerations/-",
    "value": {"key":"node-role.kubernetes.io/master", "operator": "Exists", "effect": "NoSchedule"}
}]'

# 4) Fix RBAC allowing karpenter to create nodeClaims
# https://github.com/aws/karpenter-provider-aws/blob/main/charts/karpenter/templates/clusterrole-core.yaml#L52-L67
# {"level":"ERROR","time":"2024-01-30T21:13:12.667Z","logger":"controller","message":"Reconciler error","commit":"2dd7fdc","controller":"nodeclaim.lifecycle","controllerGroup":"karpenter.sh","controllerKind":"NodeClaim","NodeClaim":{"name":"default-nvpkv"},"namespace":"","name":"default-nvpkv","reconcileID":"1a1a3577-753b-424f-b70a-3f89a6d388ab","error":"syncing node, syncing node labels, nodes \"ip-10-0-33-137.ec2.internal\" is forbidden: cannot set blockOwnerDeletion if an ownerReference refers to a resource you can't set finalizers on: , <nil>"} 
oc patch clusterrole karpenter --type=json -p '[{
    "op": "add",
    "path": "/rules/-",
    "value": {"apiGroups":["karpenter.sh"], "resources": ["nodeclaims","nodeclaims/finalizers", "nodepools","nodepools/finalizers"], "verbs": ["create","update","delete","patch"]}
  }]'
```

## Setup Karpenter for test variants

- Discover the node provisioner configuration from MAPI/MachineSet object:

```sh
INFRA_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
MACHINESET_SG_NAME=$(oc get machineset -n openshift-machine-api $MACHINESET_NAME -o json | jq -r '.spec.template.spec.providerSpec.value.securityGroups[0].filters[0].values[0]')
MACHINESET_INSTANCE_PROFILE=$(oc get machineset -n openshift-machine-api $MACHINESET_NAME -o json | jq -r '.spec.template.spec.providerSpec.value.iamInstanceProfile.id')
MACHINESET_AMI_ID=$(oc get machineset -n openshift-machine-api $MACHINESET_NAME -o json | jq -r '.spec.template.spec.providerSpec.value.ami.id')
MACHINESET_USER_DATA_SECRET=$(oc get machineset -n openshift-machine-api $MACHINESET_NAME -o json | jq -r '.spec.template.spec.providerSpec.value.userDataSecret.name')
MACHINESET_USER_DATA=$(oc get secret -n openshift-machine-api $MACHINESET_USER_DATA_SECRET -o jsonpath='{.data.userData}' | base64 -d)

TAG_NAME="${MACHINESET_NAME/"-$REGION"*}-karpenter"

# Installer does not set the SG Name 'as-is' defined in the MachineSet, so it need to filter by tag:Name
# and discover the ID

cat <<EOF
AWS_REGION=$REGION
INFRA_NAME=$INFRA_NAME
MACHINESET_NAME=$MACHINESET_NAME
MACHINESET_SUBNET_NAME=$MACHINESET_SUBNET_NAME
MACHINESET_SG_NAME=$MACHINESET_SG_NAME
MACHINESET_INSTANCE_PROFILE=$MACHINESET_INSTANCE_PROFILE
MACHINESET_AMI_ID=$MACHINESET_AMI_ID
MACHINESET_USER_DATA_SECRET=$MACHINESET_USER_DATA_SECRET
MACHINESET_USER_DATA=$MACHINESET_USER_DATA
TAG_NAME=$TAG_NAME
EOF
```

- Create Karpenter Node Class:

!!! tip "References"
    - [About Node Templates](https://karpenter.sh/v0.31/concepts/node-templates/)
    - [About Provisioners](https://karpenter.sh/v0.31/concepts/provisioners/)
    - [About NodePools](https://karpenter.sh/docs/concepts/nodepools/)


```sh
NODE_CLASS_NAME=default
NODE_CLASS_FILENAME=./karpenter-nodeClass-$NODE_CLASS_NAME.yaml
cat << EOF > $NODE_CLASS_FILENAME
---
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: $NODE_CLASS_NAME
spec:
  amiFamily: Custom
  amiSelectorTerms:
  - id: "${MACHINESET_AMI_ID}"
  instanceProfile: "${MACHINESET_INSTANCE_PROFILE}"
  subnetSelectorTerms:
  - tags:
      kubernetes.io/cluster/${INFRA_NAME}: owned
      karpenter.sh/discovery: "$CLUSTER_NAME"
  securityGroupSelectorTerms:
  - tags:
      Name: "${MACHINESET_SG_NAME}"
  tags:
    Name: ${TAG_NAME}
    cluster_name: $CLUSTER_NAME
    Environment: autoscaler
  userData: |
    $MACHINESET_USER_DATA
EOF
```

- Review and create

```sh
# Check if all vars have been replaced in ./kpt-provisioner-m6.yaml
less $NODE_CLASS_FILENAME

# Apply the config

oc create -f $NODE_CLASS_FILENAME
```

### Create Karpenter NodePool for test Phase-1-Case-1: OnDemand single type


- Creating NodePool

```sh
POOL_NAME=p1c1-m6xlarge-od
POOL_CONFIG_FILE=./karpenter-${POOL_NAME}.yaml
#POOL_CAPCITY_TYPES="\"on-demand\", \"spot\""
POOL_CAPCITY_TYPES="\"on-demand\""
#POOL_INSTANCE_CATEGORIES="\"m\""
POOL_INSTANCE_FAMILY="\"m6i\""
# POOL_INSTANCE_GEN="\"6\""
CLUSTER_LIMIT_CPU="40"
CLUSTER_LIMIT_MEM="160Gi"

# Read for more info: https://karpenter.sh/docs/concepts/nodepools/
cat << EOF > ${POOL_CONFIG_FILE}
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: $POOL_NAME
spec:
  template:
    metadata:
      labels:
        Environment: karpenter
    spec:
      nodeClassRef:
        name: $NODE_CLASS_NAME

      # forcing to match m6i.xlarge (phase 1)
      requirements:
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "karpenter.k8s.aws/instance-family"
          operator: In
          values: [$POOL_INSTANCE_FAMILY]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: [$POOL_CAPCITY_TYPES]
        - key: "karpenter.k8s.aws/instance-size"
          operator: In
          values: ["xlarge"]

  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 12h

  limits:
    cpu: "$CLUSTER_LIMIT_CPU"
    memory: $CLUSTER_LIMIT_MEM
  weight: 10
EOF
```

- Review and create:

```sh
less $POOL_CONFIG_FILE

oc apply -f $POOL_CONFIG_FILE
```

### Create Karpenter NodePool for test Phase-1-Case-2: OnDemand + Spot single type

- Creating NodePool

```sh
POOL_NAME=p1c2-m6xlarge-od-spot
POOL_CONFIG_FILE=./karpenter-${POOL_NAME}.yaml
POOL_CAPCITY_TYPES="\"on-demand\", \"spot\""
POOL_INSTANCE_FAMILY="\"m6i\""
CLUSTER_LIMIT_CPU="40"
CLUSTER_LIMIT_MEM="160Gi"

# Read for more info: https://karpenter.sh/docs/concepts/nodepools/
cat << EOF > ${POOL_CONFIG_FILE}
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: $POOL_NAME
spec:
  template:
    metadata:
      labels:
        Environment: karpenter
    spec:
      nodeClassRef:
        name: $NODE_CLASS_NAME

      # forcing to match m6i.xlarge (phase 1)
      requirements:
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "karpenter.k8s.aws/instance-family"
          operator: In
          values: [$POOL_INSTANCE_FAMILY]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: [$POOL_CAPCITY_TYPES]
        - key: "karpenter.k8s.aws/instance-size"
          operator: In
          values: ["xlarge"]

  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 12h

  limits:
    cpu: "$CLUSTER_LIMIT_CPU"
    memory: $CLUSTER_LIMIT_MEM
  weight: 10
EOF
```

- Review and create:

```sh
less $POOL_CONFIG_FILE

oc create -f $POOL_CONFIG_FILE
```

### Create Karpenter NodePool for test Phase-2-Case-1: OnDemand mixed types

- Creating NodePool

```sh
POOL_NAME=p2c1-mixed-od
POOL_CONFIG_FILE=./karpenter-${POOL_NAME}.yaml
POOL_CAPCITY_TYPES="\"on-demand\""
POOL_INSTANCE_FAMILY="\"c5\",\"c5a\",\"i3\",\"m5\",\"m5a\",\"m6a\",\"m6i\",\"r5\",\"r5a\",\"r6i\",\"t3\",\"t3a\""
CLUSTER_LIMIT_CPU="40"
CLUSTER_LIMIT_MEM="160Gi"

# Read for more info: https://karpenter.sh/docs/concepts/nodepools/
cat << EOF > ${POOL_CONFIG_FILE}
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: $POOL_NAME
spec:
  template:
    metadata:
      labels:
        Environment: karpenter
    spec:
      nodeClassRef:
        name: $NODE_CLASS_NAME

      # forcing to match m6i.xlarge (phase 1)
      requirements:
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "karpenter.k8s.aws/instance-family"
          operator: In
          values: [$POOL_INSTANCE_FAMILY]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: [$POOL_CAPCITY_TYPES]

  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 12h

  limits:
    cpu: "$CLUSTER_LIMIT_CPU"
    memory: $CLUSTER_LIMIT_MEM
  weight: 10
EOF
```

- Review and create:

```sh
less $POOL_CONFIG_FILE

oc create -f $POOL_CONFIG_FILE
```

### Create Karpenter NodePool for test Phase-2-Case-2: OnDemand+Spot mixed types

- Creating NodePool

```sh
POOL_NAME=p2c2-mixed-od-spot
POOL_CONFIG_FILE=./karpenter-${POOL_NAME}.yaml
POOL_CAPCITY_TYPES="\"on-demand\", \"spot\""
POOL_INSTANCE_FAMILY="\"c5\",\"c5a\",\"i3\",\"m5\",\"m5a\",\"m6a\",\"m6i\",\"r5\",\"r5a\",\"r6i\",\"t3\",\"t3a\""
CLUSTER_LIMIT_CPU="40"
CLUSTER_LIMIT_MEM="160Gi"

# Read for more info: https://karpenter.sh/docs/concepts/nodepools/
cat << EOF > ${POOL_CONFIG_FILE}
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: $POOL_NAME
spec:
  template:
    metadata:
      labels:
        Environment: karpenter
    spec:
      nodeClassRef:
        name: $NODE_CLASS_NAME

      # forcing to match m6i.xlarge (phase 1)
      requirements:
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "karpenter.k8s.aws/instance-family"
          operator: In
          values: [$POOL_INSTANCE_FAMILY]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: [$POOL_CAPCITY_TYPES]

  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 12h

  limits:
    cpu: "$CLUSTER_LIMIT_CPU"
    memory: $CLUSTER_LIMIT_MEM
  weight: 10
EOF
```

- Review and create:

```sh
less $POOL_CONFIG_FILE

oc create -f $POOL_CONFIG_FILE
```

### Review

Check if objects have been created:

```sh
oc get EC2NodeClass 
oc get EC2NodeClass default -o json | jq .status

oc get NodePool
oc get NodePool -o yaml
```

Check the logs (expected no errors):

```sh
oc logs -f -c controller deployment.apps/karpenter
```

## Run scaling tests

- Start:

```sh
oc apply -f https://raw.githubusercontent.com/elmiko/openshift-lab-scaling/devel/setup.yaml
oc apply -f https://raw.githubusercontent.com/elmiko/openshift-lab-scaling/devel/three-hour-scaling-test.yaml
```

- Check the logs

```sh
oc logs -n kb-burner -f -l batch.kubernetes.io/job-name=pykb-runner
```

- Check if there are pending pods provisioned by kube-burner

```sh
oc get pods -A | grep -i pending
```

### Clean up jobs

```sh
# Remove jobs
NS_JOBS=cluster-scaling
for X in $(seq 0 3); do echo "Deleting namespace $NS_JOBS-$X" && oc delete ns $NS_JOBS-$X & done

# Remove KB
oc delete ns kb-burner &
oc delete ClusterRoleBinding kube-burner-user
```

## Collect the data:

- Create local file dir for cluster data

```sh
DATA_DIR=test-data-${CLUSTER_NAME}
mkdir -p $DATA_DIR
```

- Test logs and Karpenter

```sh
oc adm inspect ns/kb-burner ns/karpenter --dest-dir $DATA_DIR/namespace-tests
#oc adm inspect ns/karpenter --dest-dir $DATA_DIR/ns-karpenter

tar cfJ $DATA_DIR/namespace-tests.txz $DATA_DIR/namespace-tests &
```

- Cluster Must-gather

```sh
oc adm must-gather --dest-dir $DATA_DIR/must-gather

tar cfJ $DATA_DIR/must-gather.txz $DATA_DIR/must-gather
```

- Prometheus

> https://access.redhat.com/solutions/5482971

```sh
# save to $DATA_DIR/prometheus
cat <<'EOF' > prometheus-metrics.sh
#!/usr/bin/env bash

function queue() {
local TARGET="${1}"
shift
local LIVE
LIVE="$(jobs | wc -l)"
while [[ "${LIVE}" -ge 45 ]]; do
  sleep 1
  LIVE="$(jobs | wc -l)"
done
echo "${@}"
if [[ -n "${FILTER:-}" ]]; then
  "${@}" | "${FILTER}" >"${TARGET}" &
else
  "${@}" >"${TARGET}" &
fi
}

ARTIFACT_DIR=$PWD
mkdir -p $ARTIFACT_DIR/metrics
echo "Snapshotting prometheus (may take 15s) ..."
queue ${ARTIFACT_DIR}/metrics/prometheus.tar.gz oc --insecure-skip-tls-verify exec -n openshift-monitoring prometheus-k8s-0 -- tar cvzf - -C /prometheus .
FILTER=gzip queue ${ARTIFACT_DIR}/metrics/prometheus-target-metadata.json.gz oc --insecure-skip-tls-verify exec -n openshift-monitoring prometheus-k8s-0 -- /bin/bash -c "curl -G http://localhost:9090/api/v1/targets/metadata --data-urlencode 'match_target={instance!=\"\"}'"
wait
EOF
bash prometheus-metrics.sh
```

- Prometheus check

```sh
# TODO/not working:
mkdir $DATA_DIR/metrics/prometheus
tar xfz $DATA_DIR/metrics/prometheus.tar.gz -C $DATA_DIR/metrics/prometheus
podman run \
    -p 9090:9090 \
    -v ${PWD}/$DATA_DIR/metrics/prometheus:/prometheus:w \
    -d quay.io/prometheus/prometheus:v2.45.3
```

- Cluster costs: Wait for available in Cost Explorer


### Clean up cluster

- Karpenter only

```sh
helm uninstall karpenter --namespace karpenter
oc delete NodePools $POOL_NAME
oc delete EC2NodeClass default


# Destroy cloudformation
aws cloudformation delete-stack \
    --region ${AWS_REGION} \
    --stack-name karpenter-${CLUSTER_NAME}
```

- OCP Cluster

```sh
# Destroy cluster
./openshift-install destroy cluster --dir $INSTALL_DIR
```