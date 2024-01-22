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

- Private subnets single-stack IPv4 with black hole default route
- Public subnets with dual-stack
- IPv4 public IP assignment blocked in public subnets
- IPv6 IP assignment enabled by default in the public subnet

### Create VPC

```sh
cat <<EOF
RESOURCE_NAME_PREFIX=${RESOURCE_NAME_PREFIX}
TEMPLATE_BASE_URL=$TEMPLATE_BASE_URL
EOF

# Create a variant to prevent any 'cache' of the template in CloudFormation
PREFIX_VARIANT="${RESOURCE_NAME_PREFIX}-v6-03"
export VPC_STACK_NAME="${PREFIX_VARIANT}-vpc"
aws cloudformation create-change-set \
--stack-name "${VPC_STACK_NAME}" \
--change-set-name "${VPC_STACK_NAME}" \
--change-set-type "CREATE" \
--template-body ${CFN_STACK_PATH}/stack_ocp_private_vpc_ipv6_dualstack.yaml \
--include-nested-stacks \
--tags $TAGS \
--parameters \
  ParameterKey=VpcCidr,ParameterValue=${CLUSTER_VPC_CIDR} \
  ParameterKey=NamePrefix,ParameterValue=${PREFIX_VARIANT} \
  ParameterKey=TemplatesBaseURL,ParameterValue="${TEMPLATE_BASE_URL}"

aws cloudformation describe-change-set \
--stack-name "${VPC_STACK_NAME}" \
--change-set-name "${VPC_STACK_NAME}"

sleep 20
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