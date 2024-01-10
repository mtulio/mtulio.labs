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

## Option 2) VPC dual-stack with IPv6 as egress traffic

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

- Sync Templates:

```sh
export CLUSTER_VPC_CIDR=10.0.0.0/16
export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
export RESOURCE_NAME_PREFIX="lab-ci"
export AWS_REGION=us-east-1

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
TEMPLATES+=("00_iam_role.yaml")
TEMPLATES+=("01_vpc_99_security_group.yaml")
TEMPLATES+=("04_ec2_instance.yaml")
TEMPLATES+=("01_vpc_01_egress_internet_gateway.yaml")
update_templates
```

- Generate user data (ignitions) for proxy node server (squid):

```sh
curl -L -o /tmp/fcos.json https://builds.coreos.fedoraproject.org/streams/stable.json

export PROXY_IMAGE=quay.io/mrbraga/squid:6.6
export PROXY_NAME="${RESOURCE_NAME_PREFIX}-proxy"
export PROXY_AMI_ID=$(jq -r .architectures.x86_64.images.aws.regions[\"${AWS_REGION}\"].image < /tmp/fcos.json)

export SSH_PUB_KEY=$(<"${SSH_PUB_KEY_FILE}")
export PASSWORD="$(uuidgen | sha256sum | cut -b -32)"
export HTPASSWD_CONTENTS="${PROXY_NAME}:$(openssl passwd -apr1 ${PASSWORD})"
export HTPASSWD_CONTENTS="$(echo -e ${HTPASSWD_CONTENTS} | base64 -w0)"

# define squid config
export SQUID_CONFIG="$(base64 -w0 < ${WORKDIR}/proxy-template/squid.conf)"

# define squid.sh
export SQUID_SH="$(envsubst < ${WORKDIR}/proxy-template/squid.sh.template | base64 -w0)"

# define proxy.sh
export PROXY_SH="$(base64 -w0 < ${WORKDIR}/proxy-template/proxy.sh)"

# generate ignition file
envsubst < ${WORKDIR}/proxy-template/proxy.ign.template > /tmp/proxy.ign
test -f /tmp/proxy.ign || echo "Failed to create /tmp/proxy.ign"

# publish ignition to shared bucket
export PROXY_URI="s3://${BUCKET_NAME}/proxy.ign"
export PROXY_URL="https://${BUCKET_NAME}.s3.amazonaws.com/proxy.ign"

aws s3 cp /tmp/proxy.ign $PROXY_URI

# Generate Proxy Instance user data
export PROXY_USER_DATA=$(envsubst < ${WORKDIR}/proxy-template/userData.ign.template | base64 -w0)
```

- Deploy VPC and Proxy node:

```sh
cat <<EOF
NAME_PREFIX=${RESOURCE_NAME_PREFIX}-proxy
PROXY_AMI_ID=$PROXY_AMI_ID
PROXY_USER_DATA=$PROXY_USER_DATA
TEMPLATE_BASE_URL=$TEMPLATE_BASE_URL
EOF

export PROXY_STACK_NAME="${RESOURCE_NAME_PREFIX}-proxy-vpc8"
aws cloudformation create-change-set \
--stack-name "${PROXY_STACK_NAME}" \
--change-set-name "${PROXY_STACK_NAME}" \
--change-set-type "CREATE" \
--template-body ${CFN_STACK_PATH}/stack_ocp_private_vpc_ipv6_proxy.yaml \
--include-nested-stacks \
--capabilities CAPABILITY_IAM \
--tags $TAGS \
--parameters \
  ParameterKey=VpcCidr,ParameterValue=${CLUSTER_VPC_CIDR} \
  ParameterKey=NamePrefix,ParameterValue=${RESOURCE_NAME_PREFIX}-proxy \
  ParameterKey=ProxyAmiId,ParameterValue=${PROXY_AMI_ID} \
  ParameterKey=ProxyUserData,ParameterValue=${PROXY_USER_DATA} \
  ParameterKey=TemplatesBaseURL,ParameterValue="${TEMPLATE_BASE_URL}"


aws cloudformation describe-change-set \
--stack-name "${PROXY_STACK_NAME}" \
--change-set-name "${PROXY_STACK_NAME}"

sleep 30
aws cloudformation execute-change-set \
    --change-set-name "${PROXY_STACK_NAME}" \
    --stack-name "${PROXY_STACK_NAME}"

aws cloudformation wait stack-create-complete \
    --region ${AWS_REGION} \
    --stack-name "${PROXY_STACK_NAME}"
```

- Create install-config.yaml

```sh

```


- Discover the IP address of jump host

```sh
VPC_ID="$(aws cloudformation describe-stacks \
  --stack-name "${PROXY_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`VpcId`].OutputValue' \
  --output text)"
PROXY_INSTANCE_ID="$(aws cloudformation describe-stacks \
  --stack-name "${PROXY_STACK_NAME}" \
  --query 'Stacks[].Outputs[?OutputKey==`ProxyInstanceId`].OutputValue' \
  --output text)"
PROXY_INSTANCE_ID="i-0d3a2138e7f9395e8"

PROXY_IP6=$(aws ec2 describe-instances --instance-ids $PROXY_INSTANCE_ID --query 'Reservations[].Instances[].Ipv6Address' --output text)

PROXY_IP4=$(aws ec2 describe-instances --instance-ids $PROXY_INSTANCE_ID --query 'Reservations[].Instances[].PrivateIpAddress' --output text)

export PROXY_SERVICE_URL="http://${PROXY_NAME}:${PASSWORD}@${PROXY_IP4}:3128"

ssh -6 core@"[$PROXY_IP]" "pwd"
```

- Copy dependencies to jump host (proxy)

```sh
scp -6 $(which openshift-install) core@"[$PROXY_IP]:~/"
scp -6 $(which oc) core@"[$PROXY_IP]:~/"
```


- Install the cluster

```sh
export PULL_SECRET_FILE=/path/to/pull-secret
export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
export BASE_DOMAIN=devcluster.openshift.com
export CLUSTER_NAME="lab415"
export CLUSTER_VPC_CIDR="10.0.0.0/16"
export AWS_REGION=us-east-1
export INSTALL_DIR="${HOME}/openshift-labs/${CLUSTER_NAME}"
mkdir $INSTALL_DIR

mapfile -t SUBNETS < <(aws ec2 describe-subnets --filters Name=vpc-id,Values=${VPC_ID} --query "Subnets[?AssignIpv6AddressOnCreation==\`false\`].SubnetId" --output text | tr '[:space:]' '\n')

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
    serviceEndpoints: 
      - name: ec2
        url: https://ec2.${AWS_REGION}.amazonaws.com
      - name: elasticloadbalancing
        url: https://elasticloadbalancing.${AWS_REGION}.amazonaws.com
      - name: s3
        url: https://s3.${AWS_REGION}.amazonaws.com
      - name: iam
        url: https://iam.${AWS_REGION}.amazonaws.com
      - name: sts
        url: https://sts.${AWS_REGION}.amazonaws.com
      - name: kms
        url: https://kms.${AWS_REGION}.amazonaws.com
        
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)

pullSecret: '$(cat ${PULL_SECRET_FILE} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})

proxy:
  httpsProxy: ${PROXY_SERVICE_URL}
  httpProxy: ${PROXY_SERVICE_URL}
  noProxy: ec2.${AWS_REGION}.amazonaws.com,elasticloadbalancing.${AWS_REGION}.amazonaws.com,s3.${AWS_REGION}.amazonaws.com,sts.${AWS_REGION}.amazonaws.com,route53.${AWS_REGION}.amazonaws.com,iam.${AWS_REGION}.amazonaws.com
EOF

scp -6 ${INSTALL_DIR}/install-config.yaml core@"[$PROXY_IP]:~/install-config.yaml"

ssh -6 core@$PROXY_IP "nohup ./openshift-install create cluster >> install.out 2>>&1 &"
```

<!-- 
    serviceEndpoints: 
      - name: ec2
        url: https://ec2.${REGION}.amazonaws.com
      - name: elasticloadbalancing
        url: https://elasticloadbalancing.${REGION}.amazonaws.com
      - name: s3
        url: https://s3.${REGION}.amazonaws.com
      - name: iam
        url: https://iam.${REGION}.amazonaws.com
      - name: tagging
        url: https://tagging.${REGION}.amazonaws.com
      - name: route53
        url: https://route53.${REGION}.amazonaws.com
      - name: sts
        url: https://sts.${REGION}.amazonaws.com
      - name: autoscaling
        url: https://autoscaling.${REGION}.amazonaws.com
      - name: servicequotas
        url: https://servicequotas.${REGION}.amazonaws.com
      - name: kms
        url: https://kms.${REGION}.amazonaws.com -->