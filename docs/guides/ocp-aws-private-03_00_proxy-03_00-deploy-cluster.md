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
export PROXY_DNS_RECORD="lab-proxy.devcluster.openshift.com"
export PROXY_DNS_HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name $DNS_BASE_DOMAIN | jq -r ".HostedZones[] | select(.Name==\"$DNS_BASE_DOMAIN.\").Id" | awk -F'/' '{print$3}')

# TODO must use PROXY_LB_SUBNET_IDS when fix Cloudformation template
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

export PROXY_CLUSTER_STACK_NAME="${PREFIX_VARIANT}-proxy-cluster-54"
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
  ParameterKey=NamePrefix,ParameterValue=${PROXY_CLUSTER_STACK_NAME} \
  ParameterKey=AmiId,ParameterValue=${PROXY_CUSTOM_AMI_ID} \
  ParameterKey=SubnetId,ParameterValue="${PROXY_SUBNET_ID}" \
  ParameterKey=DnsHostedZoneId,ParameterValue="${PROXY_DNS_HOSTED_ZONE_ID}" \
  ParameterKey=DnsRecordName,ParameterValue="${PROXY_DNS_RECORD}" \
  ParameterKey=TemplatesBaseURL,ParameterValue="${TEMPLATE_BASE_URL}"

sleep 15
aws cloudformation execute-change-set \
    --change-set-name "${PROXY_CLUSTER_STACK_NAME}" \
    --stack-name "${PROXY_CLUSTER_STACK_NAME}"
```

- Export variables used in the deployment:

```sh
# Load Balancer Address
export PROXY_SERVICE_ENDPOINT="$(aws cloudformation describe-stacks \
  --stack-name "${PROXY_CLUSTER_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
  --output text)"

export PROXY_SERVICE_ENDPOINT="$PROXY_DNS_RECORD"

# Export Proxy Serivce URL to be set on install-config
export PROXY_SERVICE_URL="http://${PROXY_USER_NAME}:${PROXY_PASSWORD}@${PROXY_SERVICE_ENDPOINT}:3128"
export PROXY_SERVICE_URL_TLS="https://${PROXY_USER_NAME}:${PROXY_PASSWORD}@${PROXY_SERVICE_ENDPOINT}:3130"
export PROXY_SERVICE_NO_PROXY="169.254.169.254,.vpce.amazonaws.com"

cat <<EOF
PROXY_SERVICE_URL=$PROXY_SERVICE_URL
PROXY_SERVICE_URL_TLS=$PROXY_SERVICE_URL_TLS
PROXY_SERVICE_NO_PROXY=$PROXY_SERVICE_NO_PROXY
EOF
```

Test:

```sh
# Public IP for an instance in VPC. 
# NOTE if you choose one EC2 behind the LB, it seems the hairpin connection is a problem in AWS/NLB
PROXY_SSH_ADDR=54.88.93.79
PROXY_SSH_OPTS="$PROXY_SSH_OPTS -o StrictHostKeyChecking=no"
ssh $PROXY_SSH_OPTS core@"$PROXY_SSH_ADDR" "curl -s --proxy $PROXY_SERVICE_URL https://mtulio.dev/api/geo" | jq .

ssh $PROXY_SSH_OPTS core@"$PROXY_SSH_ADDR" "curl -s --proxy-cacert /etc/squid/ca-chain.pem --proxy $PROXY_SERVICE_URL_TLS https://mtulio.dev/api/geo" | jq .
```