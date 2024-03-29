# Installing OpenShift on AWS extending to AWS Outposts on Day-2

Lab steps to install an OpenShift cluster on AWS, extending compute nodes to AWS Outposts as day-2 operations.

Total time running this lab: ~120 minutes (install, setup, test, destroy).

## Install OpenShift

- Export the AWS credentials

```sh
export AWS_DEFAULT_REGION=us-east-1
export AWS_PROFILE=outposts
```

- Install OpenShift cluster

```sh
VERSION="4.15.0-rc.7"
PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64
CLUSTER_NAME=op-05
INSTALL_DIR=${HOME}/openshift-labs/$CLUSTER_NAME
CLUSTER_BASE_DOMAIN=outpost-dev.devcluster.openshift.com
SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub
REGION=us-east-1
AWS_REGION=$REGION

mkdir -p $INSTALL_DIR && cd $INSTALL_DIR

oc adm release extract \
    --tools quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64 \
    -a ${PULL_SECRET_FILE}

tar xvfz openshift-client-linux-${VERSION}.tar.gz
tar xvfz openshift-install-linux-${VERSION}.tar.gz
```

- Install config (option 1): Default zones

```sh
echo "> Creating install-config.yaml"
# Create a single-AZ install config
mkdir -p ${INSTALL_DIR}
cat <<EOF | envsubst > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${CLUSTER_BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${REGION}
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

echo ">> install-config.yaml created: "
cp -v ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config.yaml-bkp

./openshift-install create cluster --dir $INSTALL_DIR --log-level=debug

export KUBECONFIG=$PWD/auth/kubeconfig
```

- Install config (option 2): Limiting only for zones not attached to the Outpost rack (use1a)

```sh
echo "> Creating install-config.yaml"
# Create a single-AZ install config
mkdir -p ${INSTALL_DIR}
cat <<EOF | envsubst > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${CLUSTER_BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
controlPlane:
  platform:
    aws:
      zones:
      - us-east-1b
compute:
- name: worker
  platform:
    aws:
      zones:
      - us-east-1b
platform:
  aws:
    region: ${REGION}
    zones:
    - us-east-1b
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

echo ">> install-config.yaml created: "
cp -v ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config.yaml-bkp

./openshift-install create cluster --dir $INSTALL_DIR --log-level=debug

export KUBECONFIG=$PWD/auth/kubeconfig
```

## Create an AWS Outposts subnets

These steps modify the existing CloudFormation template available in the installer repository to create VPC subnets, especially in Wavelength or Local Zones.

The template is modified to receive the parameter to support AWS Outpost instance ARN.

### Prerequisites

Create Cloudformation template:

> TODO: download from Installer when the field `OutpostArn` is available from [UPI Templates for subnet](https://raw.githubusercontent.com/openshift/installer/master/upi/aws/cloudformation/01_vpc_99_subnet.yaml)


```sh
TEMPLATE_NAME=./cfn-subnet-outposts.yaml
cat <<EOF > ${TEMPLATE_NAME}
AWSTemplateFormatVersion: 2010-09-09
Description: Template for Best Practice Subnets (Public and Private)

Parameters:
  VpcId:
    Description: VPC ID which the subnets will be part.
    Type: String
    AllowedPattern: ^(?:(?:vpc)(?:-[a-zA-Z0-9]+)?\b|(?:[0-9]{1,3}\.){3}[0-9]{1,3})$
    ConstraintDescription: VPC ID must be with valid name, starting with vpc-.*.
  ClusterName:
    Description: Cluster Name or Prefix name to prepend the tag Name for each subnet.
    Type: String
    AllowedPattern: ".+"
    ConstraintDescription: ClusterName parameter must be specified.
  ZoneName:
    Description: Zone Name to create the subnets (Example us-west-2-lax-1a).
    Type: String
    AllowedPattern: ".+"
    ConstraintDescription: ZoneName parameter must be specified.
  PublicRouteTableId:
    Description: Public Route Table ID to associate the public subnet.
    Type: String
    AllowedPattern: ".+"
    ConstraintDescription: PublicRouteTableId parameter must be specified.
  PublicSubnetCidr:
    # yamllint disable-line rule:line-length
    AllowedPattern: ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(1[6-9]|2[0-4]))$
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/16-24.
    Default: 10.0.128.0/20
    Description: CIDR block for Public Subnet
    Type: String
  PrivateRouteTableId:
    Description: Public Route Table ID to associate the Local Zone subnet
    Type: String
    AllowedPattern: ".+"
    ConstraintDescription: PublicRouteTableId parameter must be specified.
  PrivateSubnetCidr:
    # yamllint disable-line rule:line-length
    AllowedPattern: ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(1[6-9]|2[0-4]))$
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/16-24.
    Default: 10.0.128.0/20
    Description: CIDR block for Public Subnet
    Type: String
  PrivateSubnetLabel:
    Default: "private"
    Description: Subnet label to be added when building the subnet name.
    Type: String
  PublicSubnetLabel:
    Default: "public"
    Description: Subnet label to be added when building the subnet name.
    Type: String
  OutpostArn:
    Default: ""
    Description: OutpostArn when creating subnets on AWS Outpost
    Type: String

Conditions:
  OutpostEnabled: !Not [!Equals [!Ref "OutpostArn", ""]]

Resources:
  PublicSubnet:
    Type: "AWS::EC2::Subnet"
    Properties:
      VpcId: !Ref VpcId
      CidrBlock: !Ref PublicSubnetCidr
      AvailabilityZone: !Ref ZoneName
      OutpostArn: !If [ OutpostEnabled, !Ref OutpostArn, !Ref "AWS::NoValue"]
      Tags:
      - Key: Name
        Value: !Join ['-', [ !Ref ClusterName, !Ref PublicSubnetLabel, !Ref ZoneName]]
      # workaround to prevent CCM of using this subnet
      - Key: kubernetes.io/cluster/unmanaged
        Value: true

  PublicSubnetRouteTableAssociation:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Properties:
      SubnetId: !Ref PublicSubnet
      RouteTableId: !Ref PublicRouteTableId

  PrivateSubnet:
    Type: "AWS::EC2::Subnet"
    Properties:
      VpcId: !Ref VpcId
      CidrBlock: !Ref PrivateSubnetCidr
      AvailabilityZone: !Ref ZoneName
      OutpostArn: !If [ OutpostEnabled, !Ref OutpostArn, !Ref "AWS::NoValue"]
      Tags:
      - Key: Name
        Value: !Join ['-', [!Ref ClusterName, !Ref PrivateSubnetLabel, !Ref ZoneName]]
      # workaround to prevent CCM of using this subnet
      - Key: kubernetes.io/cluster/unmanaged
        Value: true

  PrivateSubnetRouteTableAssociation:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Properties:
      SubnetId: !Ref PrivateSubnet
      RouteTableId: !Ref PrivateRouteTableId

Outputs:
  PublicSubnetId:
    Description: Subnet ID of the public subnets.
    Value:
      !Join ["", [!Ref PublicSubnet]]

  PrivateSubnetId:
    Description: Subnet ID of the private subnets.
    Value:
      !Join ["", [!Ref PrivateSubnet]]
EOF
```

### Steps

- Export the variables discovered from Outposts' Rack/instance

```sh
export OutpostId=$(aws outposts list-outposts --query  "Outposts[].OutpostId" --output text)
export OutpostArn=$(aws outposts list-outposts --query  "Outposts[].OutpostArn" --output text)
export OutpostAvailabilityZone=$(aws outposts list-outposts --query  "Outposts[].AvailabilityZone" --output text)
```

- Export required variables to create subnets:

```sh
CLUSTER_ID=$(oc get infrastructures cluster -o jsonpath='{.status.infrastructureName}')
MACHINESET_NAME=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.name}')
MACHINESET_SUBNET_NAME=$(oc get machineset -n openshift-machine-api $MACHINESET_NAME -o json | jq -r '.spec.template.spec.providerSpec.value.subnet.filters[0].values[0]')

VpcId=$(aws ec2 describe-subnets --region $AWS_DEFAULT_REGION --filters Name=tag:Name,Values=$MACHINESET_SUBNET_NAME --query 'Subnets[].VpcId' --output text)

ClusterName=$CLUSTER_ID

PublicRouteTableId=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VpcId \
    | jq -r '.RouteTables[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .RouteTableId }]' \
    | jq -r '.[]  | select(.Name | contains("public")).Id')

```

- Export the private route table ID (choose one):

```sh
# Private gateway Option 1) When deploying NAT GW in the same zone of the Outpost
PrivateRouteTableId=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VpcId \
    | jq -r '.RouteTables[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .RouteTableId }]' \
    | jq -r ".[]  | select(.Name | contains(\"${OutpostAvailabilityZone}\")).Id")

# Private gateway Option 2) When deploying NAT GW in the same zone of the Outpost
NGW_ZONE=us-east-1b
PrivateRouteTableId=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VpcId \
    | jq -r '.RouteTables[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .RouteTableId }]' \
    | jq -r ".[]  | select(.Name | contains(\"${NGW_ZONE}\")).Id")

```

- Export the CIDR blocks for subnets:

```sh
# 1. When the last subnet CIDR is 10.0.192.0/20, it will return 208 (207+1, where 207 is the last 3rd octet of the network)
# 2. Create /24 subnets
NextFreeNet=$(echo "$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VpcId | jq  -r ".Subnets[].CidrBlock" | sort -t . -k 3,3n -k 4,4n | tail -n1 | xargs ipcalc | grep ^HostMax | awk '{print$2}' | awk -F'.' '{print$3}') + 1" | bc)
PublicSubnetCidr="10.0.${NextFreeNet}.0/24"

NextFreeNet=$(( NextFreeNet + 1 ))
PrivateSubnetCidr="10.0.${NextFreeNet}.0/24"
```

- Review the variables before proceeding:

```sh
cat <<EOF
AWS_REGION=$AWS_REGION
AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
OutpostId=$OutpostId
OutpostArn=$OutpostArn
OutpostAvailabilityZone=$OutpostAvailabilityZone
ClusterName=$ClusterName
PublicRouteTableId=$PublicRouteTableId
PrivateRouteTableId=$PrivateRouteTableId
PublicSubnetCidr=$PublicSubnetCidr
PrivateSubnetCidr=$PrivateSubnetCidr
EOF
```

- Create the subnet:

```sh
STACK_NAME=${CLUSTER_ID}-subnets-outpost
aws cloudformation create-stack --stack-name $STACK_NAME \
    --region ${AWS_DEFAULT_REGION} \
    --template-body file://${TEMPLATE_NAME} \
    --parameters \
        ParameterKey=VpcId,ParameterValue="${VpcId}" \
        ParameterKey=ClusterName,ParameterValue="${ClusterName}" \
        ParameterKey=ZoneName,ParameterValue="${OutpostAvailabilityZone}" \
        ParameterKey=PublicRouteTableId,ParameterValue="${PublicRouteTableId}" \
        ParameterKey=PublicSubnetCidr,ParameterValue="${PublicSubnetCidr}" \
        ParameterKey=PrivateRouteTableId,ParameterValue="${PrivateRouteTableId}" \
        ParameterKey=PrivateSubnetCidr,ParameterValue="${PrivateSubnetCidr}" \
        ParameterKey=OutpostArn,ParameterValue="${OutpostArn}" \
        ParameterKey=PrivateSubnetLabel,ParameterValue="private-outpost" \
        ParameterKey=PublicSubnetLabel,ParameterValue="public-outpost"

aws cloudformation wait stack-create-complete --stack-name ${STACK_NAME}

aws cloudformation describe-stacks --stack-name ${STACK_NAME}
```

- List the subnets in Outpost:

```sh
aws ec2 describe-subnets --filters Name=outpost-arn,Values=${OutpostArn} Name=vpc-id,Values=$VpcId
```

- Export the subnets according to your needs:

> TODO get from CloudFormation template instead of discovering

```sh
OutpostPublicSubnetId=$(aws ec2 describe-subnets --filters Name=outpost-arn,Values=${OutpostArn} Name=vpc-id,Values=$VpcId | jq -r '.Subnets[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .SubnetId }]'  | jq -r '.[] | select(.Name | contains("public")).Id')

OutpostPrivateSubnetId=$(aws ec2 describe-subnets --filters Name=outpost-arn,Values=${OutpostArn} Name=vpc-id,Values=$VpcId | jq -r '.Subnets[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .SubnetId }]'  | jq -r '.[] | select(.Name | contains("private")).Id')
```

## Create Machine set manifest

- Export required variables:

```sh
# Choose from $ aws outposts get-outpost-instance-types
OutpostInstanceType=m5.xlarge

cat <<EOF
OutpostPublicSubnetId=$OutpostPublicSubnetId
OutpostPrivateSubnetId=$OutpostPrivateSubnetId
OutpostInstanceType=$OutpostInstanceType
EOF
```

- Create machine set patch:

```sh
cat << EOF > ./outpost-machineset-patch.yaml
metadata:
  annotations: {}
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
    location: outposts
  name: ${CLUSTER_ID}-outposts-${OutpostAvailabilityZone}
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-outposts-${OutpostAvailabilityZone}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: outposts
        machine.openshift.io/cluster-api-machine-type: outposts
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-outposts-${OutpostAvailabilityZone}
        location: outposts
    spec:
      metadata:
        labels:
          node-role.kubernetes.io/outposts: ""
          location: outposts
      providerSpec:
        value:
          blockDevices:
            - ebs:
                volumeSize: 120
                volumeType: gp2
          instanceType: ${OutpostInstanceType}
          placement:
            availabilityZone: ${OutpostAvailabilityZone}
            region: ${AWS_REGION}
          subnet:
            id: ${OutpostPrivateSubnetId}
      taints: 
        - key: node-role.kubernetes.io/outposts
          effect: NoSchedule
EOF
```

- Retrieve the Machine set and merge it into yours

```sh
oc get machineset -n openshift-machine-api $(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.name}') -o yaml \
    | yq4 'del(
        .metadata.annotations,
        .metadata.uid,
        .spec.template.metadata.labels,
        .spec.template.spec.providerSpec.value.subnet,
        .spec.template.spec.providerSpec.value.blockDevices,
        .status)' \
    > ./outpost-tpl-00.yaml

yq4 ea '. as $item ireduce ({}; . * $item )' ./outpost-tpl-00.yaml ./outpost-machineset-patch.yaml > ./outpost-machineset.yaml
```

- Review and create the machine set

```sh
oc create -f ./outpost-machineset.yaml
```

Example output

```sh
$ oc get nodes -l node-role.kubernetes.io/outpost
NAME                         STATUS   ROLES            AGE   VERSION
ip-10-0-209-9.ec2.internal   Ready    outpost,worker   12h   v1.28.6+f1618d5


$ $ oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=outpost
NAME                                    PHASE     TYPE        REGION      ZONE         AGE
otp-00-n89jb-outpost-us-east-1a-zs5ps   Running   m5.xlarge   us-east-1   us-east-1a   12h


$ oc get machineset -n openshift-machine-api -l location=outpost
NAME                              DESIRED   CURRENT   READY   AVAILABLE   AGE   LABELS
otp-00-n89jb-outpost-us-east-1a   1         1         1       1           12h   machine.openshift.io/cluster-api-cluster=otp-00-n89jb
```

## Changing cluster network MTU 

The correct cluster network MTU is required for the correctly operation of the cluster network.

The steps below adjust the MTU based on the supported information from AWS: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/network_mtu.html

> Currently the supported value is: 1300

- check the current value for cluster network MTU:

```sh
$ oc get network.config cluster -o yaml | yq4 ea .status
clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
clusterNetworkMTU: 8901
networkType: OVNKubernetes
serviceNetwork:
  - 172.30.0.0/16
```

- check current value for host network MTU:

```sh
NODE_NAME=$(oc get nodes -l location=outposts -o jsonpath={.items[0].metadata.name})
# Hardware MTU
oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "ip address show | grep -E '^(.*): ens'" 2>/dev/null
# CN MTU
oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "ip address show | grep -E '^(.*): br-int'" 2>/dev/null
```

Example output:

```sh
2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq master ovs-system state UP group default qlen 1000
5: br-int: <BROADCAST,MULTICAST> mtu 8901 qdisc noop state DOWN group default qlen 1000
```

- Patch

```sh
OVERLAY_TO=1200
OVERLAY_FROM=$(oc get network.config cluster -o jsonpath='{.status.clusterNetworkMTU}')
MACHINE_TO=$(oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "ip address show | grep -E '^([0-9]): ens'" 2>/dev/null | awk -F'mtu ' '{print$2}' | cut -d ' ' -f1)

oc patch Network.operator.openshift.io cluster --type=merge --patch \
  "{\"spec\": { \"migration\": { \"mtu\": { \"network\": { \"from\": $OVERLAY_FROM, \"to\": ${OVERLAY_TO} } , \"machine\": { \"to\" : $MACHINE_TO } } } } }"
```

- Wait until the machines are updated:
    - MachineConfigPool must be progressing
    - Nodes will be restarted
    - Nodes must have the correct MTU for the overlay interface

```sh
function check_node_mcp() {
    echo ">>>> $(date)"
    echo -e "Network migration status: $(oc get network.config cluster -o jsonpath={.status.migration})"
    oc get mcp
    oc get nodes
    MCP_WORKER=$(oc get mcp worker -o jsonpath='{.spec.configuration.name}')
    MCP_MASTER=$(oc get mcp master -o jsonpath='{.spec.configuration.name}')
    echo -e "\n Checking if nodes have desired config: master[${MCP_MASTER}] worker[${MCP_WORKER}]"
    for NODE in $(oc get nodes -o jsonpath='{.items[*].metadata.name}');
    do
        MCP_NODE=$(oc get node ${NODE} -o json | jq -r '.metadata.annotations["machineconfiguration.openshift.io/currentConfig"]');
        if [[ "$MCP_NODE" == "$MCP_MASTER" ]] || [[ "$MCP_NODE" == "$MCP_WORKER" ]];
        then
            NODE_CN_MTU=$(oc debug node/${NODE} --  chroot /host /bin/bash -c "ip address show | grep -E '^([0-9]): br-int'" 2>/dev/null | awk -F'mtu ' '{print$2}' | cut -d ' ' -f1)
            NODE_HOST_MTU=$(oc debug node/${NODE} --  chroot /host /bin/bash -c "ip address show | grep -E '^([0-9]): ens'" 2>/dev/null | awk -F'mtu ' '{print$2}' | cut -d ' ' -f1)
            echo -e "$NODE\t OK \t Interface MTU HOST(ens*)=${NODE_HOST_MTU} CN(br-ext)=${NODE_CN_MTU}";
            continue;
        fi;
        echo -e "$NODE\t FAIL \t CURRENT[${MCP_NODE}] != DESIRED[${MCP_WORKER} || ${MCP_MASTER}]";
    done
}

while true; do check_node_mcp; sleep 15; done
```

- Apply the migration:

```sh
oc patch Network.operator.openshift.io cluster --type=merge --patch \
  "{\"spec\": { \"migration\": null, \"defaultNetwork\":{ \"ovnKubernetesConfig\": { \"mtu\": ${OVERLAY_TO} }}}}"
```

- Wait for cluster stable:

```sh
while true; do check_node_mcp; sleep 15; done
```

Example output:

```sh
>>>> Tue Feb 27 12:22:32 AM -03 2024
Network migration status: 
NAME     CONFIG                                             UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
master   rendered-master-f359387b39abb9eec25b51403d960164   False     True       False      3              1                   1                     0                      10h
worker   rendered-worker-72552cec3c784dd9ae7ef388773989da   False     True       False      4              3                   3                     0                      10h
NAME                           STATUS                     ROLES                  AGE   VERSION
ip-10-0-11-245.ec2.internal    Ready                      worker                 10h   v1.28.6+f1618d5
ip-10-0-13-57.ec2.internal     Ready                      control-plane,master   10h   v1.28.6+f1618d5
ip-10-0-20-127.ec2.internal    Ready                      worker                 10h   v1.28.6+f1618d5
ip-10-0-209-107.ec2.internal   Ready                      outposts,worker        8h    v1.28.6+f1618d5
ip-10-0-23-35.ec2.internal     Ready,SchedulingDisabled   control-plane,master   10h   v1.28.6+f1618d5
ip-10-0-36-105.ec2.internal    Ready,SchedulingDisabled   worker                 10h   v1.28.6+f1618d5
ip-10-0-45-247.ec2.internal    Ready                      control-plane,master   10h   v1.28.6+f1618d5

 Checking if nodes have desired config: master[rendered-master-6eb66809b570fd83e0afe136647d94e5] worker[rendered-worker-82cdb4cc3854db575b7fe36e10c7de0c]
ip-10-0-11-245.ec2.internal      OK      Interface MTU HOST(ens*)=9001 CN(br-ext)=1200
ip-10-0-13-57.ec2.internal       OK      Interface MTU HOST(ens*)=9001 CN(br-ext)=1200
ip-10-0-20-127.ec2.internal      OK      Interface MTU HOST(ens*)=9001 CN(br-ext)=1200
ip-10-0-209-107.ec2.internal     OK      Interface MTU HOST(ens*)=9001 CN(br-ext)=1200
ip-10-0-23-35.ec2.internal       FAIL    CURRENT[rendered-master-f359387b39abb9eec25b51403d960164] != DESIRED[rendered-worker-82cdb4cc3854db575b7fe36e10c7de0c || rendered-master-6eb66809b570fd83e0afe136647d94e5]
ip-10-0-36-105.ec2.internal      FAIL    CURRENT[rendered-worker-72552cec3c784dd9ae7ef388773989da] != DESIRED[rendered-worker-82cdb4cc3854db575b7fe36e10c7de0c || rendered-master-6eb66809b570fd83e0afe136647d94e5]
ip-10-0-45-247.ec2.internal      FAIL    CURRENT[rendered-master-f359387b39abb9eec25b51403d960164] != DESIRED[rendered-worker-82cdb4cc3854db575b7fe36e10c7de0c || rendered-master-6eb66809b570fd83e0afe136647d94e5]
...
```

- Validating cluster network MTU by pulling images from internal registry from the Outpost node:

```sh
NODE_NAME=$(oc get nodes -l node-role.kubernetes.io/outposts='' -o jsonpath={.items[0].metadata.name})
KPASS=$(cat auth/kubeadmin-password)

API_INT=$(oc get infrastructures cluster -o jsonpath={.status.apiServerInternalURI})

oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "\
oc login --insecure-skip-tls-verify -u kubeadmin -p ${KPASS} ${API_INT}; \
podman login -u kubeadmin -p \$(oc whoami -t) image-registry.openshift-image-registry.svc:5000; \
podman pull image-registry.openshift-image-registry.svc:5000/openshift/tests"
```

Example output:

```sh
Starting pod/ip-10-0-209-9ec2internal-debug ...
To use host binaries, run `chroot /host`
WARNING: Using insecure TLS client config. Setting this option is not supported!

Login successful.

You have access to 70 projects, the list has been suppressed. You can list all projects with 'oc projects'

Using project "default".
Welcome! See 'oc help' to get started.
Login Succeeded!
Trying to pull image-registry.openshift-image-registry.svc:5000/openshift/tests:latest...
Getting image source signatures
Copying blob sha256:2799c1fb4d899f5800972dbe30772eb0ecbf423cc4221eca47f8c25873681089
..
Writing manifest to image destination
Storing signatures
ec9d578280946791263973138ea0955f665a684a55ef332313480f7f1dfceece

Removing debug pod ...
```

## Creating User Workloads in Outpost


- Create the application

```sh
APP_NAME=myapp-outpost
cat << EOF > ./outpost-app.yaml
kind: Namespace
apiVersion: v1
metadata:
  name: ${APP_NAME}
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NAME}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: gp2-csi 
  volumeMode: Filesystem
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NAME}
spec:
  selector:
    matchLabels:
      app: ${APP_NAME}
  replicas: 1
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        location: outposts
    spec:
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      nodeSelector: 
        node-role.kubernetes.io/outposts: ''
      tolerations: 
      - key: "node-role.kubernetes.io/outposts"
        operator: "Equal"
        value: ""
        effect: "NoSchedule"
      containers:
        - image: openshift/origin-node
          command:
           - "/bin/socat"
          args:
            - TCP4-LISTEN:8080,reuseaddr,fork
            - EXEC:'/bin/bash -c \"printf \\\"HTTP/1.0 200 OK\r\n\r\n\\\"; sed -e \\\"/^\r/q\\\"\"'
          imagePullPolicy: Always
          name: echoserver
          ports:
            - containerPort: 8080
          volumeMounts:
            - mountPath: "/mnt/storage"
              name: data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ${APP_NAME}
EOF

oc create -f ./outpost-app.yaml
```

- Check deployments

```sh
$ oc get pv -n myapp-outpost
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                         STORAGECLASS   REASON   AGE
pvc-0ea0c08b-5993-4e9d-93c2-201e77dcb9d8   10Gi       RWO            Delete           Bound    myapp-outpost/myapp-outpost   gp2-csi                 16s

$ oc get all -n  myapp-outpost
Warning: apps.openshift.io/v1 DeploymentConfig is deprecated in v4.14+, unavailable in v4.10000+
NAME                                READY   STATUS    RESTARTS   AGE
pod/myapp-outpost-cb94f9cd6-npczx   1/1     Running   0          20m

NAME                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/myapp-outpost   1/1     1            1           77m

NAME                                      DESIRED   CURRENT   READY   AGE
replicaset.apps/myapp-outpost-cb94f9cd6   1         1         1       77m
```

## Expose the deployment through services

Expose the deployments using different service types.

### Service NodePort

- Deploy services exposing the NodePort:

```sh
cat << EOF > ./outpost-svc-np.yaml
---
apiVersion: v1
kind: Service 
metadata:
  name:  ${APP_NAME}-np
  namespace: ${APP_NAME}
spec:
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: NodePort
  selector: 
    app: ${APP_NAME}
EOF
```

<!-- 
### Service LoadBalancer with AWS Classic Load Balancer (fail)

```sh
cat << EOF | oc create -f -
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${APP_NAME}-clb
  name: ${APP_NAME}-clb
  namespace: ${APP_NAME}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-subnets: ${OutpostPublicSubnetId}
    service.beta.kubernetes.io/aws-load-balancer-target-node-labels: node-role.kubernetes.io/outpost=''
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    app: ${APP_NAME}
  type: LoadBalancer
EOF
```

Error message
```
$ oc describe  svc myapp-outpost-clb -n ${APP_NAME}
Events:
  Type     Reason                  Age   From                Message
  ----     ------                  ----  ----                -------
  Normal   EnsuringLoadBalancer    9s (x4 over 48s)  service-controller  Ensuring load balancer
  Warning  SyncLoadBalancerFailed  8s                service-controller  Error syncing load balancer: failed to ensure load balancer: ValidationError: You cannot use Outposts subnets for load balancers of type 'classic'
           status code: 400, request id: a90e376b-4ac4-4d5a-b3d3-127e025168f
```

- Test creating service in the region


```sh
cat << EOF | oc create -f -
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${APP_NAME}-lb-default
  name: ${APP_NAME}-lb-default
  namespace: ${APP_NAME}
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    app: ${APP_NAME}
  type: LoadBalancer
EOF
``` -->

### Exposing the service with ALB ingress

Steps to deploy the service using Application Load Balancer on Outpost with ALBO (AWS Load Balancer Operator).

#### Install ALBO

- Setup requirements to install ALBO through OLM:

```sh
ALBO_NS=aws-load-balancer-operator

# Create the namespace
# Create the CredentialsRequests
# Subscribe to the operator
cat << EOF | oc create -f -
---
kind: Namespace
apiVersion: v1
metadata:
  name: ${ALBO_NS}
---
apiVersion: cloudcredential.openshift.io/v1
kind: CredentialsRequest
metadata:
  name: aws-load-balancer-operator
  namespace: openshift-cloud-credential-operator
spec:
  providerSpec:
    apiVersion: cloudcredential.openshift.io/v1
    kind: AWSProviderSpec
    statementEntries:
      - action:
          - ec2:DescribeSubnets
        effect: Allow
        resource: "*"
      - action:
          - ec2:CreateTags
          - ec2:DeleteTags
        effect: Allow
        resource: arn:aws:ec2:*:*:subnet/*
      - action:
          - ec2:DescribeVpcs
        effect: Allow
        resource: "*"
  secretRef:
    name: aws-load-balancer-operator
    namespace: aws-load-balancer-operator
  serviceAccountNames:
    - aws-load-balancer-operator-controller-manager

---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: $ALBO_NS
  namespace: $ALBO_NS
spec:
  targetNamespaces:
  - $ALBO_NS

---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: $ALBO_NS
  namespace: $ALBO_NS
spec:
  channel: stable-v0
  installPlanApproval: Automatic 
  name: $ALBO_NS
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc get CredentialsRequest aws-load-balancer-operator -n openshift-cloud-credential-operator
oc get OperatorGroup $ALBO_NS -n $ALBO_NS
oc get Subscription $ALBO_NS -n $ALBO_NS
oc get installplan -n $ALBO_NS
oc get all -n $ALBO_NS
oc get pods -w -n $ALBO_NS
```

- Wait for the operator be created, then create the controller:

```bash
# Create cluster ALBO controller
cat <<EOF | oc create -f -
apiVersion: networking.olm.openshift.io/v1alpha1
kind: AWSLoadBalancerController 
metadata:
  name: cluster 
spec:
  subnetTagging: Auto 
  ingressClass: cloud 
  config:
    replicas: 2 
  enabledAddons: 
    - AWSWAFv2
EOF

# Wait for the controller be in Running
oc get pods -w -n $ALBO_NS -l app.kubernetes.io/name=aws-load-balancer-operator
```


#### Create ALB ingress in Outpost


- Deploy the service using the ingress

```sh
SVC_NAME_ALB=${APP_NAME}-alb
cat << EOF > ./outpost-svc-alb.yaml
---
apiVersion: v1
kind: Service 
metadata:
  name: ${SVC_NAME_ALB}
  namespace: ${APP_NAME}
spec:
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: NodePort
  selector:
    app: ${APP_NAME}
EOF

# review and apply
oc create -f ./outpost-svc-alb.yaml
```

- Create the Ingress in the Outpost subnet selecting only the instance running in Outpost as a target:

```sh
INGRESS_NAME=alb-outpost-public
cat << EOF | oc create -f -
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $INGRESS_NAME
  namespace: ${APP_NAME}
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: instance
    alb.ingress.kubernetes.io/subnets: ${OutpostPublicSubnetId}
    alb.ingress.kubernetes.io/target-node-labels: location=outposts
  labels:
    location: outpost
spec:
  ingressClassName: cloud
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${SVC_NAME_ALB}
                port:
                  number: 80
EOF
```

Check if the ingress has been created:

```sh
oc get ingress alb-outpost-public -n ${APP_NAME}
```

Try to access the Load Balancer

```sh
APP_INGRESS=$(./oc get ingress -n ${APP_NAME} alb-outpost-public \
  --template='{{(index .status.loadBalancer.ingress 0).hostname}}')

while ! curl $APP_INGRESS; do sleep 5; done
```

Example output:

```sh
$ while ! curl $APP_INGRESS; do sleep 5; done
curl: (6) Could not resolve host: k8s-myappout-outpostm-8f4b5eecb7-432946071.us-east-1.elb.amazonaws.com
curl: (6) Could not resolve host: k8s-myappout-outpostm-8f4b5eecb7-432946071.us-east-1.elb.amazonaws.com
curl: (6) Could not resolve host: k8s-myappout-outpostm-8f4b5eecb7-432946071.us-east-1.elb.amazonaws.com
curl: (6) Could not resolve host: k8s-myappout-outpostm-8f4b5eecb7-432946071.us-east-1.elb.amazonaws.com
curl: (6) Could not resolve host: k8s-myappout-outpostm-8f4b5eecb7-432946071.us-east-1.elb.amazonaws.com
curl: (6) Could not resolve host: k8s-myappout-outpostm-8f4b5eecb7-432946071.us-east-1.elb.amazonaws.com
curl: (6) Could not resolve host: k8s-myappout-outpostm-8f4b5eecb7-432946071.us-east-1.elb.amazonaws.com
GET / HTTP/1.1
X-Forwarded-For: 189.114.197.154
X-Forwarded-Proto: http
X-Forwarded-Port: 80
Host: k8s-myappout-outpostm-8f4b5eecb7-432946071.us-east-1.elb.amazonaws.com
X-Amzn-Trace-Id: Root=1-65cfd390-56d5743b52a8b84148e8562f
User-Agent: curl/8.0.1
Accept: */*
```

#### ALBO testing w/ unmanaged subnets

Validating ingress created using ALBO steps when the Outpost subnets are tagged with the "unmanaged" cluster tag.

> Note: those steps have been created to validate the open question for [this thread](https://github.com/openshift/openshift-docs/pull/71263/files#r1503214052).

Checklist:

1. Subnets created by CloudFormation
```sh
$ aws cloudformation  describe-stacks --stack-name ${CLUSTER_ID}-subnets-outpost | jq '.Stacks[].Outputs[] | select(.OutputKey=="PublicSubnetId")'
{
  "OutputKey": "PublicSubnetId",
  "OutputValue": "subnet-0f2c7cb846fd7c55a",
  "Description": "Subnet ID of the public subnets."
}

PUBLIC_SUBNET=$(aws cloudformation  describe-stacks --stack-name ${CLUSTER_ID}-subnets-outpost | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="PublicSubnetId").OutputValue')
```

2. Tags from those subnets
```sh
$ aws ec2 describe-subnets --subnet-ids ${PUBLIC_SUBNET} | jq '.Subnets[] | [.SubnetId, (.Tags[] | select(.Key | contains("kubernetes"))) ]'
[
  "subnet-0f2c7cb846fd7c55a",
  {
    "Key": "kubernetes.io/cluster/unmanaged",
    "Value": "true"
  }
]
```

3. Ingress created and ALB FQDN
```sh
$ oc get ingress -n ${APP_NAME}
NAME                 CLASS   HOSTS   ADDRESS                                                                   PORTS   AGE
alb-outpost-public   cloud   *       k8s-myappout-alboutpo-091a2e4eac-1527379645.us-east-1.elb.amazonaws.com   80      15s

ALB_FQDN=$(oc get ingress -n ${APP_NAME} alb-outpost-public \
  --template='{{(index .status.loadBalancer.ingress 0).hostname}}')

echo $ALB_FQDN

$ echo $ALB_FQDN
k8s-myappout-alboutpo-091a2e4eac-1527379645.us-east-1.elb.amazonaws.com
```

4. ALB subnets (created by ALBC)
```sh
$ aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select(.DNSName==\"${ALB_FQDN}\").AvailabilityZones"
[
  {
    "ZoneName": "us-east-1a",
    "SubnetId": "subnet-0f2c7cb846fd7c55a",
    "OutpostId": "op-0a759e7fbceffcb86",
    "LoadBalancerAddresses": []
  }
]
```

5. ALB's target instances (in the target group)
```sh
ALB_ARN=$(aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select(.DNSName==\"${ALB_FQDN}\").LoadBalancerArn")
TG_ARN=$(aws elbv2 describe-target-groups --load-balancer-arn $ALB_ARN  | jq -r .TargetGroups[0].TargetGroupArn)

$ aws elbv2 describe-target-health  --target-group-arn $TG_ARN
{
    "TargetHealthDescriptions": [
        {
            "Target": {
                "Id": "i-09ea38f1672bbd7be",
                "Port": 30474
            },
            "HealthCheckPort": "30474",
            "TargetHealth": {
                "State": "healthy"
            }
        }
    ]
}
```

6. Testing
```sh
$ APP_INGRESS=$(./oc get ingress -n ${APP_NAME} alb-outpost-public \
  --template='{{(index .status.loadBalancer.ingress 0).hostname}}')

while ! curl $APP_INGRESS; do sleep 5; done
GET / HTTP/1.1
X-Forwarded-For: 179.193.53.233
X-Forwarded-Proto: http
X-Forwarded-Port: 80
Host: k8s-myappout-alboutpo-091a2e4eac-1527379645.us-east-1.elb.amazonaws.com
X-Amzn-Trace-Id: Root=1-65dceb86-05ffe6523dc625cf64c07ffe
User-Agent: curl/8.0.1
Accept: */*
```

### Validating Service LoadBalancer in Outposts

Exercising service LoadBalancer scenarios to understand the limitations and workarounds required.

| ID | Test Summary | Zones | `unmanaged` tag?* | Result |
| -- | -- | -- | -- | -- |
| 1A | CLB default | all | yes | Failed (inconsistent) |
| 1B | CLB w/ OP-parent subnet only and OP node selector | 1a | yes | Failed(Couldn't connect to server) |
| 1C | NLB default | all | yes | Failed (unable to connect to the backend app) |
| 1D | NLB w/ OP-parent subnet only and OP node selector | 1a | yes | Failed(Connection reset by peer) |
| 2 | CLB w/ OP subnets | 1a-OP | yes | Failed (unsupported by AWS) |
| 3 | CLB w/ OP nodes (default subnets) | all | yes | Failed |
| 4 | NLB replace from CLB. OP-subnets w/ unmanaged tag (non OP zone) | 1b,1c | yes | Success(selected correct subnets) |
| 5A | NLB w/ OP-subnets w/ unmanaged tag (non OP zone) | 1b,1c | yes | Success(selected correct subnets) |
| 5B | NLB w/ OP-subnet annotation | 1a-OP | yes | Failed(unsupported by AWS) |

*`unmanaged` subnet tag means the scenarios with the Outpost subnet have been tagged with `kubernetes.io/cluster/unmanaged:true` to prevent CCM from discovering the Outpost subnet when creating service LB.

#### Test 1A: Service CLB default (inconsistent)

Description/Scenario:

- LB Type: default (CLB, default for CCM)
- Extra configuration: None
- Result: failed
- Reason: CLB attached the Outpost node but can't route traffic to it.

Result: 
- Can connect to the listener but can't reach the backend
- unreachable requests

Default service CLB:

```sh
SVC_NAME_CLB=${APP_NAME}-clb-default
cat << EOF | oc create -f -
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${APP_NAME}
  name: ${SVC_NAME_CLB}
  namespace: ${APP_NAME}
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8081
  selector:
    app: ${APP_NAME}
  type: LoadBalancer
EOF
```

- Test:

```sh
APP_CLB=$(./oc get svc -n ${APP_NAME} ${SVC_NAME_CLB} \
  -o jsonpath={.status.loadBalancer.ingress[0].hostname})

echo "APP_CLB=${APP_CLB}"
while ! curl -v $APP_CLB; do sleep 5; done

while true; do curl -w'%{http_code}' $APP_CLB; do date; done
```

Example output:

```text
APP_CLB=accb46c817bc8408381f4f171895a47b-1332448957.us-east-1.elb.amazonaws.com
*   Trying 54.147.88.143:80...
* Connected to accb46c817bc8408381f4f171895a47b-1332448957.us-east-1.elb.amazonaws.com (54.147.88.143) port 80 (#0)
> GET / HTTP/1.1
> Host: accb46c817bc8408381f4f171895a47b-1332448957.us-east-1.elb.amazonaws.com
> User-Agent: curl/8.0.1
> Accept: */*
> 

* Recv failure: Connection reset by peer
* Closing connection 0
curl: (56) Recv failure: Connection reset by peer
*   Trying 54.210.221.253:80...
* Connected to accb46c817bc8408381f4f171895a47b-1332448957.us-east-1.elb.amazonaws.com (54.210.221.253) port 80 (#0)
> GET / HTTP/1.1
> Host: accb46c817bc8408381f4f171895a47b-1332448957.us-east-1.elb.amazonaws.com
> User-Agent: curl/8.0.1
> Accept: */*
> 
```

#### Test 1B: Service CLB limiting Outposts nodes and parent subnet

Scenario:
- VPC created by installer
- Outpost subnet created by CloudFormation template with "unmanaged" subnet tag
- LB Type: default (CLB, default for CCM)
- Service LoadBalancer created with annotations:
    - subnet: using **only the subnet** for the Outpost's Parent zone
    - targets/nodes: limited by attaching only nodes with the label `location=outposts`

Result:
- TBD

Steps:

- Create the service:
```sh
OUTPOST_PARENT_ZONE=$(aws outposts list-outposts --query "Outposts[].AvailabilityZone" --output text)
PUBLIC_SUBNET_OP_PARENT_ZONE=$(aws ec2 describe-subnets \
    --filters Name=vpc-id,Values=$VpcId Name=availability-zone,Values=$OUTPOST_PARENT_ZONE \
    | jq -r '.Subnets[] | {"Id": .SubnetId, "Name": .Tags[]|select(.Key=="Name")|select(.Value | contains("public")) | select(.Value | contains("outpost") | not).Value }.Id')

SVC_NAME_CLB_SB_NODE_OP=${APP_NAME}-clb-sb-nd
cat << EOF | oc create -f -
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${APP_NAME}
  name: ${SVC_NAME_CLB_SB_NODE_OP}
  namespace: ${APP_NAME}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-subnets: ${PUBLIC_SUBNET_OP_PARENT_ZONE}
    service.beta.kubernetes.io/aws-load-balancer-target-node-labels: location=outposts
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8081
  selector:
    app: ${APP_NAME}
  type: LoadBalancer
EOF
```

- Test:

```sh
APP_CLB_SB_NODE_OP=$(./oc get svc -n ${APP_NAME} ${SVC_NAME_CLB_SB_NODE_OP} \
  -o jsonpath={.status.loadBalancer.ingress[0].hostname})

echo "APP_CLB_SB_NODE_OP=${APP_CLB_SB_NODE_OP}"
while ! curl $APP_CLB_SB_NODE_OP; do sleep 5; done
```

Output:
```
echo "APP_CLB_SB_NODE_OP=${APP_CLB_SB_NODE_OP}"
while ! curl $APP_CLB_SB_NODE_OP; do sleep 5; done
APP_CLB_SB_NODE_OP=a4b1fb0033cbf4925b2b6abb66acb6b6-222743820.us-east-1.elb.amazonaws.com
curl: (56) Recv failure: Connection reset by peer
curl: (56) Recv failure: Connection reset by peer
curl: (56) Recv failure: Connection reset by peer
...
```

#### Test 1C: Service NLB default

Scenario:

- Similar to 1A but using NLB LB type
- Similar 5A but VPC has subnets on zone A (where OP rack is attached)

Results: Failed (unable to connect to the backend app)

Steps:

```sh
SVC_NAME_NLB_DEF=${APP_NAME}-nlb-def
cat << EOF | oc create -f -
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${APP_NAME}
  name: ${SVC_NAME_NLB_DEF}
  namespace: ${APP_NAME}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8081
  selector:
    app: ${APP_NAME}
  type: LoadBalancer
EOF
```

- Test:

```sh
APP_NLB_DEF=$(oc get svc ${SVC_NAME_NLB_DEF} -n ${APP_NAME} -o jsonpath={.status.loadBalancer.ingress[0].hostname})

echo "APP_NLB_DEF=${APP_NLB_DEF}"
while ! curl $APP_NLB_DEF; do sleep 10; done
```

Output:

```
echo "APP_NLB_DEF=${APP_NLB_DEF}"
while ! curl $APP_NLB_DEF; do sleep 10; done
APP_NLB_DEF=a36f257114ba940b6bf4c17055a07657-bf40210300eb8592.elb.us-east-1.amazonaws.com
curl: (6) Could not resolve host: a36f257114ba940b6bf4c17055a07657-bf40210300eb8592.elb.us-east-1.amazonaws.com
...
curl: (6) Could not resolve host: a36f257114ba940b6bf4c17055a07657-bf40210300eb8592.elb.us-east-1.amazonaws.com
...
```

#### Test 1D: Service NLB limiting Outposts nodes and parent subnet

Scenario:

- Similar to 1B but using NLB LB type

Results: Failed (unable to connect to the backend app)

Steps:

```sh
SVC_NAME_NLB_SB_NODE_OP=${APP_NAME}-nlb-sb-nd
cat << EOF | oc create -f -
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${APP_NAME}
  name: ${SVC_NAME_NLB_SB_NODE_OP}
  namespace: ${APP_NAME}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
    service.beta.kubernetes.io/aws-load-balancer-subnets: ${PUBLIC_SUBNET_OP_PARENT_ZONE}
    service.beta.kubernetes.io/aws-load-balancer-target-node-labels: location=outposts
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8081
  selector:
    app: ${APP_NAME}
  type: LoadBalancer
EOF
```

- Test:

```sh
APP_NLB_SB_NODE_OP=$(oc get svc ${SVC_NAME_NLB_SB_NODE_OP} -n ${APP_NAME} -o jsonpath={.status.loadBalancer.ingress[0].hostname})

echo "APP_NLB_SB_NODE_OP=${APP_NLB_SB_NODE_OP}"
while ! curl $APP_NLB_SB_NODE_OP; do sleep 10; done
```

Output:

```
while ! curl $APP_NLB_SB_NODE_OP; do sleep 10; done
APP_NLB_SB_NODE_OP=ac87494bab8344afeb1aaaaa841e898b-404654f41be20122.elb.us-east-1.amazonaws.com
curl: (6) Could not resolve host: ac87494bab8344afeb1aaaaa841e898b-404654f41be20122.elb.us-east-1.amazonaws.com
....
curl: (6) Could not resolve host: ac87494bab8344afeb1aaaaa841e898b-404654f41be20122.elb.us-east-1.amazonaws.com
...
curl: (7) Failed to connect to ac87494bab8344afeb1aaaaa841e898b-404654f41be20122.elb.us-east-1.amazonaws.com port 80 after 170 ms: Couldn't connect to server
```

#### Test 2: Service CLB with Outpost subnets (not supported)

Description:

- LB Type: custom Outpost subnet
- Extra configuration:
    - Annotation:
        - service.beta.kubernetes.io/aws-load-balancer-subnets: ${OutpostPublicSubnetId}
- Result: failed
- Reason: CLB does not support Outpost subnets.

Result: unsupported. OP subnets can't be attached to CLB

Steps:

- Deploy the service

```sh
SVC_NAME_CLB_SB=${APP_NAME}-clb-op-sb
cat << EOF | oc create -f -
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${APP_NAME}
  name: ${SVC_NAME_CLB_SB}
  namespace: ${APP_NAME}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-subnets: ${OutpostPublicSubnetId}
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8081
  selector:
    app: ${APP_NAME}
  type: LoadBalancer
EOF
```

- Test:

```sh
APP_CLB_SB=$(./oc get svc -n ${APP_NAME} ${SVC_NAME_CLB_SB} \
  -o jsonpath={.status.loadBalancer.ingress[0].hostname})

echo "SVC_NAME_CLB_SB=${SVC_NAME_CLB_SB}"
while ! curl $SVC_NAME_CLB_SB; do sleep 5; done
```

Output:
```
$ oc describe svc $SVC_NAME_CLB_SB -n ${APP_NAME} | grep ^Events -A20
Events:
  Type     Reason                  Age    From                Message
  ----     ------                  ----   ----                -------
  Warning  SyncLoadBalancerFailed  4m56s  service-controller  Error syncing load balancer: failed to ensure load balancer: ValidationError: You cannot use Outposts subnets for load balancers of type 'classic'
           status code: 400, request id: 875a7b34-7d34-42e2-88c6-e52c74e85d33
  x4
  Normal   EnsuringLoadBalancer    2m18s (x6 over 4m57s)  service-controller  Ensuring load balancer
  Warning  SyncLoadBalancerFailed  2m17s                  service-controller  Error syncing load balancer: failed to ensure load balancer: ValidationError: You cannot use Outposts subnets for load balancers of type 'classic'
           status code: 400, request id: 936eb787-5d7f-4db0-9572-0b7bdf410674

```


#### Test 3: Service CLB limiting Outposts nodes (unreachable)

Description:

- LB Type: select target instance
- Extra configuration:
    - Annotation:
        - service.beta.kubernetes.io/aws-load-balancer-target-node-labels: location=outpost
- Result: failed
- Reason: Only the Outpost node is attached, although CLB can't reach traffic to the node.

Result: unreachable


Steps:

```sh
SVC_NAME_CLB_NODE=${APP_NAME}-clb-op-node
cat << EOF | oc create -f -
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${APP_NAME}
  name: ${SVC_NAME_CLB_NODE}
  namespace: ${APP_NAME}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-target-node-labels: location=outposts
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8081
  selector:
    app: ${APP_NAME}
  type: LoadBalancer
EOF
```

- Test:

```sh
APP_CLB_NODE=$(./oc get svc -n ${APP_NAME} ${SVC_NAME_CLB_NODE} \
  -o jsonpath={.status.loadBalancer.ingress[0].hostname})

echo "APP_CLB_NODE=${APP_CLB_NODE}"
while ! curl -v $APP_CLB_NODE; do sleep 5; done
```

Output:

```text
$ while ! curl -v $APP_CLB_NODE; do sleep 5; done
*   Trying 54.160.90.21:80...
* Connected to a62e971109b834921851c290a946bcb2-939519935.us-east-1.elb.amazonaws.com (54.160.90.21) port 80 (#0)
> GET / HTTP/1.1
> Host: a62e971109b834921851c290a946bcb2-939519935.us-east-1.elb.amazonaws.com
> User-Agent: curl/8.0.1
> Accept: */*
> 
* Recv failure: Connection reset by peer
* Closing connection 0
curl: (56) Recv failure: Connection reset by peer

```

#### Test 4: Replace default ingress (Service CLB) to NLB

Documentation: [Replacing Ingress Controller Classic Load Balancer with Network Load Balancer](https://docs.openshift.com/container-platform/4.14/networking/configuring_ingress_cluster_traffic/configuring-ingress-cluster-traffic-aws.html#nw-aws-replacing-clb-with-nlb_configuring-ingress-cluster-traffic-aws)

Scenario:
- OP rack is attached to zone A
- subnets on OP with unmanaged tag
- region has subnets on B and C zones

Expected: success w/ NLB on non-OP subnets

Result: Success

Steps:

- Check the existing LB for the default router:

```sh
$ oc get svc router-default -n openshift-ingress
NAME             TYPE           CLUSTER-IP       EXTERNAL-IP                                                              PORT(S)                      AGE
router-default   LoadBalancer   172.30.235.194   ae44f5e3a79b4466f9ecf97854241419-628902116.us-east-1.elb.amazonaws.com   80:32281/TCP,443:32404/TCP   9h
```

- Run the migration step

```sh
cat << EOF |  oc replace --force --wait -f -
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: default
  namespace: openshift-ingress-operator
spec:
  endpointPublishingStrategy:
    loadBalancer:
      scope: External
      providerParameters:
        type: AWS
        aws:
          type: NLB
    type: LoadBalancerService
EOF
```

- Check if the ingress has been replaced

```sh
$ oc get svc router-default -n openshift-ingress
NAME             TYPE           CLUSTER-IP      EXTERNAL-IP                                                                     PORT(S)                      AGE
router-default   LoadBalancer   172.30.87.237   a7824438c657046a1a5f6fa543ffec11-eea19794cae4d69c.elb.us-east-1.amazonaws.com   80:31030/TCP,443:30410/TCP   6m10s
```

- Check the subnets for the NLB ingress:

```sh
ROUTER_NLB_HOSTNAME=$(oc get svc router-default -n openshift-ingress -o jsonpath={.status.loadBalancer.ingress[0].hostname})
aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select(.DNSName==\"${ROUTER_NLB_HOSTNAME}\") | {"Type": .Type, "zones": .AvailabilityZones} "
```

Output

```json
{
  "Type": "network",
  "zones": [
    {
      "ZoneName": "us-east-1b",
      "SubnetId": "subnet-03a8525cc9092d77d",
      "LoadBalancerAddresses": []
    },
    {
      "ZoneName": "us-east-1c",
      "SubnetId": "subnet-0eaefe029bf6c591c",
      "LoadBalancerAddresses": []
    }
  ]
}
```

#### Test 5A: Create Service LB NLB on Outpost clusters

Scenario:
- OP rack is attached to zone A
- subnets on OP with unmanaged tag
- region has subnets on B and C zones
- default subnet discovery

Expected:
- Creation Success
- Failed to connect as the target is not "routable"

Steps:

```sh
SVC_NAME_NLB=${APP_NAME}-nlb
cat << EOF | oc create -f -
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${APP_NAME}
  name: ${SVC_NAME_NLB}
  namespace: ${APP_NAME}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8081
  selector:
    app: ${APP_NAME}
  type: LoadBalancer
EOF
```

- Test:

```sh
APP_NLB=$(oc get svc ${SVC_NAME_NLB} -n ${APP_NAME} -o jsonpath={.status.loadBalancer.ingress[0].hostname})

echo "APP_NLB=${APP_NLB}"
while ! curl $APP_NLB; do sleep 5; done
```

- Check the subnets for the NLB ingress:

```sh
aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select(.DNSName==\"${APP_NLB}\") | {"Type": .Type, "zones": .AvailabilityZones} "
```

Output:
```json
$ aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select(.DNSName==\"${APP_NLB}\") | {"Type": .Type, "zones": .AvailabilityZones} "
{
  "Type": "network",
  "zones": [
    {
      "ZoneName": "us-east-1c",
      "SubnetId": "subnet-0eaefe029bf6c591c",
      "LoadBalancerAddresses": []
    },
    {
      "ZoneName": "us-east-1b",
      "SubnetId": "subnet-03a8525cc9092d77d",
      "LoadBalancerAddresses": []
    }
  ]
}
```

#### Test 5B: Create Service LB with NLB on Outpost

Scenario:
- OP rack is attached to zone A
- subnets on OP with unmanaged tag
- region has subnets on B and C zones
- annotate OP subnet

Expected: Fail to create an unsupported type on OP

Result: Fail to create an unsupported type on OP

Steps:

```sh
SVC_NAME_NLB_OP=${APP_NAME}-nlb-op
cat << EOF | oc create -f -
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${APP_NAME}
  name: ${SVC_NAME_NLB_OP}
  namespace: ${APP_NAME}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-subnets: ${OutpostPublicSubnetId}
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8081
  selector:
    app: ${APP_NAME}
  type: LoadBalancer
EOF
```

- Validation error:

```sh
$ oc describe svc ${SVC_NAME_NLB_OP} -n ${APP_NAME}  | tail -n1
  Warning  SyncLoadBalancerFailed  18s                service-controller  Error syncing load balancer: failed to ensure load balancer: error creating load balancer: "ValidationError: You cannot use Outposts subnets for load balancers of type 'network'\n\tstatus code: 400, request id: facb472e-2455-4608-b108-0d17dc925397"
```


## Destroy the cluster


- Delete the Outpost machine set:

```sh
oc delete machineset -n openshift-machine-api -l location=outpost
```

- Delete the CloudFormation stack for subnet:

```sh
aws cloudformation delete-stack --stack-name ${STACK_NAME}
```

- Delete cluster:

```sh
./openshift-install destroy cluster --log-level debug
```

## References

- [AWS Doc: What is AWS Outposts?](https://docs.aws.amazon.com/outposts/latest/userguide/what-is-outposts.html)
- [AWS Doc: How AWS Outposts works](https://docs.aws.amazon.com/outposts/latest/userguide/how-outposts-works.html)
- [AWS Blog: Configuring an Application Load Balancer on AWS Outposts](https://aws.amazon.com/blogs/networking-and-content-delivery/configuring-an-application-load-balancer-on-aws-outposts/)
- [AWS Doc Outposts: Customer-owned IP addresses](https://docs.aws.amazon.com/outposts/latest/userguide/routing.html#ip-addressing)