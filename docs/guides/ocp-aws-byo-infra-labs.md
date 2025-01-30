# Deploying OpenShift on AWS bringing Your Own Infrastructure

This section describes how-to guides with quickly snippets/commands
to exercise the bring your own infrastructure (BYO) variants when deploying
an OpenShift cluster on AWS using `openshift-install`.

For more information about OpenShift install, check the
[official documentation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/preparing-to-install-on-aws.html)

Steps:

- Prerequisites
    - install awscli
    - install openshift-install
    - yq4
- Choose and Deploy your BYO infrastructure
    - BYO VPC
    - BYO subnet on AWS Local Zones
    - BYO subnet on AWS Wavelength
    - BYO Public IPv4 Pool (TODO)
    - BYO EIP (TODO)
    - BYO VPC with multi-CIDR blocks (TODO)
    - BYO VPC with multi-subnets in same zone (TODO)
    - BYO KMS Key (TODO)
    - BYO Security Group (TODO)
    - BYO Infra for private deployments (TODO)
- Create the install-config.yaml
    - Base install-config
    - Patch the configuration to BYO infra
        - BYO VPC
        - BYO subnet on AWS Local Zones
        - BYO subnet on AWS Wavelength
        - BYO VPC with multi-subnets in same zone
- Deploy OpenShift cluster on AWS

## Prerequisites

- Export environment variables used in the cluster:
```sh
export CLUSTER_NAME="byo-aws"
export CLUSTER_BASEDOMAIN="devcluster.openshift.com"
export PULL_SECRET_PATH="$HOME/.openshift/pull-secret-latest.json"
export SSH_KEYS="$(cat ~/.ssh/id_rsa.pub)"
export AWS_DEFAULT_REGION=us-east-1
export INSTALL_DIR="${PWD}/${CLUSTER_NAME}"

# Source and version URL to download the CloudFormation templates
export TEMPLATES_BASE=https://raw.githubusercontent.com/openshift/installer
export TEMPLATES_VERSION=master
export TEMPLATES_PATH=upi/aws/cloudformation
# Alternatively you can use SPLAT lab templates, uncomment to enable it
#TEMPLATES_BASE=https://raw.githubusercontent.com/openshift-splat-team/installer-labs
#TEMPLATES_VERSION=main
#TEMPLATES_PATH=installer-upi/aws/cloudformation/templates

TEMPLATE_URL=${TEMPLATES_BASE}/${TEMPLATES_VERSION}/${TEMPLATES_PATH}
TEMPLATES=()

function download_cloudformation_templates() {
  echo "Downloading Required CloudFormation Templates: ${TEMPLATES[*]}"
  for TEMPLATE in "${TEMPLATES[@]}"; do
    echo "Downloading ${TEMPLATE}"
    wget -O ${INSTALL_DIR}/${TEMPLATE} "${TEMPLATE_URL}/${TEMPLATE}"
  done
}
export -f download_cloudformation_templates

mkdir -vp ${INSTALL_DIR}
```
- Install `openshift-install`
- [Install `awscli` v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- Install `yq`:
```sh
yq_version=v4.34.2
yq_bin_arch=yq_linux_amd64
yq_url="https://github.com/mikefarah/yq/releases/download/${yq_version}/${yq_bin_arch}"
BIN_YQ=${PWD}/yq

wget -O ${BIN_YQ} ${yq_url} && chmod +x ${BIN_YQ}
```

## Choose and Deploy your BYO infrastructure

### BYO VPC

Create the network (VPC, subnets, Route Tables, gateways, etc):
```sh
# Download the CloudFormation Templates
TEMPLATES=( "01_vpc.yaml" )
download_cloudformation_templates

export STACK_VPC=${CLUSTER_NAME}-vpc

# Append the the parameter InfrastructureName if you are using the SPLAT's repo version:
# ParameterKey=InfrastructureName,ParameterValue=${CLUSTER_NAME} \
aws cloudformation create-stack --stack-name ${STACK_VPC} \
  --template-body file://${INSTALL_DIR}/template-vpc.yaml \
  --parameters \
    ParameterKey=VpcCidr,ParameterValue="10.0.0.0/16" \
    ParameterKey=AvailabilityZoneCount,ParameterValue=3 \
    ParameterKey=SubnetBits,ParameterValue=12

aws cloudformation wait stack-create-complete --stack-name ${STACK_VPC}

aws cloudformation describe-stacks --stack-name ${STACK_VPC}
```

### BYO subnet on AWS Local Zones

Steps to create subnets on Local Zone in New York location (`us-east-1-nyc-1a`):

  - enable the zone group
  - create the subnet in the Local Zone
```sh
# Adjust to yours
export AZ_NAME="us-east-1-nyc-1a"
export SUBNET_CIDR_PUB="10.0.128.0/24"
export SUBNET_CIDR_PVT="10.0.129.0/24"

## Hands on
# enable zone group
AZ_SUFFIX=$(echo ${AZ_NAME/${CLUSTER_REGION}-/})

ZONE_GROUP_NAME=$(aws ec2 describe-availability-zones \
  --filters Name=zone-name,Values=$AZ_NAME \
  | jq -r .AvailabilityZones[].GroupName)
ZONE_GROUP_STATUS=$(aws ec2 describe-availability-zones \
  --filters Name=zone-name,Values=$AZ_NAME \
  | jq -r .AvailabilityZones[].OptInStatus)

# Enable only when not opted-in to prevent errors
test ${ZONE_GROUP_STATUS} == "opted-in" || {
  aws ec2 modify-availability-zone-group \
  --group-name "${ZONE_GROUP_NAME}" \
  --opt-in-status opted-in; sleep 20; }

# Export the VPC ID
export VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId").OutputValue' )

# Export Route Table IDs (Public and Private)
export ROUTE_TABLE_PUB=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[]
    | select(.OutputKey=="PublicRouteTableId").OutputValue')

#> Select the first route table from the list
export ROUTE_TABLE_PVT=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[]
    | select(.OutputKey=="PrivateRouteTableIds").OutputValue
    | split(",")[0] | split("=")[1]')

# Create public and private subnet in Local Zones
# Download the CloudFormation Templates
TEMPLATES+=( "01_vpc_99_subnet.yaml" )
download_cloudformation_templates

TEMPLATE_NAME_SUBNET="${INSTALL_DIR}/01_vpc_99_subnet.yaml"
export STACK_SUBNET=${CLUSTER_NAME}-subnets-${AZ_SUFFIX}

aws cloudformation create-stack \
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

aws cloudformation wait stack-create-complete --stack-name ${STACK_SUBNET}
aws cloudformation describe-stacks --stack-name ${STACK_SUBNET}
```

### BYO subnet on AWS Wavelentth Zones

Steps to create subnets on Wavelength Zone in New York location (`us-east-1-wl1-nyc-wlz-1`):

  - enable the zone group
  - create the AWS VPC Carrier Gateway
  - create the subnet in the Wavelength Zone, with public subnet associated to the route table with default route to Carrier Gateway
```sh
# Adapt to yours
export AZ_NAME="us-east-1-wl1-nyc-wlz-1"
export SUBNET_CIDR_PUB="10.0.128.0/24"
export SUBNET_CIDR_PVT="10.0.129.0/24"

## Hands on
# enable zone group
AZ_SUFFIX=$(echo ${AZ_NAME/${CLUSTER_REGION}-/})

ZONE_GROUP_NAME=$(aws ec2 describe-availability-zones \
  --filters Name=zone-name,Values=$AZ_NAME \
  | jq -r .AvailabilityZones[].GroupName)
ZONE_GROUP_STATUS=$(aws ec2 describe-availability-zones \
  --filters Name=zone-name,Values=$AZ_NAME \
  | jq -r .AvailabilityZones[].OptInStatus)

# Enable only when not opted-in to prevent errors
test ${ZONE_GROUP_STATUS} == "opted-in" || {
    aws ec2 modify-availability-zone-group \
    --group-name "${ZONE_GROUP_NAME}" \
    --opt-in-status opted-in; sleep 20; }

# Create the Carrier Gateway and 'edge' route table
# Download the CloudFormation Templates
TEMPLATE_NAME_CARRIER_GW=01_vpc_01_carrier_gateway.yaml
TEMPLATE_NAME_SUBNET=01_vpc_99_subnet.yaml

TEMPLATES+=( "${TEMPLATE_NAME_CARRIER_GW}" )
TEMPLATES+=( "${TEMPLATE_NAME_SUBNET}" )
download_cloudformation_templates

# Export the VPC ID
export VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId").OutputValue' )

export STACK_CAGW=${CLUSTER_NAME}-cagw
aws cloudformation create-stack \
  --stack-name ${STACK_CAGW} \
  --template-body file://$TEMPLATE_NAME_CARRIER_GW \
  --parameters \
    ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
    ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}"

aws cloudformation wait stack-create-complete --stack-name ${STACK_CAGW}
aws cloudformation describe-stacks --stack-name ${STACK_CAGW}


# Extract Public Route Table ID from the Carrier Gateway stack
export ROUTE_TABLE_PUB=$(aws --region $CLUSTER_REGION cloudformation describe-stacks \
  --stack-name ${STACK_CAGW} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PublicRouteTableId").OutputValue')

# Extract Private Route Table ID from the Carrier Gateway stack
#> Select the first route table from the list
export ROUTE_TABLE_PVT=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[]
    | select(.OutputKey=="PrivateRouteTableIds").OutputValue
    | split(",")[0] | split("=")[1]')

# Create public and private subnet in Wavelength Zones
export STACK_SUBNET=${CLUSTER_NAME}-subnets-${AZ_SUFFIX}
aws cloudformation create-stack \
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

aws cloudformation wait stack-create-complete --stack-name ${STACK_SUBNET}
aws cloudformation describe-stacks --stack-name ${STACK_SUBNET}
```

### BYO VPC with multi-subnets in same zone

Create multiple subnets in the same zone to isolate cluster resources into dedicated subnets, suchh as:

- Deploy API's and Ingress LBs in dedicated subnet in zone A
- Deploy Control Plane nodes into different subnet in zone A

> TODO create AWS CloudFormation stack set to reuse AWS CloudFomration templates

### BYO Public IPv4 Pool

The prerequisite step is to have a Public IPv4 pool onboarded to the AWS Account.

After it is provisioned, no additional steps is required by OpenShift cluster installation, other than setting the Public IPv4 Pool ID to the install-config.yaml.

See [openshift-install parameter `platform.aws.publicIpv4Pool`](https://docs.openshift.com/container-platform/4.17/installing/installing_aws/installation-config-parameters-aws.html)

See AWS documentation to ["Bring your own IP addresses (BYOIP) to Amazon EC2"](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-byoip.html#byoip-onboard).

### BYO EIP

> TODO: There is no CloudFormation templates

> Implemented by EPs:
> -  https://github.com/openshift/enhancements/pull/1593
> - CORS https://github.com/openshift/enhancements/pull/1688

Check the CI step [spiked/blocked in release PR 56960](https://github.com/openshift/release/pull/56960):

```sh
EXPIRATION_DATE=$(date -d '4 hours' --iso=minutes --utc)
CLUSTER_NAME="${NAMESPACE}-${UNIQUE_HASH}"
TAGS="{Key=Name,Value=${CLUSTER_NAME}-eip-lb-ingress}"
TAGS+=",{Key=expirationDate,Value=${EXPIRATION_DATE}}"
TAGS+=",{Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared}"
TAGS+=",{Key=sigs.k8s.io/cluster-api-provider-aws/cluster/${CLUSTER_NAME},Value=shared}"
TAGS+=",{Key=sigs.k8s.io/cluster-api-provider-aws/role,Value=none}"

RESOURCE_TAGS="ResourceType=elastic-ip,Tags=[${TAGS}]"

echo "Creating Elastic IPs for each zone..."
# Create a new Elastic IP for each zones
for i in $(seq 0 $((zone_count - 1))); do
  aws ec2 allocate-address \
    --domain vpc \
    --region "${AWS_REGION}" \
    --tag-specifications "${RESOURCE_TAGS}" \
    --public-ipv4-pool "${pool_id}" > /tmp/eip-"${i}".json
done

eip_allocation_ids=$(jq -r '.AllocationId' /tmp/eip-*.json | paste -sd "," -)
```

There is additional work on CAPA to fully support BYO EIP, take a look at the following references:

- [CAPA spike to BYO EIP](https://github.com/kubernetes-sigs/cluster-api-provider-aws/compare/main...mtulio:cluster-api-provider-aws:spike-byo-eip?expand=1)
- [Installer Spike/PoC to BYO EIP for control plane components (API NLB, Bootstrap, and NAT GWs)](https://github.com/openshift/installer/compare/main...mtulio:installer:spike-byo-eip?expand=1#diff-eb33be4c39b4da2461546c7a4f59bce61f5b515fa6e2f7d71974b647f6f42a9e)

### BYO Infra for private deployments

> TODO/WIP Partial

Steps to create the infrastructure (VPC/network, Proxy and Bastion nodes, etc) for private deployments.

Check out the draft/notes [ocp-aws-private-one-time-deploy](https://mtulio.dev/guides/ocp-aws-private-one-time-deploy/).


## Create the install-config.yaml

```sh
cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: "${CLUSTER_BASEDOMAIN}"
metadata:
  name: "${CLUSTER_NAME}"
pullSecret: '$(cat ${PULL_SECRET_PATH} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  ${SSH_KEYS}
platform:
  aws:
    region: ${AWS_DEFAULT_REGION}
EOF
```

### Patch the configuration to BYO infra

Choose one or more adapting to your environment:

#### BYO VPC

Config for BYO VPC in regular zones:

- Extracts to variable `SUBNETS` the subnet IDs from CloudFormation stack for VPC (`STACK_VPC`)
- Creates the YAML patch file
- Patch the install-config.yaml
```sh
mapfile -t SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[0].OutputValue' | tr ',' '\n')

mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[1].OutputValue' | tr ',' '\n')

echo "Subnets (${#SUBNETS[@]}): ${SUBNETS[@]}"

# Create the patch for install-config.yaml
cat <<EOF > ${INSTALL_DIR}/install-config.patch.yaml
platform:
  aws:
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)
EOF

${BIN_YQ} -i ". *= load(\"${INSTALL_DIR}/install-config.patch.yaml\")" ${INSTALL_DIR}/install-config.yaml

grep -A 7 subnets ${INSTALL_DIR}/install-config.yaml
```

#### BYO subnet on AWS Local Zones

Steps to patch install-config to BYO VPC extending to Local Zone subnet:

- Prerequisite: BYO VPC
- Extracts to variable `SUBNETS` the subnet IDs from CloudFormation stack for VPC (`STACK_VPC`)
- Appends to variable `SUBNETS` the subnet IDs from CloudFormation stack for Local Zone subnet (`STACK_SUBNET`)
- Creates the YAML patch file
- Patch the install-config.yaml
```sh
# Extract the subnet IDs from regular zones
mapfile -t SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[0].OutputValue' | tr ',' '\n')

mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[1].OutputValue' | tr ',' '\n')

# Extracts the PublicSubnetId *or* PrivateSubnetId subnet ID to launch machines, depending of your use case.
# This need to be repeated for each additional zones / cloudformation stacks.
mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_SUBNET}" \
  --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetId'].OutputValue" \
  --output text)

echo "Subnets (${#SUBNETS[@]}): ${SUBNETS[@]}"

cat <<EOF > ${INSTALL_DIR}/install-config.patch.yaml
platform:
  aws:
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)
EOF

${BIN_YQ} -i ". *= load(\"${INSTALL_DIR}/install-config.patch.yaml\")" ${INSTALL_DIR}/install-config.yaml

grep -A 7 subnets ${INSTALL_DIR}/install-config.yaml
```

#### BYO subnet on AWS Wavelentth Zones

Steps to patch install-config to BYO VPC extending to Local Zone subnet:

- Prerequisite: BYO VPC
- Extracts to variable `SUBNETS` the subnet IDs from CloudFormation stack for VPC (`STACK_VPC`)
- Appends to variable `SUBNETS` the subnet IDs from CloudFormation stack for Local Zone subnet (`STACK_SUBNET`)
- Creates the YAML patch file
- Patch the install-config.yaml
```sh
# Extract the subnet IDs from regular zones
mapfile -t SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[0].OutputValue' | tr ',' '\n')

mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[1].OutputValue' | tr ',' '\n')

# Extracts the PublicSubnetId *or* PrivateSubnetId subnet ID to launch machines, depending of your use case.
# This need to be repeated for each additional zones / cloudformation stacks.
mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_SUBNET}" \
  --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetId'].OutputValue" \
  --output text)

echo "Subnets (${#SUBNETS[@]}): ${SUBNETS[@]}"

cat <<EOF > ${INSTALL_DIR}/install-config.patch.yaml
platform:
  aws:
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)
EOF

${BIN_YQ} -i ". *= load(\"${INSTALL_DIR}/install-config.patch.yaml\")" ${INSTALL_DIR}/install-config.yaml

grep -A 7 subnets ${INSTALL_DIR}/install-config.yaml
```

#### BYO VPC with multi-subnets in same zone

Patch install-config.yaml to use the new subnets API `platform.aws.vpc.subnets`
proposed by [EP #1634](https://github.com/openshift/enhancements/pull/1634):

> Ideally to reproduce in a fully private or fully public clusters to simulate two subnets in the same zone and scheme to distributed into LBs and Nodes

> Deploying a cluster on single zone in existing VPC with multiple zones may reproduce the BUG of CCM choosing all subnets instead of enforcing what installer is instructed

```sh
SUBNET_ID_ZONE1A_PRIVATE=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetIds'].OutputValue" \
  --output text | tr ',' '\n' | head -n1)
SUBNET_ID_ZONE1A_PUBLIC=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetIds'].OutputValue" \
  --output text | tr ',' '\n' | head -n1)

cat <<EOF > ${INSTALL_DIR}/install-config.patch.yaml
platform:
  aws:
    vpc:
      subnets:
      - id: ${SUBNET_ID_ZONE1A_PRIVATE}
          roles:
          - type: ClusterNode
          - type: ControlPlaneInternalLB
      - id: ${SUBNET_ID_ZONE1A_PUBLIC}
          roles:
          - type: Bootstrap
          - type: ControlPlaneExternalLB
          - type: IngressControllerLB
EOF

${BIN_YQ} -i ". *= load(\"${INSTALL_DIR}/install-config.patch.yaml\")" ${INSTALL_DIR}/install-config.yaml

grep -A 7 subnets ${INSTALL_DIR}/install-config.yaml
```


## Deploy OpenShift cluster on AWS

```sh
./openshift-install create cluster
```
