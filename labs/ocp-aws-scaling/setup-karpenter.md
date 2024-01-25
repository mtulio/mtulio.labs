# Kubernetes Scaling Lab | Karpenter

[karpenter.sh](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/)
deployment steps to experiment in OpenShift clusters on AWS.

### Install OpenShift

```sh
VERSION="4.14.8"
PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64
CLUSTER_NAME=kpt00
INSTALL_DIR=${HOME}/openshift-labs/$CLUSTER_NAME
CLUSTER_BASE_DOMAIN=lab-scaling.devcluster.openshift.com
REGION=us-east-1
SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

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
cp ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config.yaml-bkp

./openshift-install create cluster --dir $INSTALL_DIR --log-level=debug
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
oc apply -f deploy-karpenter/setup//csr-approver.yaml

# OR

oc create -f https://raw.githubusercontent.com/mtulio/mtulio.labs/lab-kube-scaling/labs/ocp-aws-scaling/deploy-karpenter/setup/csr-approver.yaml
```

- Export Required variables

```sh
export KARPENTER_NAMESPACE=karpenter
export KARPENTER_VERSION=v0.27.0
export CLUSTER_NAME=$(oc get infrastructures cluster -o jsonpath='{.status.infrastructureName}')
export WORKER_PROFILE=$(oc get machineset -n openshift-machine-api $(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.name}') -o json | jq -r '.spec.template.spec.providerSpec.value.iamInstanceProfile.id')
export KUBE_ENDPOINT=$(oc get infrastructures cluster -o jsonpath='{.status.apiServerInternalURI}')

cat <<EOF
KARPENTER_NAMESPACE=$KARPENTER_NAMESPACE
KARPENTER_VERSION=$KARPENTER_VERSION
CLUSTER_NAME=$CLUSTER_NAME
WORKER_PROFILE=$WORKER_PROFILE
EOF
```

- Install Karpenter with helm:

```sh
# Create the karpenter chart/helm repo
# https://artifacthub.io/packages/helm/karpenter/karpenter
helm repo add karpenter https://charts.karpenter.sh/

# Install it, without waiting 
helm upgrade --install --namespace karpenter \
  karpenter karpenter/karpenter \
  --version 0.16.3 \
  --set clusterName=${CLUSTER_NAME} \
  --set aws.defaultInstanceProfile=$WORKER_PROFILE \
  --set settings.cluster-endpoint=$KUBE_ENDPOINT 

```

- Apply patches to fix karpenter default deployment:

```sh
#
# Patches
#

# 1) remove webhooks
oc delete validatingwebhookconfiguration validation.webhook.config.karpenter.sh
oc delete validatingwebhookconfiguration validation.webhook.provisioners.karpenter.sh
oc delete mutatingwebhookconfiguration defaulting.webhook.provisioners.karpenter.sh

# 2) remove invalid SCC
      # securityContext:
      #   fsGroup: 1000

oc patch deployment.apps/karpenter --type=json -p="[{'op': 'remove', 'path': '/spec/template/spec/securityContext'}]"

# 3) Mount volumes/creds
oc set volume deployment.apps/karpenter --add -t secret -m /var/secrets/karpenter --secret-name=karpenter-aws-credentials --read-only=true

# 4) set env vars
oc set env deployment.apps/karpenter AWS_REGION=us-east-1 AWS_SHARED_CREDENTIALS_FILE=/var/secrets/karpenter/credentials CLUSTER_ENDPOINT=$KUBE_ENDPOINT
```

## Setup Karpenter

- Discover the node provisioner configuration from MAPI/MachineSet object:

```sh
AWS_REGION=us-east-1
INFRA_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
MACHINESET_NAME=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.name}')
MACHINESET_SUBNET_NAME=$(oc get machineset -n openshift-machine-api $MACHINESET_NAME -o json | jq -r '.spec.template.spec.providerSpec.value.subnet.filters[0].values[0]')
MACHINESET_SG_NAME=$(oc get machineset -n openshift-machine-api $MACHINESET_NAME -o json | jq -r '.spec.template.spec.providerSpec.value.securityGroups[0].filters[0].values[0]')
MACHINESET_INSTANCE_PROFILE=$(oc get machineset -n openshift-machine-api $MACHINESET_NAME -o json | jq -r '.spec.template.spec.providerSpec.value.iamInstanceProfile.id')
MACHINESET_AMI_ID=$(oc get machineset -n openshift-machine-api $MACHINESET_NAME -o json | jq -r '.spec.template.spec.providerSpec.value.ami.id')
MACHINESET_USER_DATA_SECRET=$(oc get machineset -n openshift-machine-api $MACHINESET_NAME -o json | jq -r '.spec.template.spec.providerSpec.value.userDataSecret.name')
MACHINESET_USER_DATA=$(oc get secret -n openshift-machine-api $MACHINESET_USER_DATA_SECRET -o jsonpath='{.data.userData}' | base64 -d)

cat <<EOF
AWS_REGION=$AWS_REGION
INFRA_NAME=$INFRA_NAME
MACHINESET_NAME=$MACHINESET_NAME
MACHINESET_SUBNET_NAME=$MACHINESET_SUBNET_NAME
MACHINESET_SG_NAME=$MACHINESET_SG_NAME
MACHINESET_INSTANCE_PROFILE=$MACHINESET_INSTANCE_PROFILE
MACHINESET_AMI_ID=$MACHINESET_AMI_ID
MACHINESET_USER_DATA_SECRET=$MACHINESET_USER_DATA_SECRET
MACHINESET_USER_DATA=$MACHINESET_USER_DATA
EOF
```

- Create Karpenter Provisioner and AWSNodeTemplate:

!!! tip "References"
    - [About Node Templates](https://karpenter.sh/v0.31/concepts/node-templates/)
    - [About Provisioners](https://karpenter.sh/v0.31/concepts/provisioners/)
    - [About NodePools](https://karpenter.sh/docs/concepts/nodepools/)


```sh
cat << EOF > ./kpt-provisioner-m6.yaml
# https://karpenter.sh/v0.30/concepts/provisioners/
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: "kpt-provisioner-m6"
spec:
  weight: 10
  consolidation:
    enabled: true
  labels:
    Environment: karpenter
  
  # Resource limits constrain the total size of the cluster.
  # Limits prevent Karpenter from creating new instances once the limit is exceeded.
  limits:
    resources:
      cpu: "1000"
      memory: 1000Gi
  labels:
    node-role.kubernetes.io/app: ""
    node-role.kubernetes.io/worker: ""
  requirements:
    - key: karpenter.k8s.aws/instance-category
      operator: In
      values: [m]
    - key: karpenter.k8s.aws/instance-generation
      operator: In
      values: ["6"]
    - key: "topology.kubernetes.io/zone"
      operator: In
      values: ["${AWS_REGION}a","${AWS_REGION}b","${AWS_REGION}c"]
    - key: "kubernetes.io/arch"
      operator: In
      values: ["amd64"]
    - key: "karpenter.sh/capacity-type"
      operator: In
      values: ["on-demand"]
    - key: "karpenter.k8s.aws/instance-cpu"
      operator: Gt
      values: ["2"]
    - key: "karpenter.k8s.aws/instance-memory"
      operator: Gt
      values: ["4096"]
    - key: "karpenter.k8s.aws/instance-pods"
      operator: Gt
      values: ["20"]
  providerRef:
    name: "kpt-${MACHINESET_NAME}"

---
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  name: "kpt-${MACHINESET_NAME}"
spec:
  subnetSelector:
    kubernetes.io/cluster/${INFRA_NAME}: owned
    kubernetes.io/role/internal-elb: ""
  securityGroupSelector:
    Name: "${MACHINESET_SG_NAME}"
  instanceProfile: "${MACHINESET_INSTANCE_PROFILE}"
  amiFamily: Custom
  tags:
    cluster_name: $CLUSTER_NAME
    Environment: autoscaler
  amiSelector:
    aws-ids: "${MACHINESET_AMI_ID}"
  userData: |
    $MACHINESET_USER_DATA
EOF

# Check if all vars have been replaced in ./kpt-provisioner-m6.yaml
less ./kpt-provisioner-m6.yaml

# Apply the config

oc create -f ./kpt-provisioner-m6.yaml
```


## Run scaling tests

```sh
oc create -f https://raw.githubusercontent.com/elmiko/openshift-lab-scaling/devel/setup.yaml
oc create -f https://raw.githubusercontent.com/elmiko/openshift-lab-scaling/devel/three-hour-scaling-test.yaml
```