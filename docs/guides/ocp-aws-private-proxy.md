# Install an OCP cluster on AWS in private subnets with proxy

!!! warning "Experimental steps"
    The steps described on this page are experimental, as usual on my lab's website! =]

!!! info "CloudFormation templates"
    The CloudFormation templates mentioned on this page are available in the path:
    [mtulio.labs/labs/labs/ocp-install-iac/aws-cloudformation-templates](https://github.com/mtulio/mtulio.labs/tree/master/labs/ocp-install-iac/aws-cloudformation-templates)

Install an OCP cluster on AWS with private subnets with proxy using AWS VPC PrivateLink.


Reference:
- https://aws.amazon.com/blogs/networking-and-content-delivery/how-to-use-aws-privatelink-to-secure-and-scale-web-filtering-using-explicit-proxy/

- https://aws.amazon.com/privatelink/

- https://aws.amazon.com/privatelink/pricing/

- https://docs.openshift.com/container-platform/4.14/installing/installing_aws/installing-aws-private.html

- ci-operator/step-registry/ipi/conf/aws/blackholenetwork/ipi-conf-aws-blackholenetwork-commands.sh
- ci-operator/step-registry/ipi/conf/aws/proxy/ipi-conf-aws-proxy-commands.sh

## Prerequisites

### Global variables

```sh
CLUSTER_NAME=pvt1
CLUSTER_VPC_CIDR=10.0.0.0/16

RESOURCE_NAME_PREFIX="lab-ci"
AWS_REGION=us-east-1
```

### Tools

The tools/binaries must be installed in your PATH:

- AWS CLI

- yq-go in your PATH

- openssl

### CloudFormation Template

- Sync the CloudFormation templates to a Public S3 bucket to be used by CloudFormation nested stack deployment:

> There are two valid flags to reference CloudFormation templates: --template-body or --template-url (only S3 URL is allowed)

```sh
BUCKET_NAME="installer-upi-templates"
TEMPLATE_BASE_URL="https://${BUCKET_NAME}.s3.amazonaws.com"

aws s3api create-bucket --bucket $BUCKET_NAME --region us-east-1
aws s3api put-public-access-block \
    --bucket ${BUCKET_NAME} \
    --public-access-block-configuration \
    BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
aws s3api put-bucket-policy \
    --bucket ${BUCKET_NAME} \
    --policy "{\"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Effect\": \"Allow\",
      \"Principal\": \"*\",
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${BUCKET_NAME}/*\"
    }
  ]
}"

function update_templates() {
  local base_path="${1:-labs/ocp-install-iac/aws-cloudformation-templates}"
  for TEMPLATE in ${TEMPLATES[*]}; do
      
      if [[ ! -f "$base_path/$TEMPLATE" ]]; then
        echo "Template ${TEMPLATE} not found in ${base_path}"
        continue
      fi
      aws s3 cp $base_path/$TEMPLATE s3://$BUCKET_NAME/${TEMPLATE}
  done
}
```

## Create VPC

TODO

- Extract and merge the subnet IDs:

```sh
export VPC_ID=vpc-0e64d023ca085182f
mapfile -t SUBNETS < <(aws ec2 describe-subnets --filters Name=vpc-id,Values=${VPC_ID} --query "Subnets[?AssignIpv6AddressOnCreation==\`false\`].SubnetId" --output text | tr '[:space:]' '\n')
```

## Create install-config.yaml

TODO for private with subnets

> https://docs.openshift.com/container-platform/4.14/installing/installing_aws/installing-aws-private.html#installation-aws-config-yaml_installing-aws-private

- Create install-config.yaml:

```sh
export PULL_SECRET_FILE=/path/to/pull-secret
export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
export BASE_DOMAIN=devcluster.openshift.com
export INSTALL_DIR="${HOME}/openshift-labs/${CLUSTER_NAME}"
mkdir $INSTALL_DIR

cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: Internal
baseDomain: ${BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
networking:
  machineNetwork:
  - cidr: ${CLUSTER_VPC_CIDR}
platform:
  aws:
    region: ${AWS_REGION}
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)

pullSecret: '$(cat ${PULL_SECRET_FILE} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
```

## Create Proxy

### Prerequisites

- switch to directory labs/ocp-install-iac

- sync the cloudformation templates to the bucket

```sh
export TEMPLATES=()
TEMPLATES+=("00_iam_role.yaml")
TEMPLATES+=("01_vpc_99_security_group.yaml")
TEMPLATES+=("04_ec2_instance.yaml")
update_templates
```

- export variables used in the deployment

```sh
export WORKDIR=./labs/ocp-install-iac
export CFN_TEMPLATE_PATH=${WORKDIR}/aws-cloudformation-templates
export CFN_STACK_PATH=file://${CFN_TEMPLATE_PATH}
```

### Prepare the Proxy configuration

- run the script:

```sh
function generate_proxy_ignition() {
  envsubst < ${WORKDIR}/proxy-template/proxy.ign.template > ${INSTALL_DIR}/proxy.ign
  test -f ${INSTALL_DIR}/proxy.ign || echo "Failed to create ${INSTALL_DIR}/proxy.ign"
  echo "${INSTALL_DIR}/proxy.ign"
}

EXPIRATION_DATE=$(date -d '4 hours' --iso=minutes --utc)
TAGS="Key=expirationDate,Value=${EXPIRATION_DATE}"

CONFIG="${INSTALL_DIR}/install-config.yaml"

#export  PROXY_IMAGE=registry.ci.openshift.org/origin/4.5:egress-http-proxy
export PROXY_IMAGE=quay.io/mrbraga/squid:6.6

export PROXY_NAME="proxy-$(yq-go r "${CONFIG}" 'metadata.name')"
export REGION="$(yq-go r "${CONFIG}" 'platform.aws.region')"
echo Using region: ${REGION}
test -n "${REGION}"

curl -L -o /tmp/fcos-stable.json https://builds.coreos.fedoraproject.org/streams/stable.json
export AMI_ID=$(jq -r .architectures.x86_64.images.aws.regions[\"${REGION}\"].image < /tmp/fcos-stable.json)
if [ -z "${AMI}" ]; then
  echo "Missing AMI in region: ${REGION}" 1>&2
  exit 1
fi
export RELEASE=$(jq -r .architectures.x86_64.images.aws.regions[\"${REGION}\"].release < /tmp/fcos-stable.json)
echo "Using FCOS ${RELEASE} AMI: ${AMI_ID}"

export ssh_pub_key=$(<"${HOME}/.ssh/id_rsa.pub")

# get the VPC ID from a subnet -> subnet.VpcId
#PROXY_SUBNET_ID="$(yq-go r "${CONFIG}" 'platform.aws.subnets[0]')"
PROXY_SUBNET_ID=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=${VPC_ID} --query "Subnets[?AssignIpv6AddressOnCreation==\`true\`].SubnetId" --output text | tr '[:space:]' '\n' | tail -n1)
echo "Using aws_subnet: ${PROXY_SUBNET_ID}"

export PASSWORD="$(uuidgen | sha256sum | cut -b -32)"
export HTPASSWD_CONTENTS="${PROXY_NAME}:$(openssl passwd -apr1 ${PASSWORD})"
export HTPASSWD_CONTENTS="$(echo -e ${HTPASSWD_CONTENTS} | base64 -w0)"

# define squid config
export SQUID_CONFIG="$(base64 -w0 < ${WORKDIR}/proxy-template/squid.conf)"

# define squid.sh
export SQUID_SH="$(envsubst < ${WORKDIR}/proxy-template/squid.sh.template | base64 -w0)"

# define proxy.sh
export PROXY_SH="$(base64 -w0 < ${WORKDIR}/proxy-template/proxy.sh)"


# create ignition entries for certs and script to start squid and systemd unit entry
# create the proxy stack and then get its IP
export PROXY_URI="s3://${BUCKET_NAME}/proxy.ign"
export PROXY_URL="https://${BUCKET_NAME}.s3.amazonaws.com/proxy.ign"

cat <<EOF
PASSWORD=$PASSWORD
HTPASSWD_CONTENTS=$HTPASSWD_CONTENTS
SQUID_CONFIG=$SQUID_CONFIG
SQUID_SH=$SQUID_SH
PROXY_SH=$PROXY_SH
PROXY_URL=$PROXY_URL
PROXY_IMAGE=$PROXY_IMAGE
EOF

generate_proxy_ignition

aws s3 cp ${INSTALL_DIR}/proxy.ign $PROXY_URI

export USER_DATA=$(envsubst < labs/ocp-install-iac/proxy-template/userData.ign.template | base64 -w0)
```

### Provision the instance

Create the EC2 instance in the Public subnet with IPv6:

> TODO --tags

```sh
cat <<EOF
CFN_STACK_PATH=$CFN_STACK_PATH
VPC_ID=$VPC_ID
VPC_CIDR=$CLUSTER_VPC_CIDR
NAME_PREFIX=${RESOURCE_NAME_PREFIX}-proxy
AMI_ID=$AMI_ID
PROXY_SUBNET_ID=$PROXY_SUBNET_ID
USER_DATA=$USER_DATA
TEMPLATE_BASE_URL=$TEMPLATE_BASE_URL
EOF


export PROXY_STACK_NAME="ocp-proxy10"
aws cloudformation create-change-set \
--stack-name "${PROXY_STACK_NAME}" \
--change-set-name "${PROXY_STACK_NAME}" \
--change-set-type "CREATE" \
--template-body ${CFN_STACK_PATH}/stack_ocp_private_proxy.yaml \
--include-nested-stacks \
--capabilities CAPABILITY_IAM \
--tags $TAGS \
--parameters \
  ParameterKey=VpcId,ParameterValue=${VPC_ID} \
  ParameterKey=VpcCidr,ParameterValue=${CLUSTER_VPC_CIDR} \
  ParameterKey=NamePrefix,ParameterValue=${RESOURCE_NAME_PREFIX}-proxy \
  ParameterKey=AmiId,ParameterValue=${AMI_ID} \
  ParameterKey=SubnetId,ParameterValue=${PROXY_SUBNET_ID} \
  ParameterKey=UserData,ParameterValue=${USER_DATA} \
  ParameterKey=TemplatesBaseURL,ParameterValue="${TEMPLATE_BASE_URL}"

aws cloudformation describe-change-set \
--stack-name "${PROXY_STACK_NAME}" \
--change-set-name "${PROXY_STACK_NAME}"

aws cloudformation execute-change-set \
    --change-set-name "${PROXY_STACK_NAME}" \
    --stack-name "${PROXY_STACK_NAME}"

aws cloudformation wait stack-create-complete \
    --region ${AWS_REGION} \
    --stack-name "${PROXY_STACK_NAME}"
```

- Gather instance attributes
```sh
export INSTANCE_ID="$(aws cloudformation describe-stacks \
  --stack-name "${PROXY_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`ProxyInstanceId`].OutputValue' \
  --output text)"

export PRIVATE_PROXY_IP=$(aws cloudformation describe-stacks \
  --stack-name "${PROXY_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`ProxyPrivateIp`].OutputValue' \
  --output text)

# AWS does not return IPv6 address in resource AWS::EC2::Instance
# https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-instance.html#aws-resource-ec2-instance-return-values
export PUBLIC_PROXY_IP="$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[].Instances[].Ipv6Address" --output text)"

export PROXY_URL="http://${PROXY_NAME}:${PASSWORD}@${PRIVATE_PROXY_IP}:3128/"

echo "Instance ${INSTANCE_ID}"
echo "${PROXY_URL}"

cat >> "${CONFIG}" << EOF
proxy:
  httpsProxy: ${PROXY_URL}
  httpProxy: ${PROXY_URL}
EOF

echo "Instance ${INSTANCE_ID}"
```

### Destroy

```sh
aws cloudformation delete-stack --stack-name "$PROXY_STACK_NAME" &&

update_templates
```

## Costs

> TBD

## References

TBD