# Install an OCP cluster on AWS in private subnets with proxy

!!! warning "Experimental steps"
    The steps described on this page are experimental!

!!! info "CloudFormation templates"
    The CloudFormation templates mentioned on this page are available in the path:
    [mtulio.labs/labs/labs/ocp-install-iac/aws-cloudformation-templates](https://github.com/mtulio/mtulio.labs/tree/master/labs/ocp-install-iac/aws-cloudformation-templates)


## Deploy VPC single stack IPv4 with blackhole private subnets

| Publish | Install type | 
| -- | -- |
| Internal | BYO VPC/Restricted/Proxy |

Items:

- Publish=Internal
- Public subnets with dual-stack
- Private subnets single-stack IPv4 with black hole default route
- IPv4 public IP assignment blocked in public subnets
- IPv6 IP assignment enabled by default in the public subnet

Results:

- ??

Steps:


### Create VPC

- Deploy VPC and Proxy node:

```sh
cat <<EOF
RESOURCE_NAME_PREFIX=${RESOURCE_NAME_PREFIX}
TEMPLATE_BASE_URL=$TEMPLATE_BASE_URL
EOF

# Create a variant to prevent any 'cache' of the template in CloudFormation
PREFIX_VARIANT="${RESOURCE_NAME_PREFIX}-22"
export VPC_STACK_NAME="${PREFIX_VARIANT}-vpc"
aws cloudformation create-change-set \
--stack-name "${VPC_STACK_NAME}" \
--change-set-name "${VPC_STACK_NAME}" \
--change-set-type "CREATE" \
--template-body ${CFN_STACK_PATH}/stack_ocp_private_vpc_ipv4_public_blackhole.yaml \
--include-nested-stacks \
--capabilities CAPABILITY_IAM \
--tags $TAGS \
--parameters \
  ParameterKey=VpcCidr,ParameterValue=${CLUSTER_VPC_CIDR} \
  ParameterKey=NamePrefix,ParameterValue=${PREFIX_VARIANT} \
  ParameterKey=TemplatesBaseURL,ParameterValue="${TEMPLATE_BASE_URL}"

aws cloudformation describe-change-set \
--stack-name "${VPC_STACK_NAME}" \
--change-set-name "${VPC_STACK_NAME}"

aws cloudformation execute-change-set \
    --change-set-name "${VPC_STACK_NAME}" \
    --stack-name "${VPC_STACK_NAME}"

aws cloudformation wait stack-create-complete \
    --region ${AWS_REGION} \
    --stack-name "${VPC_STACK_NAME}"
```

- Export variables used later:

```sh
export VPC_ID="$(aws cloudformation describe-stacks \
  --stack-name "${VPC_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`VpcId`].OutputValue' \
  --output text)"


```