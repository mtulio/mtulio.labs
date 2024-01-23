# OpenShift Private Hacking | one-time setup

Simple and quickly way to deploy OpenShift private/restricted mode on AWS.

## Prerequisites

- [Create deployment S3 Bucket and sync templates](./ocp-aws-private-01_00-pre.md)
- Build images
    - [Build proxy image (AMI)](./ocp-aws-private-01_01-build-image-squid-proxy.md)
    - [Build bastion host image (AMI)](./ocp-aws-private-01_01-build-image-ssm.md)
- [Create Proxy config and ignition file](./ocp-aws-private-03_00_proxy-01-config-TLS.md)
- [Create Bastion host config/ignition](./ocp-aws-private-03_bastion-01-config.md)

## One-time deployment

- Provision the resources (VPC, Proxy cluster and Bastion):

```sh
cat <<EOF
RESOURCE_NAME_PREFIX=${RESOURCE_NAME_PREFIX}
TEMPLATE_BASE_URL=$TEMPLATE_BASE_URL
EOF

# Create a variant to prevent any 'cache' of the template in CloudFormation
PREFIX_VARIANT="${RESOURCE_NAME_PREFIX}-55"
export VPC_STACK_NAME="${PREFIX_VARIANT}-vpc"
aws cloudformation create-change-set \
--stack-name "${VPC_STACK_NAME}" \
--change-set-name "${VPC_STACK_NAME}" \
--change-set-type "CREATE" \
--template-body ${CFN_STACK_PATH}/stack_ocp_cluster_private-proxy_bastion.yaml \
--include-nested-stacks \
--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
--tags $TAGS \
--parameters \
  ParameterKey=VpcCidr,ParameterValue=${CLUSTER_VPC_CIDR} \
  ParameterKey=NamePrefix,ParameterValue=${PREFIX_VARIANT} \
  ParameterKey=TemplatesBaseURL,ParameterValue="${TEMPLATE_BASE_URL}" \
  ParameterKey=ProxyAmiId,ParameterValue="${PROXY_AMI_ID}" \
  ParameterKey=ProxyUserData,ParameterValue="${PROXY_USER_DATA}" \
  ParameterKey=ProxyDnsHostedZoneId,ParameterValue="${PROXY_DNS_HOSTED_ZONE_ID}" \
  ParameterKey=ProxyDnsRecordName,ParameterValue="${PROXY_DNS_RECORD}" \
  ParameterKey=BastionAmiId,ParameterValue="${BASTION_AMI_ID}" \
  ParameterKey=BastinoUserData,ParameterValue="${BASTION_USER_DATA}"


aws cloudformation describe-change-set \
--stack-name "${VPC_STACK_NAME}" \
--change-set-name "${VPC_STACK_NAME}"

sleep 40
aws cloudformation execute-change-set \
    --change-set-name "${VPC_STACK_NAME}" \
    --stack-name "${VPC_STACK_NAME}"

aws cloudformation wait stack-create-complete \
    --region ${AWS_REGION} \
    --stack-name "${VPC_STACK_NAME}"


update_templates
```

### Installer from bastin host


- From the client
```sh

```

- in the bastion, run the installer:

```sh
aws ssm get-parameter --name lab-ci-54-openshift-cluster-subnets --query "Parameter.Value" --output text


#export PULL_SECRET_FILE=/path/to/pull-secret
export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
export BASE_DOMAIN=devcluster.openshift.com
export CLUSTER_NAME="lab415v22"
export CLUSTER_VPC_CIDR="10.0.0.0/16"
export AWS_REGION=us-east-1
export INSTALL_DIR="${HOME}/openshift-labs/${CLUSTER_NAME}"
mkdir $INSTALL_DIR

# For ipv4
FILTER_PRIVATE_SUBNET_OPT=MapPublicIpOnLaunch
# For ipv6
#FILTER_PRIVATE_SUBNET_OPT=AssignIpv6AddressOnCreation

VPC_ID=vpc-075db0fdc1118bc03
mapfile -t SUBNETS < <(aws ec2 describe-subnets --filters Name=vpc-id,Values=${VPC_ID} --query "Subnets[?$FILTER_PRIVATE_SUBNET_OPT==\`false\`].SubnetId" --output text | tr '[:space:]' '\n')

# exporting VPC endpoint DNS names and create the format to installer
aws ec2 describe-vpc-endpoints \
  --filters Name=vpc-id,Values=$VPC_ID \
  --query 'VpcEndpoints[].DnsEntries[0].DnsName' | jq -r .[] \
  > ${INSTALL_DIR}/tmp-aws-vpce-dns.txt

{
  echo "    serviceEndpoints:" > ${INSTALL_DIR}/config-vpce.txt
  echo -ne "169.254.169.254,$CLUSTER_VPC_CIDR" > ${INSTALL_DIR}/config-noproxy.txt
  while read line; do
  service_name=$(echo $line | awk -F'.' '{print$2}');
  service_url="https://$line";
  service_url_region="https://$service_name.$REGION.amazonaws.com";
  case $service_name in
  "ssm"|"ssmmessages"|"ec2messages"|"kms"|"sts") continue ;;
  esac
  echo -e "    - name: ${service_name}\n      url: ${service_url}" >> ${INSTALL_DIR}/config-vpce.txt
  echo -ne ",$line" >> ${INSTALL_DIR}/config-noproxy.txt
  done <${INSTALL_DIR}/tmp-aws-vpce-dns.txt
}

cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: Internal
credentialsMode: Manual
baseDomain: ${BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
networking:
  machineNetwork:
  - cidr: ${CLUSTER_VPC_CIDR}
platform:
  aws:
    region: ${AWS_REGION}
$(<${INSTALL_DIR}/config-vpce.txt)
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)

pullSecret: '$(cat ${PULL_SECRET_FILE} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(<${SSH_PUB_KEY_FILE})

proxy:
  httpsProxy: ${PROXY_SERVICE_URL_TLS}
  httpProxy: ${PROXY_SERVICE_URL}
  noProxy: $(<${INSTALL_DIR}/config-noproxy.txt)
additionalTrustBundle: |
$(cat ${INTERMEDIATE}/certs/ca-chain.cert.pem | awk '{print "  "$0}')
EOF

```

- Open tunnel
```sh
BASTION_PRIVATE_IP=10.0.0.230
PROXY_PUBLIC_IP=52.91.8.244
ssh -L 127.0.0.1:2225:$BASTION_PRIVATE_IP:22 core@$PROXY_PUBLIC_IP

```

Copy files

```sh
scp -P 2225 ${INSTALL_DIR}/install-config.yaml core@localhost:~/

# installer does not support installing from EC2 creds
ssh $SSH_OPTS -p 2225 core@localhost "mkdir ~/.aws; cat <<EOF>~/.aws/credentials
[default]
aws_access_key_id=$(grep -A2 '\[default\]' ~/.aws/credentials |grep ^aws_access_key_id | awk -F'=' '{print$2}')
aws_secret_access_key=$(grep -A2 '\[default\]' ~/.aws/credentials |grep ^aws_secret_access_key | awk -F'=' '{print$2}')
#sts_regional_endpoints = regional
EOF"

# copy user data
scp -P 2225 ${PULL_SECRET_FILE} core@localhost:~/.dockercfg

```


- In the bastion, extract the clients:

```sh
export $(cat /etc/proxy.env | xargs) || true
export $(cat /etc/installer.env | xargs) || true

# considering pull-secret.json in ~/.dockercfg
# Pull is created by userdata/ignition
PULL_SECRET=$HOME/.dockercfg
RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:4.15.0-rc.0-x86_64

function extract_clients() {
  RELEASE_CONAINER=$(podman create --name release $RELEASE_IMAGE)
  podman cp release:/release-manifests/image-references /tmp/release-references

  INSTALLER_IMAGE=$(jq -r '.spec.tags[] | select(.name=="installer").from.name' /tmp/release-references)
  OC_IMAGE=$( jq -r '.spec.tags[] | select(.name=="cli").from.name' /tmp/release-references)

  CONTAINER_INSTALLER=$(podman create --name installer --replace --authfile $PULL_SECRET $INSTALLER_IMAGE)
  CONTAINER_OC=$(podman create --name cli --replace --authfile $PULL_SECRET $OC_IMAGE)

  mkdir ~/bin
  podman cp installer:/usr/bin/openshift-install ~/bin/openshift-install
  podman cp cli:/usr/bin/oc ~/bin/oc

  podman rm installer cli release
}

function patch_private_subnets() {
  # Discovery private subnets from VPC
  # Update install-config
  mapfile -t SUBNETS < <(aws ec2 describe-subnets --filters Name=vpc-id,Values=${VPC_ID} --query "Subnets[?$FILTER_PRIVATE_SUBNET_OPT==\`false\`].SubnetId" --output text | tr '[:space:]' '\n')

  cat <<EOF > ~/install-config.proxy.patch.yaml
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)
EOF
}

function patch_vpce_interface() {
  # Discovery VPC interface ednpoints
  # Update install-config
  # exporting VPC endpoint DNS names and create the format to installer
  aws ec2 describe-vpc-endpoints \
    --filters Name=vpc-id,Values=$VPC_ID \
    --query 'VpcEndpoints[].DnsEntries[0].DnsName' | jq -r .[] \
    > ${INSTALL_DIR}/tmp-aws-vpce-dns.txt
  $(<${INSTALL_DIR}/config-vpce.txt)

  cat <<EOF > ~/install-config.proxy.patch.yaml
$(<${INSTALL_DIR}/config-vpce.txt)
EOF
}

function patch_pull_secret() {
  # Discovery VPC interface ednpoints
  # Update install-config

  cat <<EOF > ~/install-config.proxy.patch.yaml
additionalTrustBundle: |
$(cat ${INTERMEDIATE}/certs/ca-chain.cert.pem | awk '{print "  "$0}')
EOF

pullSecret: '$(cat ${PULL_SECRET_FILE} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(<${SSH_PUB_KEY_FILE})
}

function patch_proxy() {

  cat <<EOF > ~/install-config.proxy.patch.yaml
proxy:
  httpsProxy: ${PROXY_SERVICE_URL_TLS}
  httpProxy: ${PROXY_SERVICE_URL}
  noProxy: $(<${INSTALL_DIR}/config-noproxy.txt)
EOF
}

```

- Install the cluster

```sh
openshift-install create cluster --log-level=debug
```