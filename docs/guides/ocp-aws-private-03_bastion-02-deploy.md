## Deploy bastion host

!!! warning "Experimental steps"
    The steps described on this page are experimental!

!!! info "CloudFormation templates"
    The CloudFormation templates mentioned on this page are available in the path:
    [mtulio.labs/labs/labs/ocp-install-iac/aws-cloudformation-templates](https://github.com/mtulio/mtulio.labs/tree/master/labs/ocp-install-iac/aws-cloudformation-templates)


### Create Proxy node

- Export the proxy configuration according to the deployment:

```sh
BASTION_SUBNET_ID="$(aws cloudformation describe-stacks \
  --stack-name "${VPC_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`PrivateSubnetIds`].OutputValue' \
  --output text | tr ',' '\n' | head -n1)"

# Temp/must be private
BASTION_SUBNET_ID="$(aws cloudformation describe-stacks \
  --stack-name "${VPC_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
  --output text | tr ',' '\n' | head -n1)"
```

- Create EC2

```sh
cat <<EOF
PREFIX_VARIANT=$PREFIX_VARIANT
CFN_STACK_PATH=$CFN_STACK_PATH
CLUSTER_VPC_CIDR=$CLUSTER_VPC_CIDR
TAGS=$TAGS
CLUSTER_VPC_CIDR=$CLUSTER_VPC_CIDR
BASTION_AMI_ID=$PROXY_AMI_ID
BASTION_SUBNET_ID=$PROXY_SUBNET_ID
BASTION_USER_DATA=$BASTION_USER_DATA
TEMPLATE_BASE_URL=$TEMPLATE_BASE_URL
EOF

export BASTION_STACK_NAME="${PREFIX_VARIANT}-bastion-09"
aws cloudformation create-change-set \
--stack-name "${BASTION_STACK_NAME}" \
--change-set-name "${BASTION_STACK_NAME}" \
--change-set-type "CREATE" \
--template-body ${CFN_STACK_PATH}/stack_ocp_private-node_bastion.yaml \
--include-nested-stacks \
--capabilities CAPABILITY_NAMED_IAM \
--parameters \
  ParameterKey=VpcId,ParameterValue=${VPC_ID} \
  ParameterKey=VpcCidr,ParameterValue=${CLUSTER_VPC_CIDR} \
  ParameterKey=NamePrefix,ParameterValue=${PREFIX_VARIANT}05 \
  ParameterKey=AmiId,ParameterValue=${BASTION_AMI_ID} \
  ParameterKey=UserData,ParameterValue=${BASTION_USER_DATA} \
  ParameterKey=SubnetId,ParameterValue=${BASTION_SUBNET_ID} \
  ParameterKey=TemplatesBaseURL,ParameterValue="${TEMPLATE_BASE_URL}"

sleep 20
aws cloudformation execute-change-set \
    --change-set-name "${BASTION_STACK_NAME}" \
    --stack-name "${BASTION_STACK_NAME}"
```

- Export variables used in the deployment:

```sh
BASTION_INSTANCE_ID="$(aws cloudformation describe-stacks \
  --stack-name "${BASTION_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`InstanceId`].OutputValue' \
  --output text)"

BASTION_PRIVATE_IP="$(aws cloudformation describe-stacks \
  --stack-name "${BASTION_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`PrivateIp`].OutputValue' \
  --output text)"
```

## Tests

- Test the SSM session to the instance:

```sh
aws ssm start-session --target ${BASTION_INSTANCE_ID} 
```

- Test opening a tunnel to the internal API load balancer:

```sh
aws ssm start-session \
--target ${BASTION_INSTANCE_ID} \
--document-name AWS-StartPortForwardingSessionToRemoteHost \
--parameters "{\"portNumber\":[\"22\"],\"localPortNumber\":[\"2222\"],\"host\":[\"$BASTION_PRIVATE_IP\"]}"
```

- Check the public IP usde by the bastion node to access the internet

```sh
# Test SSH and proxy access
ssh -p 2225 core@localhost "curl -s --proxy $PROXY_SERVICE_URL https://mtulio.dev/api/geo" | jq .
```
