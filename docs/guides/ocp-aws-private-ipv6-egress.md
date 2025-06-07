# Install an OCP cluster on AWS in private subnets with proxy

!!! warning "Experimental steps"
    The steps described on this page are experimental, as usual on my lab's website! =]

!!! info "CloudFormation templates"
    The CloudFormation templates mentioned on this page are available in the path:
    [mtulio.labs/labs/labs/ocp-install-iac/aws-cloudformation-templates](https://github.com/mtulio/mtulio.labs/tree/master/labs/ocp-install-iac/aws-cloudformation-templates)

Exercising OpenShift on private networks to mitigate public IPv4 utilization.

Options:
0) Dualstack VPC with egress using IPv6
1) Private/Proxy VPC with proxy running in the VPC in IPv6 subnets
2) Private/Proxy disconnected VPC with proxy running outside VPC (custom PrivateLink service)
3) Private/Disconnected VPC with mirrored images with registry running in the VPC with IPv6 subnets
4) Private/Disconnected VPC with mirrored images with registry running outside the VPC with IPv6 subnets

> NOTE: To access the cluster it is required a jump host. The jump host can: A) hosted in the public IPv6 subnet with SSH port forwarding; B) hosted in private subnet with SSM port forwarding

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

- TMP? Extract and merge the subnet IDs:

```sh
export VPC_ID=vpc-0e64d023ca085182f
mapfile -t SUBNETS < <(aws ec2 describe-subnets --filters Name=vpc-id,Values=${VPC_ID} --query "Subnets[?AssignIpv6AddressOnCreation==\`false\`].SubnetId" --output text | tr '[:space:]' '\n')
```

- Create the private VPC:

```sh
export WORKDIR=./labs/ocp-install-iac
export CFN_TEMPLATE_PATH=${WORKDIR}/aws-cloudformation-templates
export CFN_STACK_PATH=file://${CFN_TEMPLATE_PATH}


export TEMPLATES=()
TEMPLATES+=("01_vpc_00_standalone.yaml")
TEMPLATES+=("01_vpc_01_route_table.yaml")
TEMPLATES+=("01_vpc_01_cidr_block_ipv6.yaml")
TEMPLATES+=("01_vpc_99_subnet.yaml")
TEMPLATES+=("01_vpc_03_route_entry.yaml")
TEMPLATES+=("01_vpc_01_route_table.yaml")
TEMPLATES+=("01_vpc_01_internet_gateway.yaml")
TEMPLATES+=("01_vpc_01_egress_internet_gateway.yaml")
update_templates


export VPC_STACK_NAME="${RESOURCE_NAME_PREFIX}-vpc6"
aws cloudformation create-change-set \
--stack-name "${VPC_STACK_NAME}" \
--change-set-name "${VPC_STACK_NAME}" \
--change-set-type "CREATE" \
--template-body ${CFN_STACK_PATH}/stack_ocp_private_vpc_proxy_ipv6.yaml \
--include-nested-stacks \
--capabilities CAPABILITY_IAM \
--tags $TAGS \
--parameters \
  ParameterKey=VpcCidr,ParameterValue=${CLUSTER_VPC_CIDR} \
  ParameterKey=NamePrefix,ParameterValue=${RESOURCE_NAME_PREFIX}-proxy \
  ParameterKey=TemplatesBaseURL,ParameterValue="${TEMPLATE_BASE_URL}"

aws cloudformation describe-change-set \
--stack-name "${VPC_STACK_NAME}" \
--change-set-name "${VPC_STACK_NAME}"

sleep 30
aws cloudformation execute-change-set \
    --change-set-name "${VPC_STACK_NAME}" \
    --stack-name "${VPC_STACK_NAME}"

aws cloudformation wait stack-create-complete \
    --region ${AWS_REGION} \
    --stack-name "${VPC_STACK_NAME}"

# lab:
aws cloudformation delete-stack --stack-name "$VPC_STACK_NAME"
```

## Option 1) VPC dual-stack with IPv6 as egress traffic

Items:

- Publish=External
- Public and Private subnets dual-stack
- IPv4 public IP assignment blocked in public subnets
- Private subnets uses Egress-only gateway (IPv6)

Results:
- Fail, bootstrap didn't completed.

### Create install-config

- Get the subnet Ids

```sh
export VPC_ID=$(aws cloudformation describe-stacks \
  --region ${AWS_REGION} \
  --stack-name "${VPC_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`VpcId`].OutputValue' --output text)

# Private subnets
mapfile -t SUBNETS < <(aws cloudformation describe-stacks \
  --region ${AWS_REGION} \
  --stack-name "${VPC_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`PrivateSubnetIds`].OutputValue' \
  --output text | tr ',' '\n')

# Public subnets
mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks \
  --region ${AWS_REGION} \
  --stack-name "${VPC_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
  --output text | tr ',' '\n')

```

- Create install-config.yaml:

```sh
export PULL_SECRET_FILE=/path/to/pull-secret
export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
export BASE_DOMAIN=devcluster.openshift.com
export INSTALL_DIR="${HOME}/openshift-labs/${CLUSTER_NAME}"
mkdir $INSTALL_DIR

cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: External
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

- Render the manifests (make sure the metadata can be discovered)

```sh
openshift-install create manifests --dir ${INSTALL_DIR}
```

- Create cluster

```sh
openshift-install create cluster --dir ${INSTALL_DIR}
```

Fail, bootstrap didn't progress.
