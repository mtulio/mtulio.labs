# Installing OpenShift on AWS extending worker node to AWS Outposts, and an standalone EC2

Lab steps to install an OpenShift cluster on AWS, extending compute node to AWS Outposts as Day 2 operations.

The lab also deploy an standalone EC2 instance, which can be used to a router (haproxy, etc) - not covered by this document.

Total time running this lab: ~120 minutes (install, setup, test, destroy).

## Install OpenShift

- Export the AWS credentials

```sh
export AWS_DEFAULT_REGION=us-east-1
export AWS_PROFILE=outposts
```

- Install OpenShift cluster

```sh
VERSION="4.17.5"
PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64
CLUSTER_NAME=bclb
INSTALL_DIR=${HOME}/openshift-labs/outposts/${CLUSTER_NAME}
CLUSTER_BASE_DOMAIN=outposts-lab.devcluster.openshift.com
SSH_PUB_KEY_FILE=$INSTALL_DIR/id_rsa.pub
REGION=us-east-1
AWS_REGION=${REGION}

mkdir -p $INSTALL_DIR && cd $INSTALL_DIR
test -f ${SSH_PUB_KEY_FILE} || ssh-keygen -t rsa -b 4096  -f $INSTALL_DIR/id_rsa
```

- Extract clients:

```sh
oc adm release extract \
    --tools quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64 \
    -a ${PULL_SECRET_FILE}

tar xvfz openshift-client-linux-${VERSION}.tar.gz
tar xvfz openshift-install-linux-${VERSION}.tar.gz
```

- Install config: Limiting only for zones not attached to the Outpost rack (use1a)

```sh
echo "> Creating install-config.yaml"
# Create a single-AZ install config
mkdir -p ${INSTALL_DIR}
cat <<EOF | envsubst > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${CLUSTER_BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
networking:
  clusterNetworkMTU: 1200
platform:
  aws:
    region: ${REGION}
    userTags:
      customer: REDACTED
      requestedBy: men...za
    defaultMachinePlatform:
      zones:
      - us-east-1a
      - us-east-1b
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

echo ">> install-config.yaml created: "
cp -v ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config.yaml-bkp

./openshift-install create cluster --dir ${INSTALL_DIR} --log-level=debug

export KUBECONFIG=$PWD/auth/kubeconfig
```

## Extending an AWS VPC cluster into an AWS Outposts

> Based in official OpenShift documentation: https://docs.openshift.com/container-platform/4.17/installing/installing_aws/ipi/installing-aws-outposts.html

These steps modify the existing CloudFormation template available in the installer repository to create VPC subnets, especially in Wavelength or Local Zones.

The template is modified to receive the parameter to support AWS Outpost instance ARN.


### Prerequisites

#### Export required variables

Steps based in OCP user documentation:
  - https://docs.openshift.com/container-platform/4.17/installing/installing_aws/ipi/installing-aws-outposts.html
  - https://docs.openshift.com/container-platform/4.17/installing/installing_aws/ipi/installing-aws-outposts.html#installation-creating-aws-vpc-subnets-edge_installing-aws-outposts

Exporting required variables:

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
```

- Export the private route table IDs (4.16 only):

```sh
# Public route table for parent zone
PublicRouteTableId=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VpcId \
    | jq -r '.RouteTables[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .RouteTableId }]' \
    | jq -r ".[]  | select(.Name | contains(\"public-${OutpostAvailabilityZone}\")).Id")

# Private route table for the parent zone - using NAT Gateway from parent zone to egress traffic from Outpost nodes to internet
PrivateRouteTableId=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VpcId \
    | jq -r '.RouteTables[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .RouteTableId }]' \
    | jq -r ".[]  | select(.Name | contains(\"private-${OutpostAvailabilityZone}\")).Id")
```

- Export the CIDR blocks for subnets by discovering next CIDR available to create /24 subnets:

```sh
# 1. When the last subnet CIDR is 10.0.192.0/20, it will return 208 (207+1, where 207 is the last 3rd octet of the network)
# 2. Create /24 subnets
NextFreeNet="`echo "$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VpcId \
  | jq  -r ".Subnets[].CidrBlock" \
  | sort -t . -k 3,3n -k 4,4n | tail -n1 \
  | xargs ipcalc | grep ^HostMax \
  | awk '{print$2}' | awk -F'.' '{print$3}') + 1" | bc `"

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


#### Create Cloudformation template:

> TODO: download from Installer when the field `OutpostArn` is available from [UPI Templates for subnet](https://raw.githubusercontent.com/openshift/installer/master/upi/aws/cloudformation/01_vpc_99_subnet.yaml)

- Create the template:

```sh
TEMPLATE_NAME=./cfn-subnet-outposts.yaml
cat <<EOF > ${TEMPLATE_NAME}
AWSTemplateFormatVersion: 2010-09-09
Description: Template for Best Practice Subnets (Public and Private) on Outposts

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

### Create CloudFormation subnet stack

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
OutpostPublicSubnetId=$(aws ec2 describe-subnets \
  --filters Name=outpost-arn,Values=${OutpostArn} Name=vpc-id,Values=$VpcId \
  | jq -r '.Subnets[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .SubnetId }]' \
  | jq -r '.[] | select(.Name | contains("public")).Id')

OutpostPrivateSubnetId=$(aws ec2 describe-subnets \
  --filters Name=outpost-arn,Values=${OutpostArn} Name=vpc-id,Values=$VpcId \
  | jq -r '.Subnets[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .SubnetId }]' \
  | jq -r '.[] | select(.Name | contains("private")).Id')
```

## Create MachineSet manifest for Outpost node

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

- Retrieve the MachineSet and merge it into yours

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

## Deploy EC2 instance to HA Proxy

### Create CloudFormation Stack template

```sh

cat << EOF > ./stack_ocp-node_haproxy-public.yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Deploy EC2 Instance.

Parameters:
  NamePrefix:
    AllowedPattern: ^([a-zA-Z][a-zA-Z0-9\-]{0,26})$
    MaxLength: 24
    MinLength: 1
    ConstraintDescription: Cluster name must be alphanumeric, start with a letter, and have a maximum of 27 characters.
    Description: A short, representative cluster name to use for host names and other identifying names.
    Type: String

  VpcId:
    Description: VPC ID to associate the Carrier Gateway.
    Type: String
    AllowedPattern: ^(?:(?:vpc)(?:-[a-zA-Z0-9]+)?\b|(?:[0-9]{1,3}\.){3}[0-9]{1,3})$
    ConstraintDescription: VPC ID must be with valid name, starting with vpc-.*.

  VpcCidr:
    AllowedPattern: ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(1[6-9]|2[0-4]))$
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/16-24.
    Default: 10.0.0.0/16
    Description: CIDR block for VPC.
    Type: String

  AmiId:
    Description: AMI ID to provision the EC2.
    Type: String
    AllowedPattern: ^(?:(?:ami)(?:-[a-zA-Z0-9]+)?\b|(?:[0-9]{1,3}\.){3}[0-9]{1,3})$
    ConstraintDescription: Subnet ID must be with valid name, starting with ami-.*.

  SubnetId:
    Description: Base64 user data to provision the EC2.
    Type: String

  InstanceType:
    Default: "m6i.large"
    Description: Base64 user data to provision the EC2.
    Type: String

  KeyName:
    Default: "openshift-dev"
    Description: Base64 user data to provision the EC2.
    Type: String

  UserData:
    Description: Base64 user data to provision the EC2.
    Type: String

  IsPublic:
    Description: Base64 user data to provision the EC2.
    Type: String
    Default: "False"
    AllowedValues: ["True", "False"]

Resources:
  #
  # EC2 Deployment
  #
  IamRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
        - Effect: "Allow"
          Principal:
            Service:
            - "ec2.amazonaws.com"
          Action:
          - "sts:AssumeRole"
      Path: "/"

  IAMPolicy:
    Type: 'AWS::IAM::Policy'
    Properties:
      PolicyName: !Join ["-", [!Ref NamePrefix, "haproxy"]]
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
        - Effect: "Allow"
          Action: "s3:Get*"
          Resource: "*"
      Roles:
      - !Ref 'IamRole'

  InstanceProfile:
    Type: "AWS::IAM::InstanceProfile"
    Properties:
      Path: "/"
      Roles:
      - !Ref IamRole

  SecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: !Join ['', ["Security Group for ", "haproxy host"]]
      SecurityGroupIngress:
      - IpProtocol: "tcp"
        FromPort: 22
        ToPort: 22
        CidrIp: "0.0.0.0/0"
      - IpProtocol: "tcp"
        FromPort: 80
        ToPort: 80
        CidrIp: "0.0.0.0/0"
      - IpProtocol: "tcp"
        FromPort: 443
        ToPort: 443
        CidrIp: "0.0.0.0/0"
      SecurityGroupEgress:
      - IpProtocol: "-1"
        CidrIp: "10.0.0.0/16"
      VpcId: !Ref VpcId
      Tags:
      - Key: Name
        Value: !Join ['', [!Ref NamePrefix, "-haproxy-sg"]]

  Instance:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: !Ref AmiId
      IamInstanceProfile: !Ref InstanceProfile
      InstanceType: !Ref InstanceType
      BlockDeviceMappings: 
      - DeviceName: "/dev/xvda"
        Ebs: 
          VolumeType: "gp2"
          DeleteOnTermination: "true"
          VolumeSize: "32"
      NetworkInterfaces:
      - AssociatePublicIpAddress: !Ref IsPublic
        DeviceIndex: "0"
        GroupSet:
        - !Ref 'SecurityGroup'
        SubnetId: !Ref "SubnetId"
      #SecurityGroupIds: 
      #- !Ref "SecurityGroupId"
      #SubnetId: !Ref "SubnetId"
      UserData: !Ref UserData
      Tags:
      - Key: Name
        Value: !Join ['', [!Ref NamePrefix, '-haproxy']]

Outputs:
  InstanceId:
    Description: Instance ID.
    Value: !Ref 'Instance'
  PrivateIp:
    Description: Private IP.
    Value: !GetAtt 'Instance.PrivateIp'
EOF

```

### Create ignition

```sh
cat << EOF > ./ec2.ign
{
  "ignition": {
    "version": "3.0.0"
  },
  "passwd": {
    "users": [
      {
        "name": "core",
        "sshAuthorizedKeys": [
          "$(cat ${SSH_PUB_KEY_FILE})"
        ]
      }
    ]
  }
}
EOF
```

```sh
curl -L -o ./fcos.json https://builds.coreos.fedoraproject.org/streams/stable.json

export HAPROXY_AMI_ID=$(jq -r .architectures.x86_64.images.aws.regions[\"${AWS_REGION}\"].image < ./fcos.json)
export HAPROXY_USER_DATA=$(base64 -w0 <(<./ec2.ign))

export HAPROXY_STACK_NAME="${CLUSTER_NAME}-haproxy3"
aws cloudformation create-stack --stack-name ${HAPROXY_STACK_NAME} \
    --region ${AWS_REGION} \
    --template-body file://./stack_ocp-node_haproxy-public.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
    ParameterKey=VpcId,ParameterValue=${VpcId} \
    ParameterKey=NamePrefix,ParameterValue=${CLUSTER_NAME} \
    ParameterKey=AmiId,ParameterValue=${HAPROXY_AMI_ID} \
    ParameterKey=UserData,ParameterValue=${HAPROXY_USER_DATA} \
    ParameterKey=SubnetId,ParameterValue=${OutpostPublicSubnetId} \
    ParameterKey=InstanceType,ParameterValue=m5.large \
    ParameterKey=IsPublic,ParameterValue="True"

aws cloudformation wait stack-create-complete --stack-name ${HAPROXY_STACK_NAME}

aws cloudformation describe-stacks --stack-name ${HAPROXY_STACK_NAME}


```

## Deploy Sample app exposing NodePort on Outpost node


```sh
APP_NAME=sample-outpost
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

---
apiVersion: v1
kind: Service 
metadata:
  name:  ${APP_NAME}-svc
  namespace: ${APP_NAME}
spec:
  ports:
    - port: 8080
      nodePort: 30080
      protocol: TCP
  type: NodePort
  selector: 
    app: ${APP_NAME}
EOF

oc create -f ./outpost-app.yaml
```

## Destroy the cluster


- Delete the Outpost machine set:

```sh
oc delete machineset -n openshift-machine-api -l location=outpost
```

- Delete the CloudFormation stack for EC2:

```sh
aws cloudformation delete-stack --stack-name ${HAPROXY_STACK_NAME}
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
\


## Follow ups

- OCP document steps could advise a user to install a cluster with custom MTU, day 0, by setting the `networking.clusterNetworkMTU=1200` on instlal-config.yaml
