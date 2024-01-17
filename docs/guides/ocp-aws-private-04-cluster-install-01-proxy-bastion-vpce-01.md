# Install an OCP cluster on AWS in private subnets with proxy

!!! warning "Experimental steps"
    The steps described on this page are experimental!

### Create install-config.yaml

- Create install-config.yaml

```sh
#export PULL_SECRET_FILE=/path/to/pull-secret
export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
export BASE_DOMAIN=devcluster.openshift.com
export CLUSTER_NAME="lab415v14"
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


## Conclusion

Reigional endpoint is designed for deployments who accepts the cloud api traversing the proxy. The PrivateLink VPC service endpoints (vpce) are designed for very restricted deployments where the traffic must not ongoing the VPC.

So, for the book[2]:
- "Option 1: Create VPC endpoints" says "Create a VPC endpoint....With this option, network traffic remains private between your VPC and the required AWS services". 
- "Option 2: Create a proxy without VPC endpoints"
- "Option 3: Create a proxy with VPC endpoints": 


[endpoint-regional]: https://docs.aws.amazon.com/general/latest/gr/rande.html#regional-endpoints
[endpoint-privatelink]: https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-share-your-services.html


## Scenario bastion in public subnet

Scenario:

- Bastion host in public subnet
- Installer running in bastion node
- Install-config provides VPCe for EC2 and ELB
- NoProxy has VPCe endpoints.
- cluster in private subnets, with blackhole route, and cluster-wide proxy set

Result:
- Cluster installed correctly

[VPCe ec2 and ELB] Installed

```sh
$ ./oc --kubeconfig auth/kubeconfig get clusterversion 
NAME      VERSION       AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.15.0-rc.0   True        False         27s     Cluster version is 4.15.0-rc.0

core@ip-10-0-1-33:~/lab415v7$ ./oc --kubeconfig auth/kubeconfig get nodes
NAME                         STATUS   ROLES                  AGE   VERSION
ip-10-0-0-177.ec2.internal   Ready    worker                 15m   v1.28.4+7aa0a74
ip-10-0-0-211.ec2.internal   Ready    control-plane,master   29m   v1.28.4+7aa0a74
ip-10-0-0-233.ec2.internal   Ready    worker                 15m   v1.28.4+7aa0a74
ip-10-0-0-44.ec2.internal    Ready    control-plane,master   29m   v1.28.4+7aa0a74
ip-10-0-2-192.ec2.internal   Ready    worker                 15m   v1.28.4+7aa0a74
ip-10-0-2-99.ec2.internal    Ready    control-plane,master   29m   v1.28.4+7aa0a74
core@ip-10-0-1-33:~/lab415v7$ ./oc --kubeconfig auth/kubeconfig get proxy -o yaml
apiVersion: v1
items:
- apiVersion: config.openshift.io/v1
  kind: Proxy
  metadata:
    creationTimestamp: "2024-01-16T02:56:06Z"
    generation: 1
    name: cluster
    resourceVersion: "535"
    uid: 8c595491-03d7-4c78-865a-583023a280c8
  spec:
    httpProxy: http://lab-ci-27-proxy:...@lab-ci-28-proxy-nlb-proxy-....elb.us-east-1.amazonaws.com:3128
    httpsProxy: http://lab-ci-27-proxy:...@lab-ci-28-proxy-nlb-proxy-...elb.us-east-1.amazonaws.com:3128
    noProxy: 169.254.169.254,10.0.0.0/16,vpce-0500365b8bbd2ff9e-vc91kojr.ec2.us-east-1.vpce.amazonaws.com,vpce-0bf6dd593b163a98a-jchy4lka.elasticloadbalancing.us-east-1.vpce.amazonaws.com
    trustedCA:
      name: ""
  status:
    httpProxy: ....
    httpsProxy: ....
    noProxy: .cluster.local,.ec2.internal,.svc,10.0.0.0/16,10.128.0.0/14,127.0.0.1,169.254.169.254,172.30.0.0/16,api-int.lab415v7.devcluster.openshift.com,localhost,vpce-0500365b8bbd2ff9e-vc91kojr.ec2.us-east-1.vpce.amazonaws.com,vpce-0bf6dd593b163a98a-jchy4lka.elasticloadbalancing.us-east-1.vpce.amazonaws.com
kind: List
metadata:
  resourceVersion: ""
core@ip-10-0-1-33:~/lab415v7$ ./oc --kubeconfig auth/kubeconfig get cm -n kube-system
NAME                                                   DATA   AGE
bootstrap                                              1      18m
cluster-config-v1                                      1      31m
extension-apiserver-authentication                     6      31m
kube-apiserver-legacy-service-account-token-tracking   1      31m
kube-root-ca.crt                                       1      31m
openshift-service-ca.crt                               1      31m
root-ca                                                1      30m
core@ip-10-0-1-33:~/lab415v7$ ./oc --kubeconfig auth/kubeconfig get cm -n kube-system cluster-config-v1 -o yaml
apiVersion: v1
data:
  install-config: |
    additionalTrustBundlePolicy: Proxyonly
    apiVersion: v1
    baseDomain: devcluster.openshift.com
    compute:
    - architecture: amd64
      hyperthreading: Enabled
      name: worker
      platform: {}
      replicas: 3
    controlPlane:
      architecture: amd64
      hyperthreading: Enabled
      name: master
      platform: {}
      replicas: 3
    metadata:
      creationTimestamp: null
      name: lab415v7
    networking:
      clusterNetwork:
      - cidr: 10.128.0.0/14
        hostPrefix: 23
      machineNetwork:
      - cidr: 10.0.0.0/16
      networkType: OVNKubernetes
      serviceNetwork:
      - 172.30.0.0/16
    platform:
      aws:
        region: us-east-1
        serviceEndpoints:
        - name: ec2
          url: https://vpce-0500365b8bbd2ff9e-vc91kojr.ec2.us-east-1.vpce.amazonaws.com
        - name: elasticloadbalancing
          url: https://vpce-0bf6dd593b163a98a-jchy4lka.elasticloadbalancing.us-east-1.vpce.amazonaws.com
        subnets:
        - subnet-029068ff5c67a8737
        - subnet-0d45a386afab45917
    proxy:
      httpProxy: ...
      httpsProxy: ....
      noProxy: 169.254.169.254,10.0.0.0/16,vpce-0500365b8bbd2ff9e-vc91kojr.ec2.us-east-1.vpce.amazonaws.com,vpce-0bf6dd593b163a98a-jchy4lka.elasticloadbalancing.us-east-1.vpce.amazonaws.com
    publish: Internal
    pullSecret: ""
    sshKey: |
   ....
kind: ConfigMap
metadata:
  annotations:
    kubernetes.io/description: The install-config content used to create the cluster.  The
      cluster configuration may have evolved since installation, so check cluster
      configuration resources directly if you are interested in the current cluster
      state.
  creationTimestamp: "2024-01-16T02:56:04Z"
  name: cluster-config-v1
  namespace: kube-system
  resourceVersion: "515"
  uid: 966c1f99-924b-42c5-963d-3d91d3f7d9d7

..
DEBUG Time elapsed per stage:                      
DEBUG                     cluster: 4m3s            
DEBUG                   bootstrap: 59s             
DEBUG          Bootstrap Complete: 15m26s          
DEBUG                         API: 1m47s           
DEBUG           Bootstrap Destroy: 50s             
DEBUG Cluster Operators Available: 17m33s          
INFO Time elapsed: 39m0s 
```

TODO:
- add the console address (*.apps) to the noProxy list


## Scenario bastion in private subnet

Scenario:

- +^
- bastion/installer in private subnet



https://dev.to/suntong/using-squid-to-proxy-ssl-sites-nj3

https://elatov.github.io/2019/01/using-squid-to-proxy-ssl-sites/#import-certificate-ca-into-the-browser-for-squid



## Mew test


- Ensure HTTPS is exported to the OS and 