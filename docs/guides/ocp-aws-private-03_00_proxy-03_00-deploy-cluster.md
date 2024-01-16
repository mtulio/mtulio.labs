## Deploy proxy cluster

!!! warning "Experimental steps"
    The steps described on this page are experimental!

!!! info "CloudFormation templates"
    The CloudFormation templates mentioned on this page are available in the path:
    [mtulio.labs/labs/labs/ocp-install-iac/aws-cloudformation-templates](https://github.com/mtulio/mtulio.labs/tree/master/labs/ocp-install-iac/aws-cloudformation-templates)


This section describe the steps to create a cluster of Proxy to serve
highly available and scale service, optionally exposing it as AWS PrivateLink service.



### Create a cluster for Proxy

- Export the proxy configuration according to the deployment:

```sh
PROXY_SUBNET_ID="$(aws cloudformation describe-stacks \
  --stack-name "${VPC_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
  --output text | tr ',' '\n' | tail -n1)"

# TODO fix the CloudFormation is not allowing comma-sepparated strings, not List of strings as parameter.
PROXY_LB_SUBNET_IDS="$(aws cloudformation describe-stacks \
  --stack-name "${VPC_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
  --output text)"
```

- Create EC2

```sh
cat <<EOF
PREFIX_VARIANT=$PREFIX_VARIANT
CFN_STACK_PATH=$CFN_STACK_PATH
CLUSTER_VPC_CIDR=$CLUSTER_VPC_CIDR
TAGS=$TAGS
CLUSTER_VPC_CIDR=$CLUSTER_VPC_CIDR
PROXY_AMI_ID=$PROXY_AMI_ID
PROXY_SUBNET_ID=$PROXY_SUBNET_ID
TEMPLATE_BASE_URL=$TEMPLATE_BASE_URL
EOF

export PROXY_CLUSTER_STACK_NAME="${PREFIX_VARIANT}-proxy-cluster-44"
aws cloudformation create-change-set \
--stack-name "${PROXY_CLUSTER_STACK_NAME}" \
--change-set-name "${PROXY_CLUSTER_STACK_NAME}" \
--change-set-type "CREATE" \
--template-body ${CFN_STACK_PATH}/stack_ocp_private-cluster_proxy.yaml \
--include-nested-stacks \
--capabilities CAPABILITY_IAM \
--parameters \
  ParameterKey=VpcId,ParameterValue=${VPC_ID} \
  ParameterKey=VpcCidr,ParameterValue=${CLUSTER_VPC_CIDR} \
  ParameterKey=NamePrefix,ParameterValue=${PREFIX_VARIANT}-proxy \
  ParameterKey=AmiId,ParameterValue=${PROXY_CUSTOM_AMI_ID} \
  ParameterKey=UserData,ParameterValue="" \
  ParameterKey=SubnetId,ParameterValue="${PROXY_SUBNET_ID}" \
  ParameterKey=TemplatesBaseURL,ParameterValue="${TEMPLATE_BASE_URL}"

sleep 30
aws cloudformation execute-change-set \
    --change-set-name "${PROXY_CLUSTER_STACK_NAME}" \
    --stack-name "${PROXY_CLUSTER_STACK_NAME}"
```

- Export variables used in the deployment:

```sh
export PROXY_SERVICE_ENDPOINT="$(aws cloudformation describe-stacks \
  --stack-name "${PROXY_CLUSTER_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
  --output text)"

# Export Proxy Serivce URL to be set on install-config
export PROXY_SERVICE_URL="http://${PROXY_NAME}:${PASSWORD}@${PROXY_SERVICE_ENDPOINT}:3128"

export PROXY_SERVICE_NO_PROXY=".vpce.amazonaws.com,127.0.0.1,169.254.169.254,localhost"

cat <<EOF
PROXY_SERVICE_URL=$PROXY_SERVICE_URL
PROXY_SERVICE_NO_PROXY=$PROXY_SERVICE_NO_PROXY
EOF
```