## Deploy proxy server

!!! warning "Experimental steps"
    The steps described on this page are experimental!

!!! info "CloudFormation templates"
    The CloudFormation templates mentioned on this page are available in the path:
    [mtulio.labs/labs/labs/ocp-install-iac/aws-cloudformation-templates](https://github.com/mtulio/mtulio.labs/tree/master/labs/ocp-install-iac/aws-cloudformation-templates)


### Create Proxy node

- Export the proxy configuration according to the deployment:

```sh
PROXY_SUBNET_ID="$(aws cloudformation describe-stacks \
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
PROXY_AMI_ID=$PROXY_AMI_ID
PROXY_SUBNET_ID=$PROXY_SUBNET_ID
TEMPLATE_BASE_URL=$TEMPLATE_BASE_URL
EOF

export PROXY_STACK_NAME="${PREFIX_VARIANT}-proxy"
aws cloudformation create-change-set \
--stack-name "${PROXY_STACK_NAME}" \
--change-set-name "${PROXY_STACK_NAME}" \
--change-set-type "CREATE" \
--template-body ${CFN_STACK_PATH}/stack_ocp_private-node_proxy.yaml \
--include-nested-stacks \
--capabilities CAPABILITY_IAM \
--parameters \
  ParameterKey=VpcId,ParameterValue=${VPC_ID} \
  ParameterKey=VpcCidr,ParameterValue=${CLUSTER_VPC_CIDR} \
  ParameterKey=NamePrefix,ParameterValue=${PREFIX_VARIANT}-proxy \
  ParameterKey=AmiId,ParameterValue=${PROXY_AMI_ID} \
  ParameterKey=UserData,ParameterValue=${PROXY_USER_DATA} \
  ParameterKey=SubnetId,ParameterValue=${PROXY_SUBNET_ID} \
  ParameterKey=IsPublic,ParameterValue="True" \
  ParameterKey=TemplatesBaseURL,ParameterValue="${TEMPLATE_BASE_URL}"


aws cloudformation execute-change-set \
    --change-set-name "${PROXY_STACK_NAME}" \
    --stack-name "${PROXY_STACK_NAME}"
```

- Export variables used in the deployment:

```sh
PROXY_INSTANCE_ID="$(aws cloudformation describe-stacks \
  --stack-name "${PROXY_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`ProxyInstanceId`].OutputValue' \
  --output text)"

PROXY_PRIVATE_IP=$(aws ec2 describe-instances --instance-ids $PROXY_INSTANCE_ID --query 'Reservations[].Instances[].PrivateIpAddress' --output text)

# Export public IP (choose one)

## Export public IPv4 when using it
PROXY_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $PROXY_INSTANCE_ID \
  --query 'Reservations[].Instances[].PublicIpAddress' \
  --output text)
PROXY_SSH_ADDR="${PROXY_PUBLIC_IP}"
PROXY_SSH_OPTS="-4"

## Export public IPv6 when using it
PROXY_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $PROXY_INSTANCE_ID \
  --query 'Reservations[].Instances[].Ipv6Address' \
  --output text)
PROXY_SSH_ADDR="[${PROXY_PUBLIC_IP}]"
PROXY_SSH_OPTS="-6"

# Export Proxy Serivce URL to be set on install-config
export PROXY_SERVICE_URL="http://${PROXY_NAME}:${PASSWORD}@${PROXY_PRIVATE_IP}:3128"

export PROXY_SERVICE_NO_PROXY="*.vpce.amazonaws.com,127.0.0.1,169.254.169.254,localhost"

```

- Review the public IP address used by the proxy

```sh
# Test SSH and proxy access
ssh $PROXY_SSH_OPTS core@"$PROXY_SSH_ADDR" "curl -s --proxy $PROXY_SERVICE_URL https://mtulio.dev/api/geo" | jq .

cat <<EOF
PROXY_PUBLIC_IP=$PROXY_PUBLIC_IP
PROXY_PRIVATE_IP=$PROXY_PRIVATE_IP
PROXY_SERVICE_URL=$PROXY_SERVICE_URL
EOF
```

- Copy dependencies to jump host (proxy)

```sh
scp $PROXY_SSH_OPTS  $(which openshift-install) core@"$PROXY_SSH_ADDR:~/"
scp $PROXY_SSH_OPTS $(which oc) core@"$PROXY_SSH_ADDR:~/"
```