# Script for blog: Extending Red Hat OpenShift Container Platform to AWS Local Zones

## Prerequisites

- AWS CLI
- Templates

~~~bash
oc adm release extract --tools quay.io/openshift-release-dev/ocp-release:4.13.1-x86_64 -a ~/.openshift/pull-secret-latest.json
tar xfz openshift-install-linux-4.13.1.tar.gz
~~~

## Steps

- Install a cluster

~~~bash
export CLUSTER_NAME=demo-lz
export CLUSTER_BASEDOMAIN="devcluster.openshift.com"
export PULL_SECRET_PATH="$HOME/.openshift/pull-secret-latest.json"
export SSH_KEYS="$(cat ~/.ssh/id_rsa.pub)"
export AWS_REGION=us-east-1

# VPC
export STACK_VPC=${CLUSTER_NAME}-vpc
aws cloudformation create-stack --stack-name ${STACK_VPC} \
     --template-body file://template-vpc.yaml \
     --parameters \
        ParameterKey=ClusterName,ParameterValue=${CLUSTER_NAME} \
        ParameterKey=VpcCidr,ParameterValue="10.0.0.0/16" \
        ParameterKey=AvailabilityZoneCount,ParameterValue=3 \
        ParameterKey=SubnetBits,ParameterValue=12

aws cloudformation wait stack-create-complete --stack-name ${STACK_VPC}
aws cloudformation describe-stacks --stack-name ${STACK_VPC}

# Local Zone subnet
export STACK_LZ=${CLUSTER_NAME}-lz-nyc-1a
export ZONE_GROUP_NAME=${AWS_REGION}-nyc-1

export VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId").OutputValue' )

export VPC_RTB_PUB=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PublicRouteTableId").OutputValue' )

aws ec2 modify-availability-zone-group \
    --group-name "${ZONE_GROUP_NAME}" \
    --opt-in-status opted-in

aws cloudformation create-stack --stack-name ${STACK_LZ} \
     --template-body file://template-lz.yaml \
     --parameters \
        ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}" \
        ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
        ParameterKey=PublicRouteTableId,ParameterValue="${VPC_RTB_PUB}" \
        ParameterKey=LocalZoneName,ParameterValue="${ZONE_GROUP_NAME}a" \
        ParameterKey=LocalZoneNameShort,ParameterValue="nyc-1a" \
        ParameterKey=PublicSubnetCidr,ParameterValue="10.0.128.0/20"

aws cloudformation wait stack-create-complete --stack-name ${STACK_LZ} 

aws cloudformation describe-stacks --stack-name ${STACK_LZ}


mapfile -t SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[0].OutputValue' | tr ',' '\n')

mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[1].OutputValue' | tr ',' '\n')

# Set the SUBNET_ID to be used later
export SUBNET_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_LZ}" \
  | jq -r .Stacks[0].Outputs[0].OutputValue)

# Append the Local Zone subnet to the subnet ID list
SUBNETS+=(${SUBNET_ID})

cat <<EOF > ${PWD}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: "${CLUSTER_BASEDOMAIN}"
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${AWS_REGION}
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)
pullSecret: '$(cat ${PULL_SECRET_PATH} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  ${SSH_KEYS}
EOF

grep -A 7 subnets ${PWD}/install-config.yaml

cp ${PWD}/install-config.yaml ${PWD}/install-config.yaml-bkp

./openshift-install create manifests

ls manifests/cluster-network-*
ls openshift/99_openshift-cluster-api_worker-machineset-*

./openshift-install create cluster


# Wait for the cluster creation

export KUBECONFIG=$PWD/auth/kubeconfig
oc get nodes -l node-role.kubernetes.io/edge

oc get machineset -n openshift-machine-api
oc get machine -n openshift-machine-api
~~~

## Create new node in Day 2

- create zone in bue

~~~bash
# Local Zone subnet
export STACK_LZ=${CLUSTER_NAME}-lz-bue-1a
export ZONE_GROUP_NAME=${AWS_REGION}-bue-1
export CIDR_BLOCK=10.0.144.0/20

export VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId").OutputValue' )

export VPC_RTB_PUB=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PublicRouteTableId").OutputValue' )

aws ec2 modify-availability-zone-group \
    --group-name "${ZONE_GROUP_NAME}" \
    --opt-in-status opted-in

aws cloudformation create-stack --stack-name ${STACK_LZ} \
     --template-body file://template-lz.yaml \
     --parameters \
        ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}" \
        ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
        ParameterKey=PublicRouteTableId,ParameterValue="${VPC_RTB_PUB}" \
        ParameterKey=LocalZoneName,ParameterValue="${ZONE_GROUP_NAME}a" \
        ParameterKey=LocalZoneNameShort,ParameterValue="bue-1a" \
        ParameterKey=PublicSubnetCidr,ParameterValue="${CIDR_BLOCK}"

aws cloudformation wait stack-create-complete --stack-name ${STACK_LZ} 

aws cloudformation describe-stacks --stack-name ${STACK_LZ}

export SUBNET_ID_BUE=$(aws cloudformation describe-stacks --stack-name "${STACK_LZ}" \
  | jq -r .Stacks[0].Outputs[0].OutputValue)
~~~

- Create machineset
~~~bash
aws ec2 describe-instance-type-offerings \
    --location-type availability-zone \
    --filters Name=location,Values=${AWS_REGION}-bue-1a \
    --region ${AWS_REGION}

export INSTANCE_BUE=m5.2xlarge

BASE_MANIFEST=$(oc get machineset -n openshift-machine-api -o jsonpath='{range .items[*].metadata}{.name}{"\n"}{end}' | grep nyc-1)
oc get machineset -n openshift-machine-api $BASE_MANIFEST -o yaml > machineset-lz-bue-1a.yaml

# replace the subnet ID from NYC to BUE
sed -si "s/${SUBNET_ID}/${SUBNET_ID_BUE}/g" machineset-lz-bue-1a.yaml

# replace the zone reference from NYC to BUE
sed -si "s/nyc-1/bue-1/g" machineset-lz-bue-1a.yaml

# replace the instance type to a new one
current_instance=$(oc get machineset -n openshift-machine-api $BASE_MANIFEST -o jsonpath='{.spec.template.spec.providerSpec.value.instanceType}')
sed -si "s/${current_instance}/${INSTANCE_BUE}/g" machineset-lz-bue-1a.yaml

oc create -f machineset-lz-bue-1a.yaml

oc get machines -w -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=edge
~~~

## Installing ALB Operator (not covered by the blog / out of scope)

~~~bash
# Tag the VPC (PATCH)
## https://docs.aws.amazon.com/cli/latest/reference/ec2/create-tags.html
VPC_ID=$(aws ec2 describe-subnets --subnet-ids ${SUBNETS[0]} --query 'Subnets[0].VpcId' --output text)
INFRA_ID="$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')"
TAG_KEY="kubernetes.io/cluster/${INFRA_ID}"

# Check and tag VPC when not exists
aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].Tags[].Key' --output text | grep $TAG_KEY || aws ec2 create-tags --resources $VPC_ID --tags Key=$TAG_KEY,Value=shared


# Install using OLM
oc create namespace aws-load-balancer-operator
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


cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: aws-load-balancer-operator
  namespace: aws-load-balancer-operator
spec:
  targetNamespaces:
  - aws-load-balancer-operator
EOF

cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: aws-load-balancer-operator
  namespace: aws-load-balancer-operator
spec:
  channel: stable-v0
  installPlanApproval: Automatic 
  name: aws-load-balancer-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc get installplan -n aws-load-balancer-operator

sleep 60

oc get all -n aws-load-balancer-operator

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

oc get all -n aws-load-balancer-operator
~~~