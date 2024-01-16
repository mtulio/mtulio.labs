# Install an OCP cluster on AWS in private subnets with proxy

!!! warning "Experimental steps"
    The steps described on this page are experimental!

### Create install-config.yaml

- Create install-config.yaml

```sh
#export PULL_SECRET_FILE=/path/to/pull-secret
export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
export BASE_DOMAIN=devcluster.openshift.com
export CLUSTER_NAME="lab415v6"
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
  #echo -e "    - name: ${service_name}\n      url: ${service_url}" >> ${INSTALL_DIR}/config-vpce.txt
  echo -e "    - name: ${service_name}\n      url: ${service_url_region}" >> ${INSTALL_DIR}/config-vpce.txt
  #echo -ne ",$line" >> ${INSTALL_DIR}/config-noproxy.txt
  #echo -ne ",$service_name.${AWS_REGION}.amazonaws.com" >> ${INSTALL_DIR}/config-noproxy.txt
  done <${INSTALL_DIR}/tmp-aws-vpce-dns.txt
}

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
$(<${INSTALL_DIR}/config-vpce.txt)
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)

pullSecret: '$(cat ${PULL_SECRET_FILE} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(<${SSH_PUB_KEY_FILE})

proxy:
  httpsProxy: ${PROXY_SERVICE_URL}
  httpProxy: ${PROXY_SERVICE_URL}
  noProxy: $(<${INSTALL_DIR}/config-noproxy.txt)
EOF
```

### Create cluster using bastion host

- Sync utilitiesto bastion node:
```sh
SSH_OPTS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
scp $SSH_OPTS -P2222  $(which openshift-install) core@localhost:~/
scp $SSH_OPTS -P2222 $(which oc) core@localhost:~/
```

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
EOF"

# copy the pull-secret if you want to extract the installer binary from the bastion
scp -P 2222 ${PULL_SECRET_FILE} core@localhost:~/pull-secret.txt
```

- Choose one: Start the installation or extract the installer from the target version

  - Extract the installer binary from target version (from the bastion host)

```sh
# OCP_VERSION
VERSION=4.15.0-rc.2
RELEASE=quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64
oc adm release extract --tools quay.io/openshift-release-dev/ocp-release:4.15.0-rc.2-x86_64

./oc adm release extract -a ./pull-secret.txt --tools $RELEASE

```

  - Start the installation remotely (from the client)

```sh
# Run create cluster
ssh -p 2222 core@localhost "nohup ./openshift-install create cluster --log-level=debug >>./install.out 2>&1 &"
```

Follow the installer logs waiting for complete.

## Running installer on client proxied to bastion host (LIMITED WORKING)

> NOTE: those steps works only to port forward API port, not to install a cluster.

- Extract kubeconfig

```sh
scp $PROXY_SSH_OPTS core@$PROXY_SSH_ADDR:~/auth/kubeconfig ~/tmp/kubeconfig

cat <<EOF |yq3 merge - ~/tmp/kubeconfig > ~/tmp/kubeconfig-tunnel
clusters:
- cluster:
    server: https://localhost:6443
EOF
```

- Check the KUBE API connectivity

```sh
oc --kubeconfig ~/tmp/kubeconfig-tunnel get nodes
```

## Conclusion

Using [regional endpoints][regional-e], you have the benefit of using the
endpoint from the region but not privately, you must have access thru the
internet. So the config will end up something like this:

```sh
$ cat ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: Internal
baseDomain: devcluster.openshift.com
metadata:
  name: "lab415v6"
networking:
  machineNetwork:
  - cidr: 10.0.0.0/16
platform:
  aws:
    region: us-east-1
    serviceEndpoints:
    - name: ec2
      url: https://ec2.us-east-1.amazonaws.com
    - name: elasticloadbalancing
      url: https://elasticloadbalancing.us-east-1.amazonaws.com
    subnets:
    - subnet-029068ff5c67a8737
    - subnet-0d45a386afab45917

pullSecret: '...
sshKey: |
  ....

proxy:
  httpsProxy: http://lab-ci-27-proxy:x@lab-ci-28-proxy-nlb-proxy-.....elb.us-east-1.amazonaws.com:3128
  httpProxy: http://lab-ci-27-proxy:x@lab-ci-28-proxy-nlb-proxy-....elb.us-east-1.amazonaws.com:3128
  noProxy: 169.254.169.254,10.0.0.0/16

$ ./oc  --kubeconfig auth/kubeconfig  get proxy -o yaml
apiVersion: v1
items:
- apiVersion: config.openshift.io/v1
  kind: Proxy
  metadata:
    creationTimestamp: "2024-01-16T00:15:54Z"
    generation: 1
    name: cluster
    resourceVersion: "533"
    uid: 202fc628-8b72-4a73-9578-99724b492fb5
  spec:
    httpProxy: http://lab-ci-27-proxy:x@lab-ci-28-proxy-nlb-proxy-....elb.us-east-1.amazonaws.com:3128
    httpsProxy: http://lab-ci-27-proxy:x@lab-ci-28-proxy-nlb-proxy-.....elb.us-east-1.amazonaws.com:3128
    noProxy: 169.254.169.254,10.0.0.0/16
    trustedCA:
      name: ""
  status:
    httpProxy: http://lab-ci-27-proxy:x@lab-ci-28-proxy-nlb-proxy-....elb.us-east-1.amazonaws.com:3128
    httpsProxy: http://lab-ci-27-proxy:x@lab-ci-28-proxy-nlb-proxy-....elb.us-east-1.amazonaws.com:3128
    noProxy: .cluster.local,.ec2.internal,.svc,10.0.0.0/16,10.128.0.0/14,127.0.0.1,169.254.169.254,172.30.0.0/16,api-int.lab415v6.devcluster.openshift.com,localhost
kind: List
```


[regional-e]: https://docs.aws.amazon.com/general/latest/gr/rande.html