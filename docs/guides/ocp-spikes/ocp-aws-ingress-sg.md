# OpenShift Spikes | Service type-LoadBalancer NLB with Security Groups

Note: This is a notebook/playbook of exploring/hacking controller for kube resource Service for type-LoadBalancer on CCM/ALBC. More details in https://github.com/openshift/enhancements/pull/1802 

## Install OpenShift cluster (self-managed)

- Install OCP cluster from a custom release built by cluster-bot:

> NOTES e2e tests for https://github.com/openshift/installer/pull/9681:

```sh
# Step 1) built an OCP release with all PRs using cluster-bot
# Step 2)
# CHANGE ME
export version=v36
BUILD_CLUSTER=build10
CI_JOB=ci-ln-5wdr0g2

# Step 3) Run steps below to create a cluster, optionally with local installer binary

export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="registry.${BUILD_CLUSTER}.ci.openshift.org/${CI_JOB}/release:latest"
#unset OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE

export INSTALL_DIR=$PWD/install-dir/install-${version}
mkdir -p $INSTALL_DIR

#cat install-dir/install-config-CIO2.yaml | sed "s/sg-v4/sg-${version}/" > ${INSTALL_DIR}/install-config.yaml
cat install-dir/install-config-regular.yaml | sed "s/sg-v4/sg-${version}/" > ${INSTALL_DIR}/install-config.yaml

export OPENSHIFT_INSTALL_REENTRANT=true
export INSTALL_COMMAND=./install-dir/openshift-install
export INSTALL_COMMAND=./openshift-install-4.20ec2
export INSTALL_COMMAND=./openshift-install
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

## Manual Testing CCM and ALBC Service interface to provision type-LoadBalancer NLB

The tests below are executed in a cluster with ALBC and CCM.

The tests are purely with purpose to understa the mechanism ALBC provides to use in parallel ALBC and CCM with Service type-LoadBalancer resource.

Those options are based in the ALBC configuration: 

### Prerequisites: Install ALBC with ALBO


```sh
# Create the Credentials for the Operator:
ALBO_NS=aws-load-balancer-operator
oc create namespace $ALBO_NS

cat << EOF| oc create -f -
apiVersion: cloudcredential.openshift.io/v1
kind: CredentialsRequest
metadata:
  name: aws-load-balancer-operator
  namespace: openshift-cloud-credential-operator
spec:
  providerSpec:
    apiVersion: cloudcredential.openshift.io/v1
    kind: AWSProviderSpec
    statementEntries:
      - action:
          - ec2:DescribeSubnets
        effect: Allow
        resource: "*"
      - action:
          - ec2:CreateTags
          - ec2:DeleteTags
        effect: Allow
        resource: arn:aws:ec2:*:*:subnet/*
      - action:
          - ec2:DescribeVpcs
        effect: Allow
        resource: "*"
  secretRef:
    name: aws-load-balancer-operator
    namespace: aws-load-balancer-operator
  serviceAccountNames:
    - aws-load-balancer-operator-controller-manager
EOF

# Install the Operator from OLM:
cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: $ALBO_NS
  namespace: $ALBO_NS
spec:
  targetNamespaces:
  - $ALBO_NS
EOF

# Create the subscription:
cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: $ALBO_NS
  namespace: $ALBO_NS
spec:
  channel: stable-v0
  installPlanApproval: Automatic 
  name: $ALBO_NS
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Wait for install-plan approved
oc get installplan -w -n $ALBO_NS

# check controller is running
oc get all -n $ALBO_NS
oc get pods -w -n $ALBO_NS


# Create cluster ALBO controller
cat <<EOF | oc create -f -
apiVersion: networking.olm.openshift.io/v1alpha1
kind: AWSLoadBalancerController 
metadata:
  name: cluster 
spec:
  subnetTagging: Auto 
  ingressClass: cloud 
  config:
    replicas: 2 
  enabledAddons: 
    - AWSWAFv2
EOF

# Wait for the pod becamig running
oc get pods -w -n $ALBO_NS -l app.kubernetes.io/name=aws-load-balancer-operator
```

- Deploy an APP, optional:

```sh
APP_NAME=app-albc
APP_NAMESPACE=$APP_NAME


oc create ns $APP_NAMESPACE

cat << EOF | oc create -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
  namespace: $APP_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      containers:
      - image: ealen/echo-server:latest
        imagePullPolicy: IfNotPresent
        name: $APP_NAME
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: "8080"
EOF
```


### Test Case 1) User defalt Service type-LoadBalancer controller (CCM):

```sh
SVC_NAME=$APP_NAME-svc-ccm
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
    app: $APP_NAME
  ports:
    - port: 80
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

### Test Case 2) Using `loadBalancerClass` to take over ALBC the Service type-LoadBalancer controller:

Service LoadBalancer NLB with ALBC using loadBalancerClass

- Making the CCM delegates to ALBC to create load balancers using `loadBalancerClass`:
> > NOTE: by default this behavior does not provision SGs. Is the ALBC controller provided by ALBO older than 2.6.0? https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/nlb/#security-group
> Using classes - example provisioning a service type loadBalancer with ALBC:
> - https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/nlb/#configuration



```sh
SVC_NAME=$APP_NAME-svc-albc
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
spec:
  selector:
    app: $APP_NAME
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
LB_DNS=$(oc get svc $APP_NAME-svc-albc -n ${APP_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

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
SVC_NAME=$APP_NAME-svc-albc-ext
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
    app: $APP_NAME
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

## Automated e2e

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
