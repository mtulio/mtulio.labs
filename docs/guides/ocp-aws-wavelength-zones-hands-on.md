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

## Guide 01 - Installing OCP in extending nodes to AWS Wavelength Zones

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
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.15.0-ec.1-x86_64"

CLUSTER_NAME=aws-a415wlz04
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

TEMPLATE_NAME_VPC="./template-vpc.yaml"
TEMPLATE_NAME_NET_PUBLIC="./template-net-public.yaml"
TEMPLATE_NAME_NET_PRIVATE="./template-net-private.yaml"

# Using Local installer: clone the repo to ~/go/src/github.com/mtulio/installer
ln -svf ~/go/src/github.com/mtulio/installer/upi/aws/cloudformation/01_vpc.yaml $TEMPLATE_NAME_VPC
ln -svf ~/go/src/github.com/mtulio/installer/upi/aws/cloudformation/01.99_net_public.yaml $TEMPLATE_NAME_NET_PUBLIC
ln -svf ~/go/src/github.com/mtulio/installer/upi/aws/cloudformation/upi/aws/cloudformation/01.99_net_private.yaml $TEMPLATE_NAME_NET_PRIVATE


export CLUSTER_REGION=us-east-1
export CLUSTER_NAME=wlz-byon02

export CIDR_VPC="10.0.0.0/16"

export STACK_VPC=${CLUSTER_NAME}-vpc
aws cloudformation create-stack \
  --region ${CLUSTER_REGION} \
  --stack-name ${STACK_VPC} \
  --template-body file://$TEMPLATE_NAME_VPC \
  --parameters \
    ParameterKey=VpcCidr,ParameterValue="${CIDR_VPC}" \
    ParameterKey=AvailabilityZoneCount,ParameterValue=3 \
    ParameterKey=SubnetBits,ParameterValue=12

aws --region $CLUSTER_REGION cloudformation wait stack-create-complete --stack-name ${STACK_VPC}
aws --region $CLUSTER_REGION cloudformation describe-stacks --stack-name ${STACK_VPC}

export VPC_ID=$(aws --region $CLUSTER_REGION cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId").OutputValue' )

## Create WLZ Gateway
TEMPLATE_NAME_CARRIER_GW="./template-net-cagw.yaml"
ln -svf ~/go/src/github.com/mtulio/installer/upi/aws/cloudformation/01.01_carrier_gateway.yaml $TEMPLATE_NAME_CARRIER_GW

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
TEMPLATE_NAME_SUBNET="./template-net-subnet.yaml"
ln -svf ~/go/src/github.com/mtulio/installer/upi/aws/cloudformation/01.99_subnet.yaml $TEMPLATE_NAME_SUBNET

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
mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws --region $CLUSTER_REGION cloudformation describe-stacks   --stack-name "${STACK_SUBNET}" --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetIds'].OutputValue" --output text | tr ',' '\n')

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