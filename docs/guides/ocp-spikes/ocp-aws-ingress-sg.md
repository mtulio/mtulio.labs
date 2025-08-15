# OpenShift Spikes | Service type-LoadBalancer NLB with Security Groups

Note: This is a notebook/playbook of exploring/hacking controller for kube resource Service for type-LoadBalancer on CCM/ALBC. More details in https://github.com/openshift/enhancements/pull/1802 

## Install OpenShift cluster (self-managed)

- Install OCP cluster from a custom release built by cluster-bot:

> NOTES e2e tests for https://github.com/openshift/installer/pull/9681:

```sh
# Step 1) built an OCP release with all PRs using cluster-bot
# Step 2)
# CHANGE ME
export version=v39
BUILD_CLUSTER=build10
CI_JOB=ci-ln-5wdr0g2

# Step 3) Run steps below to create a cluster, optionally with local installer binary

export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="registry.${BUILD_CLUSTER}.ci.openshift.org/${CI_JOB}/release:latest"
#unset OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE

export INSTALL_DIR=$PWD/install-dir/install-${version}
mkdir -p $INSTALL_DIR

#cat install-dir/install-config-CIO2.yaml | sed "s/sg-v4/sg-${version}/" > ${INSTALL_DIR}/install-config.yaml
cat install-dir/install-config-regular.yaml | sed "s/sg-v4/sg-${version}/" > ${INSTALL_DIR}/install-config.yaml
cat install-dir/install-config-regular-compact.yaml | sed "s/sg-v4/sg-${version}/" > ${INSTALL_DIR}/install-config.yaml

export OPENSHIFT_INSTALL_REENTRANT=true
export INSTALL_COMMAND=./install-dir/openshift-install
export INSTALL_COMMAND=./openshift-install-4.20ec2
export INSTALL_COMMAND=./openshift-install
export INSTALL_COMMAND=./openshift-install-4.20ec3
#./openshift-install create manifests --log-level=debug --dir $INSTALL_DIR
$INSTALL_COMMAND create cluster --log-level=debug --dir $INSTALL_DIR

#./openshift-install create cluster --log-level=debug --dir $INSTALL_DIR
```

Troubleshooting the cluster - replace CCM images in live cluster:
```sh
# Step 1) Define the release image to extract CCM image
BUILT_RELEASE="registry.build06.ci.openshift.org/ci-ln-t5fttvb/release:latest"

# Step 2) Scale down the managed operators and replace the controller image in the deployment

# Replace CCM controller image manually

# Scale down the managers
oc scale --replicas=0 deployment.apps/cluster-version-operator -n openshift-cluster-version

oc scale --replicas=0 deployment.apps/cluster-cloud-controller-manager-operator -n openshift-cloud-controller-manager-operator

oc scale --replicas=0 deployment.apps/aws-cloud-controller-manager -n openshift-cloud-controller-manager

CCM_IMAGE=$(oc adm release info $BUILT_RELEASE --image-for aws-cloud-controller-manager)

oc patch deployment.apps/aws-cloud-controller-manager \
-n openshift-cloud-controller-manager \
  --type='json' \
  -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/image\", \"value\": \"${CCM_IMAGE}\"}]"

oc get pods -o yaml   -n  openshift-cloud-controller-manager |grep -i image:

oc logs $(oc get pods -l infrastructure.openshift.io/cloud-controller-manager=AWS  -n  openshift-cloud-controller-manager -o jsonpath='{.items[1].metadata.name}')     -n  openshift-cloud-controller-manager

oc logs -f deployment.apps/aws-cloud-controller-manager -n openshift-cloud-controller-manager
```

Demo notes/draft:
```sh
##
Demo notes:

- Show The task/problem statement/challenges
- The idea is to explore the alternatives, impacted components, and propose solution
- share the enhancement and collected ideas
- share the e2e demo

##
$ yq ea .platform.aws install-dir/install-config-CIO2.yaml 
region: us-east-1
defaultMachinePlatform:
  zones: ["us-east-1a"]
lbType: NLB
ingressController:
  securityGroupEnabled: True

$ oc get cm cluster-config-v1 -o yaml -n kube-system -o yaml | yq  ea '.data["install-config"]' - | yq -j ea '.platform.aws' - | jq -r '.|{lbType, ingressController}'
{
  "lbType": "NLB",
  "ingressController": {
    "securityGroupEnabled": true
  }
}

# Validation:
$ dig +short $(oc get service/router-default  -n openshift-ingress -ojson | jq -r .status.loadBalancer.ingress[].hostname)
44.216.25.189
$ dig +short $(basename $(oc whoami --show-console ))
44.216.25.189

$ ROUTER_DNS_NAME=$(oc get service/router-default  -n openshift-ingress -ojson | jq -r .status.loadBalancer.ingress[].hostname)

$ aws elbv2 describe-load-balancers | jq ".LoadBalancers[] | select(.DNSName==\"${ROUTER_DNS_NAME}\").SecurityGroups"
[
  "sg-03e514570a2ac0e2c"
]

$ oc get service/router-default  -n openshift-ingress -o yaml | yq ea .metadata.annotations -
service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold: "2"
service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval: "10"
service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout: "4"
service.beta.kubernetes.io/aws-load-balancer-healthcheck-unhealthy-threshold: "2"
service.beta.kubernetes.io/aws-load-balancer-security-groups: 'mrb-sg-v7-474wp-ingress-lb'
service.beta.kubernetes.io/aws-load-balancer-type: nlb
traffic-policy.network.alpha.openshift.io/local-with-fallback: ""
```

### Running CCM locally

```sh
oc scale --replicas=0 deployment.apps/cluster-version-operator -n openshift-cluster-version

oc scale --replicas=0 deployment.apps/cluster-cloud-controller-manager-operator -n openshift-cloud-controller-manager-operator

oc scale --replicas=0 deployment.apps/aws-cloud-controller-manager -n openshift-cloud-controller-manager

# https://github.com/openshift/cluster-cloud-controller-manager-operator/blob/3486b5c01e32eb8375a503da49fe623ac83fcb98/pkg/cloud/aws/assets/deployment.yaml#L37

# Get current cloud-config
export CLOUD_CONFIG=$PWD/ccm-config
oc get cm cloud-conf -n openshift-cloud-controller-manager -o json | jq -r '.data["cloud.conf"]' > $CLOUD_CONFIG

CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag-key,Values=kubernetes.io/cluster/${CLUSTER_ID}" --query Vpcs[].VpcId --output text)
SUBNET_ID_PUBLIC=$(aws ec2 describe-subnets \
--filters Name=vpc-id,Values=$VPC_ID Name=tag:sigs.k8s.io/cluster-api-provider-aws/role,Values=public \
--query 'Subnets[0].SubnetId' \
--output text)

# Patch it to work correctly to run locally:
cat << EOF >> $CLOUD_CONFIG
NLBSecurityGroupMode = Managed
Region = us-east-1
VPC = $VPC_ID
SubnetID = $SUBNET_ID_PUBLIC
KubernetesClusterTag = $CLUSTER_ID
EOF

export AWS_REGION=us-east-1
export AWS_SHARED_CREDENTIALS_FILE=$HOME/.aws/credentials-splat

./aws-cloud-controller-manager -v=2 \
--cloud-config="${CLOUD_CONFIG}" \
--kubeconfig="${KUBECONFIG}" \
--cloud-provider=aws \
--use-service-account-credentials=true \
--configure-cloud-routes=false \
--leader-elect=true \
--leader-elect-lease-duration=137s \
--leader-elect-renew-deadline=107s \
--leader-elect-retry-period=26s \
--leader-elect-resource-namespace=openshift-cloud-controller-manager
```

## Create Sample Application

Deploy a sample APP to validate services:

```sh
APP_NAME_BASE=app-sample
APP_NAMESPACE=$APP_NAME_BASE

oc create ns $APP_NAMESPACE

cat << EOF | oc create -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME_BASE
  namespace: $APP_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP_NAME_BASE
  template:
    metadata:
      labels:
        app: $APP_NAME_BASE
    spec:
      containers:
      - image: ealen/echo-server:latest
        imagePullPolicy: IfNotPresent
        name: $APP_NAME_BASE
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: "8080"
EOF
```

## Manual Testing CCM and ALBC Service interface to provision type-LoadBalancer NLB

The tests described in this section are example of services exercising the specific features using different controllers, such as CCM (Cloud Controller Manager) and ALBC (AWS Load Balancer Controller).

Some tests requires ALBC, you need to follow the [following guides](./ocp-aws-ingress-sg-albc.md) as prerequisite:
- Installing ALBC with ALBO (follows ALBC released by OpenShift)
- Installing ALBC with Helm (usually latest ALBC version)


Prerequisites:
- CCM running: if you need to run locally, read the [development guide](https://github.com/kubernetes/cloud-provider-aws/blob/master/docs/development.md) to get started
- ALBC using the desired method mentioned in the last paragraph


### Test Case 1) User defalt Service type-LoadBalancer controller (CCM):

```sh
SVC_NAME=$APP_NAME_BASE-svc-ccm2
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
spec:
  selector:
    app: $APP_NAME_BASE
  ports:
    - name: http80
      port: 80
      targetPort: 8080
      protocol: TCP
  type: LoadBalancer
EOF

# two ports
SVC_NAME=$APP_NAME_BASE-svc-ccm2
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
spec:
  selector:
    app: $APP_NAME_BASE
  ports:
    - name: http80
      port: 80
      targetPort: 8080
      protocol: TCP
    - name: http81
      port: 81
      targetPort: 8080
      protocol: TCP
  type: LoadBalancer
EOF
```

```sh
LB_DNS=$(oc get svc $SVC_NAME -n ${APP_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

aws elbv2 describe-tags --resource-arns $(aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select(.DNSName==\"$LB_DNS\").LoadBalancerArn") | jq .TagDescriptions[].Tags

[
  {
    "Key": "kubernetes.io/service-name",
    "Value": "app-albc/app-albc-svc-ccm"
  },
  {
    "Key": "kubernetes.io/cluster/mrb-sg-v36-zvcgr",
    "Value": "owned"
  }
]
```

BYO SG

```sh
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag-key,Values=kubernetes.io/cluster/${CLUSTER_ID}" --query Vpcs[].VpcId --output text)

aws ec2 create-security-group \
--description="${CLUSTER_ID}-sg-byo-myapp" \
--group-name="BYO SG sample for service myapp" \
--vpc-id="${VPC_ID}" \
--tag-specifications "ResourceType=security-group,Tags=[{Key=kubernetes.io/cluster/${CLUSTER_ID},Value=shared}]"
```

### Test Case 2) Using `loadBalancerClass` to take over ALBC the Service type-LoadBalancer controller:

Service LoadBalancer NLB with ALBC using loadBalancerClass

- Making the CCM delegates to ALBC to create load balancers using `loadBalancerClass`:
> > NOTE: by default this behavior does not provision SGs. Is the ALBC controller provided by ALBO older than 2.6.0? https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/nlb/#security-group
> Using classes - example provisioning a service type loadBalancer with ALBC:
> - https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/nlb/#configuration



```sh
SVC_NAME=$APP_NAME_BASE-svc-albc
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
spec:
  selector:
    app: $APP_NAME_BASE
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: LoadBalancer
  loadBalancerClass: service.k8s.aws/nlb
EOF
```

- Check tags
```sh
LB_DNS=$(oc get svc $SVC_NAME -n ${APP_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

$ aws elbv2 describe-tags --resource-arns $(aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select(.DNSName==\"$LB_DNS\").LoadBalancerArn") | jq .TagDescriptions[].Tags
[
  {
    "Key": "service.k8s.aws/stack",
    "Value": "app-albc/app-albc-svc-albc"
  },
  {
    "Key": "service.k8s.aws/resource",
    "Value": "LoadBalancer"
  },
  {
    "Key": "elbv2.k8s.aws/cluster",
    "Value": "mrb-sg-v36-zvcgr"
  }
]

```

### Test Case 3) Using `external` provider to take over to ALBC the Service type-LoadBalancer controller:

- Making the CCM delegates to ALBC to create load balancers using annotations:
> NOTE: by default this behavior does not provision SGs

```sh
SVC_NAME=$APP_NAME_BASE-svc-albc-ext
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: instance
spec:
  selector:
    app: $APP_NAME_BASE
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: LoadBalancer
EOF

LB_DNS=$(oc get svc $SVC_NAME -n ${APP_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

aws elbv2 describe-tags --resource-arns $(aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select(.DNSName==\"$LB_DNS\").LoadBalancerArn") | jq .TagDescriptions[].Tags
```

Results:
```json
[
  {
    "Key": "service.k8s.aws/stack",
    "Value": "app-albc/app-albc-svc-albc-annot"
  },
  {
    "Key": "service.k8s.aws/resource",
    "Value": "LoadBalancer"
  },
  {
    "Key": "elbv2.k8s.aws/cluster",
    "Value": "mrb-sg-v36-zvcgr"
  }
]
```

## Automated e2e with openshift-tests

Explore existing tests in the test framework:
```sh
VERSION=$(oc get clusterversion version  -o jsonpath='{.status.desired.version}')
ARCH=x86_64
TESTS_IMAGE=$(oc adm release info --image-for=tests -a ${PULL_SECRET_FILE} \
    quay.io/openshift-release-dev/ocp-release:${VERSION}-${ARCH})

oc image extract $TESTS_IMAGE -a ${PULL_SECRET_FILE} \
    --file="/usr/bin/openshift-tests"
chmod u+x ./openshift-tests

# TODO grep loadbalancer tests
```

## Automated e2e with e2e.tests (ginkgo)

```sh
# Make the test binary
make e2e.test

# List available tests
$ ./e2e.test --ginkgo.dry-run | grep -E '\[cloud-provider-aws-e2e'

# Run the loadBalancer tests
 ./e2e.test --ginkgo.v  --ginkgo.focus 'loadbalancer'

```


## Install managed clusters

### Installing ROSA Classic

https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_rosa_classic_clusters/index

```sh
CLUSTER_NAME="mrb-rosa0"
CLUSTER_REGION="us-east-1"
CLUSTER_VERSION="4.18.9"
#COMPUTE_TYPE="m5.xlarge"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

$ rosa create account-roles --mode auto --yes --prefix "${CLUSTER_NAME}"

rosa create cluster --cluster-name "${CLUSTER_NAME}" \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-HCP-ROSA-Installer-Role" \
  --support-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-HCP-ROSA-Support-Role" \
  --worker-iam-role "arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-HCP-ROSA-Worker-Role" \
  --region "${CLUSTER_REGION}" \
  --version "${CLUSTER_VERSION}" \
  --multi-az \
  --replicas 3 \
  --compute-machine-type "${COMPUTE_TYPE}" \
  --machine-cidr 10.0.0.0/16 \
  --service-cidr 172.30.0.0/16 \
  --pod-cidr 10.128.0.0/14 \
  --host-prefix 23 \
  --yes
```

### Installing ROSA HCP

### Prerequisites

- Enroll ROSA
- Link to Account

### Steps to deploy a cluster 

Steps based in official docs to 'Create a cluster':
https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html-single/install_rosa_with_hcp_clusters/index



```sh
export AWS_PROFILE=my-account
export AWS_REGION=us-east-1

rosa login --token="xxx"
rosa create account-roles --mode auto

rosa create network

rosa create cluster

rosa create operator-roles --cluster mrb-rosa

rosa create oidc-provider --cluster mrb-rosa

rosa describe cluster -c mrb-rosa

rosa logs install -c mrb-rosa --watch

cat <<EOF >./rosa-creds
ROSA_CLUSTER=cluster-name
ROSA_ADMIN="cluster-admin"
ROSA_ADMIN_PASS="pass"
KUBECONFIG=$PWD/rosa-kubeconfig
EOF

source ./rosa-creds

export OPENSHIFT_API_URL=$(rosa describe cluster --cluster=$ROSA_CLUSTER  -o json | jq -r '.api.url')
oc login --server=$OPENSHIFT_API_URL \
  --user $ROSA_ADMIN \
  --password $ROSA_ADMIN_PASS
```


### Installing hypershift

```sh
HC_CLUSTER_NAME=mrb-hc0

BASE_DOMAIN=devcluster.openshift.org
#aws route53 create-hosted-zone --name $BASE_DOMAIN --caller-reference $(whoami)-$(date --rfc-3339=date)

export BUCKET_NAME=$HC_CLUSTER_NAME
aws s3api create-bucket --bucket $BUCKET_NAME
aws s3api delete-public-access-block --bucket $BUCKET_NAME
echo '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}' | envsubst > policy.json
aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://policy.json


REGION=us-east-1
#BUCKET_NAME=your-bucket-name
AWS_CREDS="$HOME/.aws/credentials"

./hypershift-cli install \
  --oidc-storage-provider-s3-bucket-name $BUCKET_NAME \
  --oidc-storage-provider-s3-credentials $AWS_CREDS \
  --oidc-storage-provider-s3-region $REGION \
  --enable-defaulting-webhook true


REGION=us-east-1
WK_CLUSTER_NAME=$HC_CLUSTER_NAME-wk2
BASE_DOMAIN=devcluster.openshift.com
AWS_CREDS="$HOME/.aws/credentials"
PULL_SECRET="$PULL_SECRET_FILE"

./hypershift-cli create cluster aws \
  --name $WK_CLUSTER_NAME \
  --node-pool-replicas=2 \
  --base-domain $BASE_DOMAIN \
  --pull-secret $PULL_SECRET_FILE \
  --aws-creds $AWS_CREDS \
  --region $REGION \
  --generate-ssh
```


## Validating bugs

### SG error while Service Port update

https://github.com/kubernetes/cloud-provider-aws/issues/1206

```sh

# Testing patch
SVC_NAME=$APP_NAME_BASE-svc-clb1
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
spec:
  selector:
    app: $APP_NAME_BASE
  ports:
    - name: http80
      port: 80
      targetPort: 8080
      protocol: TCP
  type: LoadBalancer
EOF


kubectl patch service $SVC_NAME -n ${APP_NAMESPACE} --type=json \
  --patch '[{"op": "add", "path": "/spec/ports/-", 
    "value": {"name":"http81","port":81,"protocol":"TCP","targetPort":8080}}]'

curl -v $(oc get svc $SVC_NAME -n ${APP_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):81
```

### SG leak on BYO SG update on CLB

[CCM-AWS Issue 1208](https://github.com/kubernetes/cloud-provider-aws/issues/1208)

```sh
# Step 1: Create CLB service
SVC_NAME=$APP_NAME_BASE-clb-sg1
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
spec:
  selector:
    app: $APP_NAME_BASE
  ports:
    - name: http80
      port: 80
      targetPort: 8080
      protocol: TCP
  type: LoadBalancer
EOF

# Step 2: Check the CLB SG
LB_DNS=$(oc get svc $SVC_NAME -n ${APP_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

$ aws elb describe-load-balancers | jq -r ".LoadBalancerDescriptions[] | select(.DNSName==\"$LB_DNS\")|(.LoadBalancerName, .SecurityGroups)"
a341df09f30f94b78b5c33371eec8bac
[
  "sg-022da65a3d6e1d9ba"
]

SG_ID_ORIGINAL=$(aws elb describe-load-balancers | jq -r ".LoadBalancerDescriptions[] | select(.DNSName==\"$LB_DNS\").SecurityGroups | .[0]")

echo $SG_ID_ORIGINAL

# Step 3: Create a SG to be added ot BYO SG annotation
CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')

VPC_ID=$(aws elb describe-load-balancers | jq -r ".LoadBalancerDescriptions[] | select(.DNSName==\"$LB_DNS\").VPCId")

SG_NAME="${SVC_NAME}-byosg"
SG_ID=$(aws ec2 create-security-group \
--vpc-id="${VPC_ID}" \
--group-name="${SG_NAME}" \
--description="BYO SG sample for service ${SVC_NAME}" \
--tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${SG_NAME}},{Key=kubernetes.io/cluster/${CLUSTER_ID},Value=shared}]" \
| tee -a | jq -r .GroupId)

$ echo $SG_ID
sg-019ce8390024660f0

# Step 4: Patch the service with BYO SG
kubectl patch service ${SVC_NAME} -n ${APP_NAMESPACE} --type=merge \
  --patch '{"metadata":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-security-groups":"'$SG_ID'"}}}'

# Step 5: Check SG has been added to CLB
$ kubectl get service ${SVC_NAME} -n ${APP_NAMESPACE} -o yaml | yq4 ea .metadata.annotations
service.beta.kubernetes.io/aws-load-balancer-security-groups: sg-019ce8390024660f0

$ aws elb describe-load-balancers | jq -r ".LoadBalancerDescriptions[] | select(.DNSName==\"$LB_DNS\")|(.LoadBalancerName, .SecurityGroups)"
a341df09f30f94b78b5c33371eec8bac
[
  "sg-019ce8390024660f0"
]

$ aws ec2 describe-network-interfaces \
    --filters "Name=group-id,Values=$SG_ID" \
    --output json | jq -r '.NetworkInterfaces[] | "\(.NetworkInterfaceId) - \(.Description) - \(.Status)"'
eni-01667c7da28262a73 - ELB a341df09f30f94b78b5c33371eec8bac - in-use
eni-0fbdb2e1df215869c - ELB a341df09f30f94b78b5c33371eec8bac - in-use

# Step 6: Check if original SG has not been cleaned (bug/leaked)

## SG exists / not deleted
$ aws ec2 describe-security-groups --group-ids $SG_ID_ORIGINAL \
    --query 'SecurityGroups[].{"name":GroupName, "tags":Tags}' \
    --output json
[
    {
        "name": "k8s-elb-a341df09f30f94b78b5c33371eec8bac",
        "tags": [
            {
                "Key": "KubernetesCluster",
                "Value": "mrb-sg-xknls"
            },
            {
                "Key": "kubernetes.io/cluster/mrb-sg-xknls",
                "Value": "owned"
            }
        ]
    }
]

## SG not linked to any ENI

$ aws ec2 describe-network-interfaces \
--filters "Name=group-id,Values=$SG_ID_ORIGINAL" \
--output json \
| jq -r '.NetworkInterfaces[] | "\(.NetworkInterfaceId) - \(.Description) - \(.Status)"'
<empty>
```

## IPv6 NLB


```sh
SVC_NAME=$APP_NAME_BASE-nlb
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
spec:
  selector:
    app: $APP_NAME_BASE
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: LoadBalancer
EOF

SVC_NAME=$APP_NAME_BASE-clb
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
spec:
  selector:
    app: $APP_NAME_BASE
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: LoadBalancer
EOF

```

### TargetGroup attributes modification test cases

```sh

# Step 1) Create the service changing the attribute
# delete existing router
SVC_NAME=router-default
APP_NAMESPACE=${APP_NAMESPACE}
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: $APP_NAMESPACE
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
    service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: preserve_client_ip.enabled=false,proxy_protocol_v2.enabled=true
spec:
  type: LoadBalancer
  selector:
    ingresscontroller.operator.openshift.io/deployment-ingresscontroller: default
  externalTrafficPolicy: Local
  internalTrafficPolicy: Cluster
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: http
  - name: https
    port: 443
    protocol: TCP
    targetPort: https
  type: LoadBalancer
EOF

SVC_NAME=router-default2
APP_NAMESPACE=openshift-ingress
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: $APP_NAMESPACE
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
    service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: preserve_client_ip.enabled=false,proxy_protocol_v2.enabled=true
spec:
  type: LoadBalancer
  selector:
    ingresscontroller.operator.openshift.io/deployment-ingresscontroller: default
  externalTrafficPolicy: Local
  internalTrafficPolicy: Cluster
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: http
  - name: https
    port: 443
    protocol: TCP
    targetPort: https
  type: LoadBalancer
EOF

# Step 2) Check if the attribute has been set to the target group
LB_DNS=$(oc get svc $SVC_NAME -n ${APP_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

aws elbv2 describe-target-group-attributes --target-group-arn $(aws elbv2 describe-target-groups --load-balancer-arn  $(aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select(.DNSName==\"$LB_DNS\").LoadBalancerArn") | jq -r .TargetGroups[].TargetGroupArn)  | jq -r '.Attributes[] | select(.Key=="preserve_client_ip.enabled")'
{
  "Key": "preserve_client_ip.enabled",
  "Value": "true"
}

# Step 3) Remove the annotation 
kubectl patch service $SVC_NAME -n ${APP_NAMESPACE} --type=json \
  --patch '[{"op": "remove", "path": "/metadata/annotations[\"service.beta.kubernetes.io/aws-load-balancer-target-group-attributes\"]"}]'

kubectl patch service $SVC_NAME -n ${APP_NAMESPACE} --type=merge \
--patch '{"metadata":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-target-group-attributes":"preserve_client_ip.enabled=false"}}}'

$ kubectl get service $SVC_NAME -n ${APP_NAMESPACE} -o json |jq .metadata.annotations
null


# Step 3) Check if the original/desired value has been restored
aws elbv2 describe-target-group-attributes --target-group-arn $(aws elbv2 describe-target-groups --load-balancer-arn  $(aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select(.DNSName==\"$LB_DNS\").LoadBalancerArn") | jq -r .TargetGroups[].TargetGroupArn)  | jq -r '.Attributes[] | select(.Key=="preserve_client_ip.enabled")'
```

https://aws.amazon.com/blogs/networking-and-content-delivery/preserving-client-ip-address-with-proxy-protocol-v2-and-network-load-balancer/

### TargetGroup attributes modification tests with ALBC

Testing ALBC with custom attributes with valid for hairpin:
```sh

# Old (CCM) annotation pattern
SVC_NAME=$APP_NAME_BASE-albc-srcoff-old
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: preserve_client_ip.enabled=false
spec:
  selector:
    app: $APP_NAME_BASE
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: LoadBalancer
  loadBalancerClass: service.k8s.aws/nlb
EOF

# Documentation pattern
SVC_NAME=$APP_NAME_BASE-albc-srcoff-doc
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
  annotations:
    alb.ingress.kubernetes.io/target-group-attributes: preserve_client_ip.enabled=false
spec:
  selector:
    app: $APP_NAME_BASE
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: LoadBalancer
  loadBalancerClass: service.k8s.aws/nlb
EOF
```

Testing ALBC with custom attributes with invalid values:

```sh
SVC_NAME=$APP_NAME_BASE-albc-attb-invalid
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
  annotations:
    alb.ingress.kubernetes.io/target-group-attributes: myattrib=false
spec:
  selector:
    app: $APP_NAME_BASE
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: LoadBalancer
  loadBalancerClass: service.k8s.aws/nlb
EOF

LB_DNS=$(oc get svc $SVC_NAME -n ${APP_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

aws elbv2 describe-tags --resource-arns $(aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select(.DNSName==\"$LB_DNS\").LoadBalancerArn") | jq .TagDescriptions[].Tags
```

## Testing proxy on CIO

https://redhat-internal.slack.com/archives/CCH60A77E/p1752869482105659?thread_ts=1745435593.239899&cid=CCH60A77E

```sh
TBD
```
