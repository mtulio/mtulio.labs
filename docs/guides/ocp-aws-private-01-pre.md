# Install an OCP cluster on AWS in private subnets with proxy

!!! warning "Experimental steps"
    The steps described on this page are experimental!

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

Export the environment variables:

```sh
#
# Global env vars
#
export RESOURCE_NAME_PREFIX="lab-ci"
export WORKDIR="$HOME/openshift-labs/${RESOURCE_NAME_PREFIX}"
mkdir -p ${WORKDIR}

export CLUSTER_VPC_CIDR=10.0.0.0/16
export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
export AWS_REGION=us-east-1

export DNS_BASE_DOMAIN="devcluster.openshift.com"
```

### Tools

The tools/binaries must be installed in your PATH:

- AWS CLI

- yq-go in your PATH

- openssl

### CloudFormation Template

- Sync the CloudFormation templates to a Public S3 bucket to be used by CloudFormation nested stack deployment:

> There are two valid flags to reference CloudFormation templates: --template-body or --template-url (only S3 URL is allowed)

!!! warning "Restricted S3 Bucket"
    Nested AWS CloudFormation templates can be stored in external HTTP URL using only S3 address, however AWS does not publically share the policy `"10.0.0.0/8` is enough to allow access from internal services, but in internal tests it works as
    expected.


```sh
# from @mtulio/mtulio.labs project
export SOURCE_DIR=./labs/ocp-install-iac
export CFN_TEMPLATE_PATH=${SOURCE_DIR}/aws-cloudformation-templates
export CFN_STACK_PATH=file://${CFN_TEMPLATE_PATH}

export BUCKET_NAME="installer-upi-templates"
export TEMPLATE_BASE_URL="https://${BUCKET_NAME}.s3.amazonaws.com"

#
# UPI Bucket
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
  for TEMPLATE in ${TEMPLATES[*]}; do
      
      if [[ ! -f "$base_path/$TEMPLATE" ]]; then
        echo "Template ${TEMPLATE} not found in ${base_path}"
        continue
      fi
      aws s3 cp $base_path/$TEMPLATE s3://$BUCKET_NAME/${TEMPLATE}
  done
}

# Upload templates to bucket
export TEMPLATES=()
TEMPLATES+=("01_vpc_00_standalone.yaml")
TEMPLATES+=("01_vpc_01_route_table.yaml")
TEMPLATES+=("01_vpc_01_cidr_block_ipv6.yaml")
TEMPLATES+=("01_vpc_99_subnet.yaml")
TEMPLATES+=("01_vpc_03_route_entry.yaml")
TEMPLATES+=("01_vpc_01_route_table.yaml")
TEMPLATES+=("01_vpc_01_internet_gateway.yaml")
TEMPLATES+=("00_iam_role.yaml")
TEMPLATES+=("01_vpc_99_security_group.yaml")
TEMPLATES+=("04_ec2_instance.yaml")
TEMPLATES+=("01_vpc_01_egress_internet_gateway.yaml")
TEMPLATES+=("01_vpc_99_endpoints.yaml")
update_templates
```