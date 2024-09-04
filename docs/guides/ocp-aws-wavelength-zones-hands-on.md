# OCP on AWS Wavelength Zones (Hands-on)

- Guide 01) Installing with full automation (Day-0)
- Guide 02) Installing in existing VPC (Day-0)

## Prerequisites

The prerequisite for installing a cluster using AWS Wavelength Zones is to opt-in to every zone group.

The permission `ec2:ModifyAvailabilityZoneGroup` is required to enable the zone group. Make sure the user running the installer has it attached to. This is one example of IAM Policy that can be attached to the User or Role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:ModifyAvailabilityZoneGroup"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
```

## Guide 01 - Installing OCP extending compute to AWS Wavelength Zones

Create a cluster in the region `us-east-1` extending worker nodes to AWS Local Zone `us-east-1-bos-1a`:

- check the zone group name for the target zone (`us-east-1-wl1-bos-wlz-1`):

```sh
$ aws --region us-east-1 ec2 describe-availability-zones \
  --all-availability-zones \
  --filters Name=zone-name,Values=us-east-1-wl1-bos-wlz-1 \
  --query "AvailabilityZones[].GroupName" --output text
us-east-1-wl1
```

- opt-in to the Zone Group

```bash
aws ec2 modify-availability-zone-group \
    --region us-east-1 \
    --group-name us-east-1-wl1 \
    --opt-in-status opted-in
```

AWS will process the request in the background, it could take a few minutes. Check if field `OptInStatus` has the value `opted-in` before proceeding:

```bash
aws --region us-east-1 ec2 describe-availability-zones \
  --all-availability-zones \
  --filters Name=zone-name,Values=us-east-1-wl1-bos-wlz-1 \
  --query "AvailabilityZones[].OptInStatus"
```

- Create the `install-config.yaml`:

```yaml
apiVersion: v1
publish: External
baseDomain: devcluster.openshift.com
metadata:
  name: "cluster-name"
pullSecret: ...
sshKey: ...
platform:
  aws:
    region: us-east-1
compute:
- name: edge
  platform:
    aws:
      zones:
      - us-east-1-wl1-bos-wlz-1
```

> Draft

```sh
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.15.0-ec.2-x86_64"

CLUSTER_NAME=aws-wlz-23112004
INSTALL_DIR=${PWD}/installdir-${CLUSTER_NAME}
mkdir $INSTALL_DIR
cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: devcluster.openshift.com
platform:
  aws:
    region: us-east-1
controlPlane:
  platform:
    aws:
      zones:
      - us-east-1a
compute:
- name: worker
  platform:
    aws:
      zones:
      - us-east-1a
- name: edge
  platform:
    aws:
      zones:
      - us-east-1-wl1-bos-wlz-1
EOF

./openshift-install create manifests --dir $INSTALL_DIR

./openshift-install create cluster --dir $INSTALL_DIR

```

## Guide 02 - Installing OCP in exiting VPC (BYO VPC) extending nodes to AWS Wavelength Zones


```bash

mkdir  ~/openshift-labs/aws-wlz && cd ~/openshift-labs/aws-wlz

# Using Local installer: clone the repo to ~/go/src/github.com/mtulio/installer
ln -svf ~/go/src/github.com/mtulio/installer/upi/aws/cloudformation/01_vpc.yaml $TEMPLATE_NAME_VPC

TEMPLATE_NAME_VPC="./01_vpc.yaml"

export CLUSTER_REGION=us-east-1
export CLUSTER_NAME=wlz-byon03-8

export CIDR_VPC="10.0.0.0/16"

export STACK_VPC=${CLUSTER_NAME}-vpc
aws cloudformation create-stack \
  --region ${CLUSTER_REGION} \
  --stack-name ${STACK_VPC} \
  --template-body file://$TEMPLATE_NAME_VPC \
  --parameters \
    ParameterKey=VpcCidr,ParameterValue="${CIDR_VPC}" \
    ParameterKey=AvailabilityZoneCount,ParameterValue=2 \
    ParameterKey=SubnetBits,ParameterValue=12

aws --region $CLUSTER_REGION cloudformation wait stack-create-complete --stack-name ${STACK_VPC}
aws --region $CLUSTER_REGION cloudformation describe-stacks --stack-name ${STACK_VPC}

export VPC_ID=$(aws --region $CLUSTER_REGION cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId").OutputValue' )

## Create WLZ Gateway
TEMPLATE_NAME_CARRIER_GW="./01.01_carrier_gateway.yaml"

export STACK_CAGW=${CLUSTER_NAME}-cagw
aws cloudformation create-stack \
  --region ${CLUSTER_REGION} \
  --stack-name ${STACK_CAGW} \
  --template-body file://$TEMPLATE_NAME_CARRIER_GW \
  --parameters \
    ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
    ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}"

aws --region $CLUSTER_REGION cloudformation wait stack-create-complete --stack-name ${STACK_CAGW}
aws --region $CLUSTER_REGION cloudformation describe-stacks --stack-name ${STACK_CAGW}


# Setup prereq subnet
# AZ_NAME=$(aws --region $CLUSTER_REGION ec2 describe-availability-zones \
#   --filters Name=opt-in-status,Values=opted-in Name=zone-type,Values=wavelength-zone \
#   | jq -r .AvailabilityZones[].ZoneName | shuf | head -n1)
AZ_NAME="us-east-1-wl1-nyc-wlz-1"
AZ_SUFFIX=$(echo ${AZ_NAME/${CLUSTER_REGION}-/})

ZONE_GROUP_NAME=$(aws --region $CLUSTER_REGION ec2 describe-availability-zones \
  --filters Name=zone-name,Values=$AZ_NAME \
  | jq -r .AvailabilityZones[].GroupName)

aws --region $CLUSTER_REGION ec2 modify-availability-zone-group \
    --group-name "${ZONE_GROUP_NAME}" \
    --opt-in-status opted-in

export ROUTE_TABLE_PUB=$(aws --region $CLUSTER_REGION cloudformation describe-stacks \
  --stack-name ${STACK_CAGW} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PublicRouteTableId").OutputValue' )


#> Select the first route table from the list
export ROUTE_TABLE_PVT=$(aws --region $CLUSTER_REGION cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[]
    | select(.OutputKey=="PrivateRouteTableIds").OutputValue
    | split(",")[0] | split("=")[1]' \
)

SUBNET_CIDR_PUB="10.0.128.0/24"
SUBNET_CIDR_PVT="10.0.129.0/24"

cat <<EOF
CLUSTER_REGION=$CLUSTER_REGION
VPC_ID=$VPC_ID
AZ_NAME=$AZ_NAME
AZ_SUFFIX=$AZ_SUFFIX
ZONE_GROUP_NAME=$ZONE_GROUP_NAME
ROUTE_TABLE_PUB=$ROUTE_TABLE_PUB
ROUTE_TABLE_PVT=$ROUTE_TABLE_PVT
SUBNET_CIDR_PUB=$SUBNET_CIDR_PUB
SUBNET_CIDR_PVT=$SUBNET_CIDR_PVT
EOF

# Subnet
TEMPLATE_NAME_SUBNET="./01.99_subnet.yaml"

export STACK_SUBNET=${CLUSTER_NAME}-subnets-${AZ_SUFFIX}
aws cloudformation create-stack \
  --region ${CLUSTER_REGION} \
  --stack-name ${STACK_SUBNET} \
  --template-body file://$TEMPLATE_NAME_SUBNET \
  --parameters \
    ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
    ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}" \
    ParameterKey=ZoneName,ParameterValue="${AZ_NAME}" \
    ParameterKey=PublicRouteTableId,ParameterValue="${ROUTE_TABLE_PUB}" \
    ParameterKey=PublicSubnetCidr,ParameterValue="${SUBNET_CIDR_PUB}" \
    ParameterKey=PrivateRouteTableId,ParameterValue="${ROUTE_TABLE_PVT}" \
    ParameterKey=PrivateSubnetCidr,ParameterValue="${SUBNET_CIDR_PVT}"

aws --region $CLUSTER_REGION cloudformation wait stack-create-complete --stack-name ${STACK_SUBNET}
aws --region $CLUSTER_REGION cloudformation describe-stacks --stack-name ${STACK_SUBNET}


## Get the subnets

# Public Subnets from VPC Stack
# mapfile -t SUBNETS < <(aws --region $CLUSTER_REGION cloudformation describe-stacks \
#   --stack-name "${STACK_VPC}" \
#   | jq -r '.Stacks[0].Outputs[0].OutputValue' | tr ',' '\n')

mapfile -t SUBNETS < <(aws --region $CLUSTER_REGION cloudformation describe-stacks   --stack-name "${STACK_VPC}" --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetIds'].OutputValue" --output text | tr ',' '\n')

# Private Subnets from VPC Stack
# mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws --region $CLUSTER_REGION cloudformation describe-stacks \
#   --stack-name "${STACK_VPC}" \
#   | jq -r '.Stacks[0].Outputs[1].OutputValue' | tr ',' '\n')

mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws --region $CLUSTER_REGION cloudformation describe-stacks   --stack-name "${STACK_VPC}" --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetIds'].OutputValue" --output text | tr ',' '\n')

echo ${SUBNETS[@]}


# SELECT ONE subnet

# Public Edge Subnet
#mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws --region $CLUSTER_REGION cloudformation describe-stacks   --stack-name "${STACK_SUBNET}" --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetIds'].OutputValue" --output text | tr ',' '\n')

# Private Edge Subnet
mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws --region $CLUSTER_REGION cloudformation describe-stacks   --stack-name "${STACK_SUBNET}" --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetId'].OutputValue" --output text | tr ',' '\n')

echo ${SUBNETS[@]}


## Cluster config

export PULL_SECRET_FILE=${HOME}/.openshift/pull-secret-latest.json
export BASE_DOMAIN=devcluster.openshift.com
export SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

CLUSTER_NAME_VARIANT=${CLUSTER_NAME}-0
INSTALL_DIR=${CLUSTER_NAME_VARIANT}
mkdir $INSTALL_DIR

cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: ${BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME_VARIANT}"
platform:
  aws:
    region: ${CLUSTER_REGION}
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)
pullSecret: '$(cat ${PULL_SECRET_FILE} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

cp ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config.yaml.bkp


./openshift-install create manifests --dir $INSTALL_DIR

./openshift-install create cluster --dir $INSTALL_DIR --log-level=debug
```

## Guide 03 - Installing OCP with dev preview images without Wavelength Zones

Goal:

- Install OpenShift with images with support of Wavelength zones
- Test the regular public IP assignment using patched MAPI AWS Provider

Steps:

- Build the images with cluster-bot:

```sh
build 4.15.0-ec.1,openshift/installer#7369,openshift/machine-api-provider-aws#78
```

- Deploy the cluster creating a new MachineSet in regular Availability Zone, setting it to use public subnet created by installer:

```sh
oc adm release extract -a ~/.openshift/pull-secret-latest.json --tools registry.build05.ci.openshift.org/ci-ln-7mgy9hb/release:latest

tar xfz openshift-install-*.tar.gz

wget -O yq "https://github.com/mikefarah/yq/releases/download/v4.34.1/yq_linux_amd64"
chmod u+x yq

CLUSTER_NAME=aws-a415wlzmapi01
cat <<EOF > ./install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: devcluster.openshift.com
platform:
  aws:
    region: us-east-1
EOF

./openshift-install create manifests

MACHINE_SET_MANIFEST=./openshift/99_openshift-cluster-api_worker-machineset-0.yaml
SUBNET_NAME=$(yq eval .spec.template.spec.providerSpec.value.subnet.filters[0].values[0] openshift/99_openshift-cluster-api_worker-machineset-0.yaml | sed 's/private/public/')
MACHINESET_NAME_NEW=$(yq eval .metadata.name openshift/99_openshift-cluster-api_worker-machineset-0.yaml)-public

cat <<EOF > ./machineset-patch.yaml
metadata:
  name: ${MACHINESET_NAME_NEW}
spec:
  template:
    spec:
      providerSpec:
        value:
          publicIP: yes
          subnet:
            filters:
              - name: tag:Name
                values:
                  - $SUBNET_NAME
EOF

./yq eval-all '. as $item ireduce ({}; . * $item)' "${MACHINE_SET_MANIFEST}" ./machineset-patch.yaml > machineset-new.yaml

cp "${MACHINE_SET_MANIFEST}" machineset-current.yaml
cp  machineset-new.yaml "${MACHINE_SET_MANIFEST}.public.yaml"
```

- Check manifests:

```sh
$ ls ${MACHINE_SET_MANIFEST}*
./openshift/99_openshift-cluster-api_worker-machineset-0.yaml  ./openshift/99_openshift-cluster-api_worker-machineset-0.yaml.public.yaml
```

- Create cluster

```sh
./openshift-install create cluster --log-level debug
```

## deploying ALBO in Full IPI

```sh
ALBO_ZONE_NAME=$(oc get nodes -o wide -l node-role.kubernetes.io/edge -o json | jq -r '.items[0].metadata.labels["topology.kubernetes.io\/zone"]')

oc get machineset -n openshift-machine-api ${CLUSTER_NAME}-edge-${ALBO_ZONE_NAME}

SUBNET_NAME=$(oc get machineset -n openshift-machine-api ${CLUSTER_NAME}-edge-${ALBO_ZONE_NAME} -o jsonpath='{.spec.template.spec.providerSpec.value.subnet.filters[0].values[0]}')


```

## deploying ALBO in BYO VPC

```bash

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
```


## Testing MAPI 

Testing MAPI PR: https://github.com/openshift/machine-api-provider-aws/pull/78

Steps to install a cluster with custom release built upon installer and MAPI changes.

- create a release image:

cluster-bot:
```sh
build 4.15.0-ec.1,openshift/installer#7369,openshift/machine-api-provider-aws#78
```

- extract bimary from built image (get in the job provided by cluster-bot):

```sh
oc adm release extract -a ~/.openshift/pull-secret-latest.json --tools registry.build05.ci.openshift.org/ci-ln-8jsw5l2/release:latest

tar xfz openshift-install-*.tar.gz

wget -O yq "https://github.com/mikefarah/yq/releases/download/v4.34.1/yq_linux_amd64"
chmod u+x yq
```

- create install-config

```sh
CLUSTER_NAME=aws-a415wlzmapi01
cat <<EOF > ./install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: devcluster.openshift.com
platform:
  aws:
    region: us-east-1
compute:
- name: edge
  platform:
    aws:
      zones:
      - us-east-1-wl1-nyc-wlz-1
EOF
```

- create manifest

```sh
./openshift-install create manifests
```

- patch manifest

```sh
MACHINE_SET_MANIFEST=./openshift/99_openshift-cluster-api_worker-machineset-0.yaml
SUBNET_NAME=$(yq eval .spec.template.spec.providerSpec.value.subnet.filters[0].values[0] openshift/99_openshift-cluster-api_worker-machineset-0.yaml | sed 's/private/public/')

cat <<EOF > ./machineset-patch.yaml
spec:
  template:
    spec:
      providerSpec:
        value:
          publicIP: yes
          subnet:
            filters:
              - name: tag:Name
                values:
                  - $SUBNET_NAME
EOF

./yq eval-all '. as $item ireduce ({}; . * $item)' "${MACHINE_SET_MANIFEST}" ./machineset-patch.yaml > machineset-new.yaml

cp "${MACHINE_SET_MANIFEST}" machineset-current.yaml
cp  machineset-new.yaml "${MACHINE_SET_MANIFEST}"
```

- create cluster

```sh
./openshift-install create cluster --log-level debug
```

- Check the results

```sh
$ oc get machineset -n openshift-machine-api | grep nyc
aws-a415wlzmapi01-q92ft-edge-us-east-1-wl1-nyc-wlz-1   1         1         1       1           52m


$ oc get machines -n openshift-machine-api | grep nyc
aws-a415wlzmapi01-q92ft-edge-us-east-1-wl1-nyc-wlz-1-jg4wq   Running   r5.2xlarge   us-east-1   us-east-1-wl1-nyc-wlz-1   47m

MACHINE_NAME=$(oc get machines -n openshift-machine-api | grep nyc | awk '{print$1}')
INSTANCE_ID=$(oc get machines -n openshift-machine-api $MACHINE_NAME -o json | jq -r .status.providerStatus.instanceId)

$ oc get nodes -l node-role.kubernetes.io/edge -o json | jq '.items[0].status.addresses[] | select(.type=="ExternalDNS")'
{
  "address": "ec2-155-146-73-121.compute-1.amazonaws.com",
  "type": "ExternalDNS"
}

$ aws ec2 describe-instances --region us-east-1 --instance-ids $INSTANCE_ID  | jq '.Reservations[].Instances[].NetworkInterfaces[].Association'
{
  "CarrierIp": "155.146.73.121",
  "IpOwnerId": "amazon",
  "PublicDnsName": "ec2-155-146-73-121.compute-1.amazonaws.com"
}
```

#### Day 2:

Create a new MachineSet in public subnet in Wavelength Zone, setting the publicIP to allow MAPI privisioning the instance in WLZ subnet assigning the Carrier Public IP address to the network interface.

This example requires an existing MachineSet created in private subnet, then it will create a new one in public subnet.

- Create machineset configuration

```sh
PVT_MACHINESET=$(oc get machineset -n openshift-machine-api -o json | jq -r '.items[] | select(.metadata.name | contains("nyc")).metadata.name')

oc get machineset $PVT_MACHINESET -n openshift-machine-api -o yaml \
  | sed 's/private-us-east-1-wl1-nyc-wlz-1/public-us-east-1-wl1-nyc-wlz-1/' \
  > machineset-pub.yaml

cat <<EOF > ./machineset-patch.yaml
metadata:
  name: ${PVT_MACHINESET}-pub
spec:
  template:
    spec:
      providerSpec:
        value:
          publicIP: yes
EOF

./yq eval-all '. as $item ireduce ({}; . * $item)' ./machineset-pub.yaml ./machineset-patch.yaml | oc create -f -
```

- Check:

```sh
$ oc get machines -n openshift-machine-api -w |grep $PVT_MACHINESET

```

## e2e tests

References:

- https://github.com/openshift/origin/pull/28363
- https://issues.redhat.com//browse/OCPBUGS-23042
- https://github.com/openshift/origin/pull/28387
- https://issues.redhat.com//browse/OCPBUGS-22703

Steps:

```bash
oc get machines -A
export PULL_SECRET=$HOME/.openshift/pull-secret-latest.json
OPENSHIFT_TESTS_IMAGE=$(oc get is -n openshift tests -o=jsonpath='{.spec.tags[0].from.name}')
oc image extract -a ${PULL_SECRET} "${OPENSHIFT_TESTS_IMAGE}" --file="/usr/bin/openshift-tests"
chmod u+x openshift-tests

./openshift-tests run openshift/conformance --dry-run  | grep -E '^"\[' | shuf  | head -n 2 > ./tests-random.txt

./openshift-tests run --junit-dir ./junit-payload -f ./tests-random.txt | tee -a ./tests-random.log.txt

./openshift-tests-patch28363 run --junit-dir ./junit-patch28363 -f ./tests-random.txt | tee -a ./tests-random-patch28363.log.txt
```