# Install an OCP cluster on AWS in private subnets with proxy using manual Authentication mode with STS

!!! warning "Experimental steps"
    The steps described on this page are experimental!

### Create install-config.yaml

- Create install-config.yaml

```sh
#export PULL_SECRET_FILE=/path/to/pull-secret
export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
export BASE_DOMAIN=devcluster.openshift.com
export CLUSTER_NAME="lab415v15"
export CLUSTER_VPC_CIDR="10.0.0.0/16"
export AWS_REGION=us-east-1
export INSTALL_DIR="${HOME}/openshift-labs/${CLUSTER_NAME}"
mkdir $INSTALL_DIR

# For ipv4
FILTER_PRIVATE_SUBNET_OPT=MapPublicIpOnLaunch
# For ipv6
#FILTER_PRIVATE_SUBNET_OPT=AssignIpv6AddressOnCreation

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

### Create tunnels with bastion host (optional)

Choose one:

- Using SSH tunneling to proxy node (when running in the same VPC, and proxy is reached publically):

```sh
ssh -L 127.0.0.1:2222:$BASTION_PRIVATE_IP:22 core@$PROXY_PUBLIC_IP
```

- Using SSM tunneling to bastion node (private subnet):

```sh
aws ssm start-session \
  --target ${BASTION_INSTANCE_ID} \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"portNumber\":[\"22\"],\"localPortNumber\":[\"2222\"],\"host\":[\"$BASTION_PRIVATE_IP\"]}"
```

### Create cluster using bastion host

- Sync config:
```sh
ssh $SSH_OPTS -p 2222 core@localhost "mkdir ~/${CLUSTER_NAME}"

scp $SSH_OPTS -P2222 ${INSTALL_DIR}/install-config.yaml core@localhost:~/${CLUSTER_NAME}/install-config.yaml

# NOTE: installer does not support EC2 Instance role to install a cluster (why if CCO must create credentials from credentialsrequests in install time?)
# TODO: copy static credentials or use manual+sts/manual to remote instance.
ssh $SSH_OPTS -p 2222 core@localhost "mkdir ~/.aws; cat <<EOF>~/.aws/credentials
[default]
aws_access_key_id=$(grep -A2 '\[default\]' ~/.aws/credentials |grep ^aws_access_key_id | awk -F'=' '{print$2}')
aws_secret_access_key=$(grep -A2 '\[default\]' ~/.aws/credentials |grep ^aws_secret_access_key | awk -F'=' '{print$2}')
#sts_regional_endpoints = regional
EOF"

# copy the pull-secret if you want to extract the installer binary from the bastion
scp -P 2222 ${PULL_SECRET_FILE} core@localhost:~/pull-secret.txt
```

- Choose one: Start the installation or extract the installer from the target version

  - Extract the installer binary from target version (from the bastion host)

```sh
# OCP_VERSION
RELEASE_IMAGE=$(${HOME}/openshift-install version \
    | awk '/release image/ {print $3}')
CCO_IMAGE=$(${HOME}/oc adm release info \
    --image-for='cloud-credential-operator' \
    ${RELEASE_IMAGE})

${HOME}/oc image extract ${CCO_IMAGE} \
    --file="/usr/bin/ccoctl" \
    -a ${HOME}/pull-secret.txt

${HOME}/oc adm release extract \
    --credentials-requests \
    --cloud=aws \
    --to=${PWD}/cco-credrequests \
    ${RELEASE_IMAGE}

${HOME}/ccoctl-patch aws create-all \
  --name=lab415v15v0 \
  --region=us-east-1 \
  --credentials-requests-dir=${PWD}/cco-credrequests \
  --output-dir=$PWD/cco-output \
  --create-private-s3-bucket

export INSTALL_DIR=$PWD
cp -rf $INSTALL_DIR/install-config.yaml $INSTALL_DIR/install-config.yaml-bkp
${HOME}/openshift-install create manifests --log-level=debug --dir $INSTALL_DIR

echo "> CCO - Copying manifests to Install directory"
cp -rvf $PWD/cco-output/manifests/* ${INSTALL_DIR}/manifests/
cp -rvf $PWD/cco-output/tls ${INSTALL_DIR}/

${HOME}/openshift-install create cluster --log-level=debug --dir $INSTALL_DIR
```
