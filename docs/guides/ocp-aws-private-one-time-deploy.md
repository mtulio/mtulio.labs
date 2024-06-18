# OpenShift Private Hacking | one-time setup

> The **Quickly**, and **one-time** is a goal, is not yet achieved! xD

Quickly way to deploy OpenShift private/restricted mode on AWS.

## Prerequisites

- [Create deployment S3 Bucket and sync templates](./ocp-aws-private-01_00-pre.md)
- Build images
    - [Build proxy image (AMI)](./ocp-aws-private-01_01-build-image-squid-proxy.md)
    - [Build bastion host image (AMI)](./ocp-aws-private-01_01-build-image-ssm.md)
- [Create Proxy config and ignition file](./ocp-aws-private-03_00_proxy-01-config-TLS.md)
- [Create Bastion host config/ignition](./ocp-aws-private-03_bastion-01-config.md)

- Set environment variables for the project deployment:

```sh
REPO_ROOT=${HOME}/go/src/github.com/mtulio/mtulio.labs
# branch lab-ocp-aws-private: git clone git@github.com:mtulio/mtulio.labs.git -b lab-ocp-aws-private $REPO_ROOT

export CFN_STACK_PATH=${REPO_ROOT}/labs/ocp-install-iac/aws-cloudformation-templates
export RESOURCE_NAME_PREFIX=capa-pvt

export BUCKET_NAME="$RESOURCE_NAME_PREFIX"
export TEMPLATE_BASE_URL="https://${BUCKET_NAME}.s3.amazonaws.com"

export BYOVPC_DIR="${HOME}/openshift-labs/capa-private"
mkdir -p $BYOVPC_DIR

export REGION=us-east-1
export AWS_REGION=$REGION
export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
export DNS_BASE_DOMAIN=devcluster.openshift.com
export CLUSTER_VPC_CIDR="10.0.0.0/16"
```

- Upload templates to S3 (Only CloudFormation will access the templates)

```sh
#
# CloudFormateion Template in public Bucket
#
aws s3api create-bucket --bucket $BUCKET_NAME --region us-east-1
aws s3api put-public-access-block \
    --bucket ${BUCKET_NAME} \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=true
aws s3api put-bucket-policy \
    --bucket ${BUCKET_NAME} \
    --policy "{\"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Effect\": \"Allow\",
      \"Principal\": \"*\",
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${BUCKET_NAME}/*\",
      \"Condition\": {
        \"IpAddress\": {
          \"aws:SourceIp\": \"10.0.0.0/8\"
        }
      }
    }
  ]
}"

function update_templates() {
  local base_path="${1:-${SOURCE_DIR}/aws-cloudformation-templates}"
  for TEMPLATE in ${base_path}/*.yaml; do
    fname=$(basename $TEMPLATE)
    if [[ ! -f "$TEMPLATE" ]]; then
      echo "Template ${fname} not found in ${base_path}"
      continue
    fi
    aws s3 cp $base_path/$fname s3://$BUCKET_NAME/${fname}
  done
}

update_templates ${CFN_STACK_PATH}
```

## Deployment


### Proxy server configuration

- Run script from [proxy config](./ocp-aws-private-03_00_proxy-01-config-TLS.md):

```sh
WORKDIR=$BYOVPC_DIR
SOURCE_DIR="${CFN_STACK_PATH}/../"
config_proxy "01"
```

### Bastion server configuration

- Run script from [bastion config](./ocp-aws-private-03_bastion-01-config.md):

```sh
config_bastion "01"
export BASE_AMI_ID=$BASTION_AMI_ID
```

### One-time deploy

- Provision the resources (VPC, Proxy cluster and Bastion):

```sh
cat <<EOF
RESOURCE_NAME_PREFIX=${RESOURCE_NAME_PREFIX}
TEMPLATE_BASE_URL=$TEMPLATE_BASE_URL
CLUSTER_VPC_CIDR=$CLUSTER_VPC_CIDR
BASE_AMI_ID=$BASE_AMI_ID
PROXY_USER_DATA=$PROXY_USER_DATA
PROXY_DNS_HOSTED_ZONE_ID=$PROXY_DNS_HOSTED_ZONE_ID
PROXY_DNS_RECORD=$PROXY_DNS_RECORD
BASTION_USER_DATA=$BASTION_USER_DATA
EOF

# TODO Cfn
#> Cleanup old DNS RR for Proxy
#aws route53 change-resource-record-sets --hosted-zone-id $PROXY_DNS_HOSTED_ZONE_ID --change-batch file://tmp/payload.json


# Create a variant to prevent any 'duplication' of the template in CloudFormation
PREFIX_VARIANT="${RESOURCE_NAME_PREFIX}-07"

# Choose the template to setup the private install variant
##> 1/ VPC + Proxy HA (ASG+LB) + Bastion in private subnet
#INFRA_DEPLOY_TEMPLATE=${CFN_STACK_PATH}/stack_ocp_cluster_private-proxy-ha_bastion.yaml

##> 2/ VPC + Proxy (single EC2) + Bastion in private subnet (including SSM agent)
INFRA_DEPLOY_TEMPLATE=${CFN_STACK_PATH}/stack_ocp_cluster_private-proxy_bastion.yaml

##> 3/ VPC + Proxy (single EC2) w/ Bastion (public subnet)
#INFRA_DEPLOY_TEMPLATE=${CFN_STACK_PATH}/TODO.yaml

##> 4/ VPC + Bastion (public subnet), and NAT Gw to egress traffic
#INFRA_DEPLOY_TEMPLATE=${CFN_STACK_PATH}/TODO.yaml

# Deploy
export STACK_NAME="${PREFIX_VARIANT}"
aws cloudformation create-change-set \
--stack-name "${STACK_NAME}" \
--change-set-name "${STACK_NAME}" \
--change-set-type "CREATE" \
--template-body file://${INFRA_DEPLOY_TEMPLATE} \
--include-nested-stacks \
--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
--tags $TAGS \
--parameters \
  ParameterKey=VpcCidr,ParameterValue=${CLUSTER_VPC_CIDR} \
  ParameterKey=NamePrefix,ParameterValue=${PREFIX_VARIANT} \
  ParameterKey=TemplatesBaseURL,ParameterValue="${TEMPLATE_BASE_URL}" \
  ParameterKey=BaseAmiId,ParameterValue="${BASE_AMI_ID}" \
  ParameterKey=ProxyUserData,ParameterValue="${PROXY_USER_DATA}" \
  ParameterKey=ProxyDnsHostedZoneId,ParameterValue="${PROXY_DNS_HOSTED_ZONE_ID}" \
  ParameterKey=ProxyDnsRecordName,ParameterValue="${PROXY_DNS_RECORD}" \
  ParameterKey=BastinoUserData,ParameterValue="${BASTION_USER_DATA}"


aws cloudformation describe-change-set \
--stack-name "${STACK_NAME}" \
--change-set-name "${STACK_NAME}"

sleep 40
aws cloudformation execute-change-set \
    --change-set-name "${STACK_NAME}" \
    --stack-name "${STACK_NAME}"

aws cloudformation wait stack-create-complete \
    --region ${AWS_REGION} \
    --stack-name "${STACK_NAME}"

```

### Create tunnels

#### Tunneling using proxy to forward port

- Discover Proxy IP and open required tunnels:

```sh
VPC_ID=$(aws cloudformation describe-stacks --stack-name $STACK_NAME | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="VpcId").OutputValue')

# Discover Proxy public IP
export PROXY_PUBLIC_IP=$(aws ec2 describe-instances --filters Name=vpc-id,Values=$VPC_ID | jq -r '.Reservations[].Instances[] | select(.PublicIpAddress != null).PublicIpAddress')

# Discover Bastion private IP
export BASTION_PRIVATE_IP=$(aws ec2 describe-instances --filters Name=vpc-id,Values=$VPC_ID | jq -r ".Reservations[].Instances[] | select(.PublicIpAddress != \"$PROXY_PUBLIC_IP\").PrivateIpAddress")
export BASTION_PORT_SSH_LOCAL=2225

cat <<EOF
BASTION_PRIVATE_IP=$BASTION_PRIVATE_IP
PROXY_PUBLIC_IP=$PROXY_PUBLIC_IP
BASTION_PORT_SSH_LOCAL=$BASTION_PORT_SSH_LOCAL
EOF

# Tunnel to Bastion SSH
ssh -L 127.0.0.1:${BASTION_PORT_SSH_LOCAL}:${BASTION_PRIVATE_IP}:22 core@${PROXY_PUBLIC_IP}
```

#### Tunneling using SSM to forward port from bastion node

> TODO / consolidated existing MDs

### Install from Bastion

#### Export updater functions

```sh
function update_installer_from_bin() {
  install_path=$1
  ssh -p ${BASTION_PORT_SSH_LOCAL} core@localhost "mkdir ~/bin"
  scp -P ${BASTION_PORT_SSH_LOCAL} ${install_path} core@localhost:~/bin/openshift-install
}

function update_config() {
  cluster_name=$1; shift
  config_path=$1
  ssh -p ${BASTION_PORT_SSH_LOCAL} core@localhost "mkdir $cluster_name"
  scp -P ${BASTION_PORT_SSH_LOCAL} $config_path core@localhost:~/$cluster_name/install-config.yaml
}
```

#### Update installer binary

- Update from local build

```sh
update_installer_from_bin $(which $INSTALLER_BIN)
```

- Update from a release/CI image

```sh
# TODO
```


#### Generate install-config.yaml

- Discover parameters

```sh
export CLUSTER_NAME="${RESOURCE_NAME_PREFIX}-00"
export INSTALL_DIR="${BYOVPC_DIR}/${CLUSTER_NAME}"
mkdir -vp $INSTALL_DIR

# Discover VPC ID
# TODO export VpcId in the cloudformation output
VPC_ID=$(aws ec2 describe-instances --instance-ids $(aws cloudformation describe-stacks --stack-name $STACK_NAME | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="BastionNodeInstanceId").OutputValue') | jq -r '.Reservations[].Instances[].VpcId')

# TODO export private subnets
# For ipv4
FILTER_PRIVATE_SUBNET_OPT=MapPublicIpOnLaunch
# For ipv6
#FILTER_PRIVATE_SUBNET_OPT=AssignIpv6AddressOnCreation
mapfile -t SUBNETS < <(aws ec2 describe-subnets --filters Name=vpc-id,Values=${VPC_ID} --query "Subnets[?$FILTER_PRIVATE_SUBNET_OPT==\`false\`].SubnetId" --output text | tr '[:space:]' '\n')
```

- Discover VPC Endpoint address

```sh
function discover_vpce() {
aws ec2 describe-vpc-endpoints --region ${AWS_REGION} \
  --filters Name=vpc-id,Values=$VPC_ID \
  --query 'VpcEndpoints[].DnsEntries[0].DnsName' | jq -r .[] \
  > ${INSTALL_DIR}/ec2-aws-vpce-dns.txt

  echo "    serviceEndpoints:" > ${INSTALL_DIR}/config-vpce.txt
  echo -ne "169.254.169.254,$CLUSTER_VPC_CIDR" > ${INSTALL_DIR}/config-noproxy.txt
  while read line; do
    service_name=$(echo $line | awk -F'.' '{print$2}');
    service_url="https://$line";

    case $service_name in
      "ssm"|"ssmmessages"|"ec2messages"|"kms"|"sts") continue ;;
    esac

    echo -e "    - name: ${service_name}\n      url: ${service_url}" >> ${INSTALL_DIR}/config-vpce.txt
    echo -ne ",$line" >> ${INSTALL_DIR}/config-noproxy.txt
  done <${INSTALL_DIR}/ec2-aws-vpce-dns.txt
}

discover_vpce
```

- Validate required vars:

```sh
# Vars should not be empty
cat <<EOF
INSTALL_DIR=$INSTALL_DIR
CLUSTER_NAME=$CLUSTER_NAME
BASE_DOMAIN=$DNS_BASE_DOMAIN
AWS_REGION=$AWS_REGION
CLUSTER_VPC_CIDR=$CLUSTER_VPC_CIDR
SUBNETS=${SUBNETS[*]}
PULL_SECRET_FILE=$PULL_SECRET_FILE
SSH_PUB_KEY_FILE=$SSH_PUB_KEY_FILE
PROXY_SERVICE_URL_TLS=$PROXY_SERVICE_URL_TLS
PROXY_SERVICE_URL=$PROXY_SERVICE_URL
INTERMEDIATE=$INTERMEDIATE
EOF

# Files must exists
CONF_FILES=("${INSTALL_DIR}/config-vpce.txt" )
CONF_FILES+=("${PULL_SECRET_FILE}" )
CONF_FILES+=("${SSH_PUB_KEY_FILE}" )
CONF_FILES+=("${INTERMEDIATE}/certs/ca-chain.cert.pem")
CONF_FILES+=("${INSTALL_DIR}/config-noproxy.txt")
for FL in ${CONF_FILES[@]}; do test -f $FL || echo "File not found: $FL"; done
```

- Generate install-config.yaml

```sh
cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: Internal
credentialsMode: Mint
baseDomain: ${DNS_BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
networking:
  machineNetwork:
  - cidr: ${CLUSTER_VPC_CIDR}
platform:
  aws:
    region: ${AWS_REGION}
$(<${INSTALL_DIR}/config-vpce.txt)
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)

pullSecret: '$(cat ${PULL_SECRET_FILE} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(<${SSH_PUB_KEY_FILE})

proxy:
  httpsProxy: ${PROXY_SERVICE_URL_TLS}
  httpProxy: ${PROXY_SERVICE_URL}
  noProxy: $(<${INSTALL_DIR}/config-noproxy.txt)
additionalTrustBundle: |
$(cat ${INTERMEDIATE}/certs/ca-chain.cert.pem | awk '{print "  "$0}')
EOF
```

- Copy install-config.yaml to bastion node (private install using proxy)

```sh
update_config "${CLUSTER_NAME}" "${INSTALL_DIR}/install-config.yaml"
```

- Copy AWS creds to install a cluster

```sh
# TODO: install with EC2 credentials; Check installer support retrieving creds from inst metadata.
ssh -p "$BASTION_PORT_SSH_LOCAL" core@localhost "mkdir ~/.aws; cat <<EOF>~/.aws/credentials
[default]
aws_access_key_id=$(grep -A2 '\[default\]' ~/.aws/credentials | grep ^aws_access_key_id | awk -F'=' '{print$2}')
aws_secret_access_key=$(grep -A2 '\[default\]' ~/.aws/credentials | grep ^aws_secret_access_key | awk -F'=' '{print$2}')
#sts_regional_endpoints = regional
EOF"
```

- Run installer (connect to the bastion node)

> Note 1: `${INSTALL_DIR}` env var may not be exported in the bastion, replace it

> Note 2: connect to the bastion using SSH tunnel `core@localhost:$BASTION_PORT_SSH_LOCAL`

```sh
# Proxy vars must be exported to connect to cloud APIs
export $(cat /etc/proxy.env | xargs) || true
export $(cat /etc/installer.env | xargs) || true

# run installer
OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.16.0-rc.4-x86_64" \
openshift-install create cluster --log-level=debug --dir ${INSTALL_DIR}
```

- (Optional) extract clients to bastion

```sh
RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:4.16.0-rc.4-x86_64"
scp -P "$BASTION_PORT_SSH_LOCAL" ${PULL_SECRET_FILE} core@localhost:~/.dockercfg

function extract_clients() {
  RELEASE_CONAINER=$(podman create --name release $RELEASE_IMAGE)
  podman cp release:/release-manifests/image-references /tmp/release-references

  INSTALLER_IMAGE=$(jq -r '.spec.tags[] | select(.name=="installer").from.name' /tmp/release-references)
  OC_IMAGE=$(jq -r '.spec.tags[] | select(.name=="cli").from.name' /tmp/release-references)

  CONTAINER_INSTALLER=$(podman create --name installer --replace --authfile $PULL_SECRET $INSTALLER_IMAGE)
  CONTAINER_OC=$(podman create --name cli --replace --authfile $PULL_SECRET $OC_IMAGE)

  mkdir -vp ~/bin
  version=$(basename $RELEASE_IMAGE | awk -F':' '{print$2}')

  echo "Saving installer to ~/bin/openshift-install-${version}"
  podman cp installer:/usr/bin/openshift-install ~/bin/openshift-install-${version}

  echo "Saving oc to ~/bin/oc-${version}"
  podman cp cli:/usr/bin/oc ~/bin/oc-${version}

  podman rm installer cli release
}
extract_clients
```


> More scripts to unrevised [file](./ocp-aws-private-one-time-deploy.draft-unrevised.md)


## Destroy

- Destroy cluster

- Destroy Stack

- Destroy bucket
