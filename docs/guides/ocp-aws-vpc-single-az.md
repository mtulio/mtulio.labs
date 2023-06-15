# Installing an OCP cluster in AWS in existing VPC with single-zone

> WIP/PR open for comment: https://github.com/mtulio/mtulio.labs/pull/24

Steps to reproduce an issue where the AWS cloud provider implementation (in-tree) is always discovering all subnets in a VPC when installing an OCP cluster in existing subnets in a single zone.

The steps described in the first section describe how to create the VPC using the CloudFormation template (used in the OCP docs), then create three clusters in each zone. The cloud provider is creating the LB for ingress/default router in all subnets, not respecting the install-config.yaml as the LB is created without any information to filter the subnets, although, when the subnets already have the cluster tags, the controller will ignore that subnet.

Section 2 describes how to workaround, proposing a new CloudFormation to create the VPC tagging with a fake cluster tag `kubernetes.io/cluster/unmanaged=shared`, to prevent the subnet discovery to assign the subnets to the Load Balancer.

## Section 1. Reproducing the issue

### Prerequisites

Create VPC:

- Create the CloudFormation Template

```bash
cat << EOF > template-vpc.yaml
AWSTemplateFormatVersion: 2010-09-09
Description: Template for Best Practice VPC with 1-3 AZs

Parameters:
  ClusterName:
    Type: String
    Description: ClusterName used to prefix resource names
  VpcCidr:
    AllowedPattern: ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(1[6-9]|2[0-4]))$
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/16-24.
    Default: 10.0.0.0/16
    Description: CIDR block for VPC.
    Type: String
  AvailabilityZoneCount:
    ConstraintDescription: "The number of availability zones. (Min: 1, Max: 3)"
    MinValue: 1
    MaxValue: 3
    Default: 1
    Description: "How many AZs to create VPC subnets for. (Min: 1, Max: 3)"
    Type: Number
  SubnetBits:
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/19-27.
    MinValue: 5
    MaxValue: 13
    Default: 12
    Description: "Size of each subnet to create within the availability zones. (Min: 5 = /27, Max: 13 = /19)"
    Type: Number

Metadata:
  AWS::CloudFormation::Interface:
    ParameterGroups:
    - Label:
        default: "Network Configuration"
      Parameters:
      - VpcCidr
      - SubnetBits
    - Label:
        default: "Availability Zones"
      Parameters:
      - AvailabilityZoneCount
    ParameterLabels:
      ClusterName:
        default: ""
      AvailabilityZoneCount:
        default: "Availability Zone Count"
      VpcCidr:
        default: "VPC CIDR"
      SubnetBits:
        default: "Bits Per Subnet"

Conditions:
  DoAz3: !Equals [3, !Ref AvailabilityZoneCount]
  DoAz2: !Or [!Equals [2, !Ref AvailabilityZoneCount], Condition: DoAz3]

Resources:
  VPC:
    Type: "AWS::EC2::VPC"
    Properties:
      EnableDnsSupport: "true"
      EnableDnsHostnames: "true"
      CidrBlock: !Ref VpcCidr
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-vpc" ] ]
      - Key: !Join [ "", [ "kubernetes.io/cluster/unmanaged" ] ]
        Value: "shared"

  PublicSubnet:
    Type: "AWS::EC2::Subnet"
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [0, !Cidr [!Ref VpcCidr, 6, !Ref SubnetBits]]
      AvailabilityZone: !Select
      - 0
      - Fn::GetAZs: !Ref "AWS::Region"
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-public-1" ] ]
  PublicSubnet2:
    Type: "AWS::EC2::Subnet"
    Condition: DoAz2
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [1, !Cidr [!Ref VpcCidr, 6, !Ref SubnetBits]]
      AvailabilityZone: !Select
      - 1
      - Fn::GetAZs: !Ref "AWS::Region"
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-public-2" ] ]
  PublicSubnet3:
    Type: "AWS::EC2::Subnet"
    Condition: DoAz3
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [2, !Cidr [!Ref VpcCidr, 6, !Ref SubnetBits]]
      AvailabilityZone: !Select
        - 2
        - Fn::GetAZs: !Ref "AWS::Region"
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-public-3" ] ]

  InternetGateway:
    Type: "AWS::EC2::InternetGateway"
    Properties:
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-igw" ] ]
  GatewayToInternet:
    Type: "AWS::EC2::VPCGatewayAttachment"
    Properties:
      VpcId: !Ref VPC
      InternetGatewayId: !Ref InternetGateway

  PublicRouteTable:
    Type: "AWS::EC2::RouteTable"
    Properties:
      VpcId: !Ref VPC
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-rtb-public" ] ]
  PublicRoute:
    Type: "AWS::EC2::Route"
    DependsOn: GatewayToInternet
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway
  PublicSubnetRouteTableAssociation:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Properties:
      SubnetId: !Ref PublicSubnet
      RouteTableId: !Ref PublicRouteTable
  PublicSubnetRouteTableAssociation2:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Properties:
      SubnetId: !Ref PublicSubnet2
      RouteTableId: !Ref PublicRouteTable
  PublicSubnetRouteTableAssociation3:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Properties:
      SubnetId: !Ref PublicSubnet3
      RouteTableId: !Ref PublicRouteTable

  PrivateSubnet:
    Type: "AWS::EC2::Subnet"
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [3, !Cidr [!Ref VpcCidr, 6, !Ref SubnetBits]]
      AvailabilityZone: !Select
      - 0
      - Fn::GetAZs: !Ref "AWS::Region"
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-private-1" ] ]
  PrivateRouteTable:
    Type: "AWS::EC2::RouteTable"
    Properties:
      VpcId: !Ref VPC
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-rtb-private-1" ] ]
  PrivateSubnetRouteTableAssociation:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Properties:
      SubnetId: !Ref PrivateSubnet
      RouteTableId: !Ref PrivateRouteTable
  NAT:
    DependsOn:
    - GatewayToInternet
    Type: "AWS::EC2::NatGateway"
    Properties:
      AllocationId:
        "Fn::GetAtt":
        - EIP
        - AllocationId
      SubnetId: !Ref PublicSubnet
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-natgw-private-1" ] ]
  EIP:
    Type: "AWS::EC2::EIP"
    Properties:
      Domain: vpc
  Route:
    Type: "AWS::EC2::Route"
    Properties:
      RouteTableId:
        Ref: PrivateRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId:
        Ref: NAT

  PrivateSubnet2:
    Type: "AWS::EC2::Subnet"
    Condition: DoAz2
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [4, !Cidr [!Ref VpcCidr, 6, !Ref SubnetBits]]
      AvailabilityZone: !Select
      - 1
      - Fn::GetAZs: !Ref "AWS::Region"
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-private-2" ] ]
  PrivateRouteTable2:
    Type: "AWS::EC2::RouteTable"
    Condition: DoAz2
    Properties:
      VpcId: !Ref VPC
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-rtb-private-2" ] ]
  PrivateSubnetRouteTableAssociation2:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Condition: DoAz2
    Properties:
      SubnetId: !Ref PrivateSubnet2
      RouteTableId: !Ref PrivateRouteTable2
  NAT2:
    DependsOn:
    - GatewayToInternet
    Type: "AWS::EC2::NatGateway"
    Condition: DoAz2
    Properties:
      AllocationId:
        "Fn::GetAtt":
        - EIP2
        - AllocationId
      SubnetId: !Ref PublicSubnet2
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-natgw-private-2" ] ]
  EIP2:
    Type: "AWS::EC2::EIP"
    Condition: DoAz2
    Properties:
      Domain: vpc
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-eip-private-2" ] ]
  Route2:
    Type: "AWS::EC2::Route"
    Condition: DoAz2
    Properties:
      RouteTableId:
        Ref: PrivateRouteTable2
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId:
        Ref: NAT2

  PrivateSubnet3:
    Type: "AWS::EC2::Subnet"
    Condition: DoAz3
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [5, !Cidr [!Ref VpcCidr, 6, !Ref SubnetBits]]
      AvailabilityZone: !Select
      - 2
      - Fn::GetAZs: !Ref "AWS::Region"
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-private-3" ] ]
  PrivateRouteTable3:
    Type: "AWS::EC2::RouteTable"
    Condition: DoAz3
    Properties:
      VpcId: !Ref VPC
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-rtb-private-3" ] ]
  PrivateSubnetRouteTableAssociation3:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Condition: DoAz3
    Properties:
      SubnetId: !Ref PrivateSubnet3
      RouteTableId: !Ref PrivateRouteTable3
  NAT3:
    DependsOn:
    - GatewayToInternet
    Type: "AWS::EC2::NatGateway"
    Condition: DoAz3
    Properties:
      AllocationId:
        "Fn::GetAtt":
        - EIP3
        - AllocationId
      SubnetId: !Ref PublicSubnet3
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-natgw-private-3" ] ]
  EIP3:
    Type: "AWS::EC2::EIP"
    Condition: DoAz3
    Properties:
      Domain: vpc
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-eip-private-3" ] ]
  Route3:
    Type: "AWS::EC2::Route"
    Condition: DoAz3
    Properties:
      RouteTableId:
        Ref: PrivateRouteTable3
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId:
        Ref: NAT3

  S3Endpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      PolicyDocument:
        Version: 2012-10-17
        Statement:
        - Effect: Allow
          Principal: '*'
          Action:
          - '*'
          Resource:
          - '*'
      RouteTableIds:
      - !Ref PublicRouteTable
      - !Ref PrivateRouteTable
      - !If [DoAz2, !Ref PrivateRouteTable2, !Ref "AWS::NoValue"]
      - !If [DoAz3, !Ref PrivateRouteTable3, !Ref "AWS::NoValue"]
      ServiceName: !Join
      - ''
      - - com.amazonaws.
        - !Ref 'AWS::Region'
        - .s3
      VpcId: !Ref VPC

Outputs:
  VpcId:
    Description: ID of the new VPC.
    Value: !Ref VPC
  PublicSubnetIds:
    Description: Subnet IDs of the public subnets.
    Value:
      !Join [
        ",",
        [!Ref PublicSubnet, !If [DoAz2, !Ref PublicSubnet2, !Ref "AWS::NoValue"], !If [DoAz3, !Ref PublicSubnet3, !Ref "AWS::NoValue"]]
      ]
  PrivateSubnetIds:
    Description: Subnet IDs of the private subnets.
    Value:
      !Join [
        ",",
        [!Ref PrivateSubnet, !If [DoAz2, !Ref PrivateSubnet2, !Ref "AWS::NoValue"], !If [DoAz3, !Ref PrivateSubnet3, !Ref "AWS::NoValue"]]
      ]
  PublicRouteTableId:
    Description: Public Route table ID
    Value: !Ref PublicRouteTable
  PrivateRouteTableIds:
    Description: Private Route table ID
    Value:
      !Join [
        ",",
        [!Ref PrivateRouteTable, !If [DoAz2, !Ref PrivateRouteTable2, !Ref "AWS::NoValue"], !If [DoAz3, !Ref PrivateRouteTable3, !Ref "AWS::NoValue"]]
      ]
EOF
```

- Create VPC

```bash
export CLUSTER_REGION=us-east-1
export VPC_NAME=byonet-use1

export STACK_VPC=${VPC_NAME}-vpc
aws cloudformation create-stack \
  --region ${CLUSTER_REGION} \
  --stack-name ${STACK_VPC} \
  --template-body file://template-vpc.yaml \
  --parameters \
      ParameterKey=ClusterName,ParameterValue=${VPC_NAME} \
      ParameterKey=VpcCidr,ParameterValue="10.0.0.0/16" \
      ParameterKey=AvailabilityZoneCount,ParameterValue=3 \
      ParameterKey=SubnetBits,ParameterValue=12

aws --region ${CLUSTER_REGION} cloudformation wait stack-create-complete --stack-name ${STACK_VPC}
aws --region ${CLUSTER_REGION} cloudformation describe-stacks --stack-name ${STACK_VPC}
```

- Export Subnet and VPC ID

```bash
mapfile -t PRIVATE_SUBNETS < <(aws --region ${CLUSTER_REGION} \
  cloudformation describe-stacks --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[0].OutputValue' | tr ',' '\n')

mapfile -t PUBLIC_SUBNETS < <(aws --region ${CLUSTER_REGION} \
  cloudformation describe-stacks --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[1].OutputValue' | tr ',' '\n')

export VPC_ID=$(aws --region ${CLUSTER_REGION} \
  cloudformation describe-stacks --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[2].OutputValue')
```

- Check the tags for each subnet in the VPC:

```bash
$ aws ec2 describe-subnets --filter Name=vpc-id,Values=$VPC_ID | jq -r '.Subnets[] | [.AvailabilityZone, .SubnetId, [ .Tags[] | select(.Key | contains("aws:") | not) ] ] '
[
  "us-east-1c",
  "subnet-0ef652f1be3095813",
  [
    {
      "Key": "Name",
      "Value": "byonet-use1-private-3"
    }
  ]
]
[
  "us-east-1a",
  "subnet-03d8721dd76527772",
  [
    {
      "Key": "Name",
      "Value": "byonet-use1-public-1"
    }
  ]
]
[
  "us-east-1c",
  "subnet-058247e779d805066",
  [
    {
      "Key": "Name",
      "Value": "byonet-use1-public-3"
    }
  ]
]
[
  "us-east-1b",
  "subnet-034e4acc93f527772",
  [
    {
      "Key": "Name",
      "Value": "byonet-use1-public-2"
    }
  ]
]
[
  "us-east-1b",
  "subnet-0d39a85a25fc55f3b",
  [
    {
      "Key": "Name",
      "Value": "byonet-use1-private-2"
    }
  ]
]
[
  "us-east-1a",
  "subnet-00accc137becba0b2",
  [
    {
      "Key": "Name",
      "Value": "byonet-use1-private-1"
    }
  ]
]
```

Download the installer:

```bash
VERSION="4.13.3"
PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
echo ">> Download Clients..."
oc adm release extract \
    --tools quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64 \
    -a ${PULL_SECRET_FILE}

tar xvfz openshift-client-linux-${VERSION}.tar.gz
tar xvfz openshift-install-linux-${VERSION}.tar.gz
```

## Scenario 01: Single zone without LB labels (only cluster labels)

- VPC with 6 subnets (public and private) into 3 zones
- OCP Cluster installed in a single zone
- Ingress controller manifest for NLB created in install time (replacing the default CLB).

### Expected results:

- OpenShift installer creates the API NLB into single-zone
- Load Balancer controller (cloud provider) assign only the subnet used by the installer, respecting the cluster tags used in [the discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.2/deploy/subnet_discovery/), preventing to add all subnets to the load balancer created by the service (in this case the default router).

### Steps:

- Export Subnet and VPC ID

```bash
export PUBLIC_SUBNET_ID=${PUBLIC_SUBNETS[0]}
export PRIVATE_SUBNET_ID=${PRIVATE_SUBNETS[0]}
```

- Check if subnets must be part of the same AZ:

```bash
$ aws ec2 describe-subnets --subnet-ids ${PUBLIC_SUBNET_ID} ${PRIVATE_SUBNET_ID} | jq -r '.Subnets[] | [.AvailabilityZone, .CidrBlock, .SubnetId, .VpcId]'
[
  "us-east-1a",
  "10.0.0.0/20",
  "subnet-03d8721dd76527772",
  "vpc-09e41ea29d3f0b22d"
]
[
  "us-east-1a",
  "10.0.48.0/20",
  "subnet-00accc137becba0b2",
  "vpc-09e41ea29d3f0b22d"
]
```

- Get Zone Name

```bash
export ZONE_NAME=$(aws ec2 describe-subnets --filter --subnet-ids ${PUBLIC_SUBNET_ID} ${PRIVATE_SUBNET_ID} | jq -r '.Subnets[0].AvailabilityZone')
```

- Create install-config

```bash
export CLUSTER_NAME=${VPC_NAME}a
export BASE_DOMAIN=devcluster.openshift.com
export SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

INSTALL_DIR=${CLUSTER_NAME}
mkdir $INSTALL_DIR

cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: ${BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${CLUSTER_REGION}
    subnets:
    - ${PUBLIC_SUBNET_ID}
    - ${PRIVATE_SUBNET_ID}
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
```

- Check install-config.yaml

```bash
$ grep -vE '(^pull|ssh)' ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: devcluster.openshift.com
metadata:
  name: "byonet-use1a"
platform:
  aws:
    region: us-east-1
    subnets:
    - subnet-00accc137becba0b2
    - subnet-03d8721dd76527772
```

- Create manifests

```bash
./openshift-install create manifests --dir $INSTALL_DIR
```

- Check processed manifests

```bash
$ grep $CLUSTER_REGION $INSTALL_DIR/openshift/*.yaml
byonet-use1a/openshift/99_openshift-cluster-api_master-machines-0.yaml:        availabilityZone: us-east-1a
byonet-use1a/openshift/99_openshift-cluster-api_master-machines-0.yaml:        region: us-east-1
byonet-use1a/openshift/99_openshift-cluster-api_master-machines-1.yaml:        availabilityZone: us-east-1a
byonet-use1a/openshift/99_openshift-cluster-api_master-machines-1.yaml:        region: us-east-1
byonet-use1a/openshift/99_openshift-cluster-api_master-machines-2.yaml:        availabilityZone: us-east-1a
byonet-use1a/openshift/99_openshift-cluster-api_master-machines-2.yaml:        region: us-east-1
byonet-use1a/openshift/99_openshift-cluster-api_worker-machineset-0.yaml:  name: byonet-use1a-4n424-worker-us-east-1a
byonet-use1a/openshift/99_openshift-cluster-api_worker-machineset-0.yaml:      machine.openshift.io/cluster-api-machineset: byonet-use1a-4n424-worker-us-east-1a
byonet-use1a/openshift/99_openshift-cluster-api_worker-machineset-0.yaml:        machine.openshift.io/cluster-api-machineset: byonet-use1a-4n424-worker-us-east-1a
byonet-use1a/openshift/99_openshift-cluster-api_worker-machineset-0.yaml:            availabilityZone: us-east-1a
byonet-use1a/openshift/99_openshift-cluster-api_worker-machineset-0.yaml:            region: us-east-1
byonet-use1a/openshift/99_openshift-machine-api_master-control-plane-machine-set.yaml:            availabilityZone: us-east-1a
byonet-use1a/openshift/99_openshift-machine-api_master-control-plane-machine-set.yaml:              region: us-east-1
```

- Create NLB manifest for ingress with single subnet annotation:

```bash
cat <<EOF > ${INSTALL_DIR}/manifests/cluster-ingress-default-ingresscontroller.yaml
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

- Create cluster

```bash
$ ./openshift-install create cluster --dir $INSTALL_DIR

$ tail -n 8 $INSTALL_DIR/.openshift_install.log
time="2023-06-14T18:57:34-03:00" level=debug msg="Time elapsed per stage:"
time="2023-06-14T18:57:34-03:00" level=debug msg="           cluster: 3m47s"
time="2023-06-14T18:57:34-03:00" level=debug msg="         bootstrap: 43s"
time="2023-06-14T18:57:34-03:00" level=debug msg="Bootstrap Complete: 12m35s"
time="2023-06-14T18:57:34-03:00" level=debug msg="               API: 1m17s"
time="2023-06-14T18:57:34-03:00" level=debug msg=" Bootstrap Destroy: 40s"
time="2023-06-14T18:57:34-03:00" level=debug msg=" Cluster Operators: 8m35s"
time="2023-06-14T18:57:34-03:00" level=info msg="Time elapsed: 27m6s"

```

- Check cluster

```bash
export KUBECONFIG=$INSTALL_DIR/auth/kubeconfig
oc get co

$ oc get machines -n openshift-machine-api
NAME                                         PHASE     TYPE         REGION      ZONE         AGE
byonet-use1a-4n424-master-0                  Running   m6i.xlarge   us-east-1   us-east-1a   68m
byonet-use1a-4n424-master-1                  Running   m6i.xlarge   us-east-1   us-east-1a   68m
byonet-use1a-4n424-master-2                  Running   m6i.xlarge   us-east-1   us-east-1a   68m
byonet-use1a-4n424-worker-us-east-1a-cn9tr   Running   m6i.xlarge   us-east-1   us-east-1a   63m
byonet-use1a-4n424-worker-us-east-1a-hv78c   Running   m6i.xlarge   us-east-1   us-east-1a   63m
byonet-use1a-4n424-worker-us-east-1a-kns9b   Running   m6i.xlarge   us-east-1   us-east-1a   63m

```

- Check the subnet tags after the cluster install, expected only the subnet in the zone us-east-1a to be tagged by the installer:

> removing manually the `tag:Name=openshift_creationDate`

```bash
$ aws ec2 describe-subnets --filter Name=vpc-id,Values=$VPC_ID | jq -r '.Subnets[] | [.AvailabilityZone, .SubnetId, [ .Tags[] | select(.Key | contains("aws:cloudformation") | not) ] ] '
[
  "us-east-1c",
  "subnet-0ef652f1be3095813",
  [
    {
      "Key": "Name",
      "Value": "byonet-use1-private-3"
    }
  ]
]
[
  "us-east-1a",
  "subnet-03d8721dd76527772",
  [
    {
      "Key": "Name",
      "Value": "byonet-use1-public-1"
    },
    {
      "Key": "kubernetes.io/cluster/byonet-use1a-4n424",
      "Value": "shared"
    }
  ]
]
[
  "us-east-1c",
  "subnet-058247e779d805066",
  [
    {
      "Key": "Name",
      "Value": "byonet-use1-public-3"
    }
  ]
]
[
  "us-east-1b",
  "subnet-034e4acc93f527772",
  [
    {
      "Key": "Name",
      "Value": "byonet-use1-public-2"
    }
  ]
]
[
  "us-east-1b",
  "subnet-0d39a85a25fc55f3b",
  [
    {
      "Key": "Name",
      "Value": "byonet-use1-private-2"
    }
  ]
]
[
  "us-east-1a",
  "subnet-00accc137becba0b2",
  [
    {
      "Key": "kubernetes.io/cluster/byonet-use1a-4n424",
      "Value": "shared"
    },
    {
      "Key": "Name",
      "Value": "byonet-use1-private-1"
    }
  ]
]

```

- Check the VPC tags:

```bash
$ aws ec2 describe-vpcs --filter Name=vpc-id,Values=$VPC_ID | jq -r '.Vpcs[] | [.VpcId , [ .Tags[] | select(.Key | contains("aws:cloudformation") | not) ] ] '
[
  "vpc-09e41ea29d3f0b22d",
  [
    {
      "Key": "openshift_creationDate",
      "Value": "2023-06-14T21:08:07.327545+00:00"
    },
    {
      "Key": "Name",
      "Value": "byonet-use1-vpc"
    },
    {
      "Key": "kubernetes.io/cluster/unmanaged",
      "Value": "shared"
    }
  ]
]

```

- Check the subnets attached to the router's service/NLB:

```bash
ROUTER_LB_HOSTNAME=$(oc get svc -n openshift-ingress -o json | jq -r '.items[] | select (.spec.type=="LoadBalancer").status.loadBalancer.ingress[0].hostname')

aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select (.DNSName==\"${ROUTER_LB_HOSTNAME}\") | [.DNSName, .AvailabilityZones]"
[
  "ac4c2574bdd6a41b5b13655cf4df678a-b5d2ea662f04c448.elb.us-east-1.amazonaws.com",
  [
    {
      "ZoneName": "us-east-1a",
      "SubnetId": "subnet-03d8721dd76527772",
      "LoadBalancerAddresses": []
    },
    {
      "ZoneName": "us-east-1b",
      "SubnetId": "subnet-034e4acc93f527772",
      "LoadBalancerAddresses": []
    },
    {
      "ZoneName": "us-east-1c",
      "SubnetId": "subnet-058247e779d805066",
      "LoadBalancerAddresses": []
    }
  ]
]
```

### Actual results:

- Installer created the NLB into the single zone/subnet
- Service load balancer discovered all subnets in the VPC


## Scenario 02: Install in zone 1b with LB tags

LB tags are used by the controller to select subnets that will be used to create Load Balancer services.

> Question: iirc there is a limitation that the controller will always try to use at least one subnet by zone, the lb tags will help to select the subnets when there is more than one in the same zone. Need to check the current cloud provider implementation. reference bug in Local Zones: TODO Issue

### Expected

- OpenShift installer creates the API NLB into single-zone
- Load Balancer controller (cloud provider) assign only the subnet used by the installer labels with load balancer tags `kubernetes.io/role/elb=1` and `kubernetes.io/role/internal-elb=1`, respecting the cluster tags used in [the discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.2/deploy/subnet_discovery/), preventing to add all subnets to the load balancer created by the service (in this case the default router).


### Steps:

- Export Subnet and VPC ID

```bash
export PUBLIC_SUBNET_ID_1B=${PUBLIC_SUBNETS[1]}
export PRIVATE_SUBNET_ID_1B=${PRIVATE_SUBNETS[1]}

export ZONE_NAME_1B=$(aws ec2 describe-subnets --filter --subnet-ids ${PUBLIC_SUBNET_ID_1B} ${PRIVATE_SUBNET_ID_1B} | jq -r '.Subnets[0].AvailabilityZone')
```

- Check if subnets must be part of the same AZ:

```bash
$ aws ec2 describe-subnets --subnet-ids ${PUBLIC_SUBNET_ID_1B} ${PRIVATE_SUBNET_ID_1B} | jq -r '.Subnets[] | [.AvailabilityZone, .CidrBlock, .SubnetId, .VpcId, [ .Tags[] | select(.Key=="Name").Value][0] ]'
[
  "us-east-1b",
  "10.0.16.0/20",
  "subnet-034e4acc93f527772",
  "vpc-09e41ea29d3f0b22d",
  "byonet-use1-public-2"
]
[
  "us-east-1b",
  "10.0.64.0/20",
  "subnet-0d39a85a25fc55f3b",
  "vpc-09e41ea29d3f0b22d",
  "byonet-use1-private-2"
]
```

- Create tags

```bash
$ aws ec2 create-tags --resources ${PUBLIC_SUBNET_ID_1B} --tags Key=kubernetes.io/role/elb,Value=1

$ aws ec2 create-tags --resources ${PRIVATE_SUBNET_ID_1B} --tags Key=kubernetes.io/role/elb-internal,Value=1
```

- Check subnet tags

```bash
$ aws ec2 describe-subnets --subnet-ids ${PUBLIC_SUBNET_ID_1B} ${PRIVATE_SUBNET_ID_1B} | jq -r '.Subnets[] | [.AvailabilityZone, .CidrBlock, .SubnetId, .VpcId, [ .Tags[] | select(.Key | contains("aws:cloudformation") | not) ] ] '
```
```json
[
  "us-east-1b",
  "10.0.16.0/20",
  "subnet-034e4acc93f527772",
  "vpc-09e41ea29d3f0b22d",
  [
    {
      "Key": "openshift_creationDate",
      "Value": "2023-06-14T21:08:07.327545+00:00"
    },
    {
      "Key": "kubernetes.io/role/elb",
      "Value": "1"
    },
    {
      "Key": "Name",
      "Value": "byonet-use1-public-2"
    }
  ]
]
[
  "us-east-1b",
  "10.0.64.0/20",
  "subnet-0d39a85a25fc55f3b",
  "vpc-09e41ea29d3f0b22d",
  [
    {
      "Key": "openshift_creationDate",
      "Value": "2023-06-14T21:08:07.327545+00:00"
    },
    {
      "Key": "Name",
      "Value": "byonet-use1-private-2"
    },
    {
      "Key": "kubernetes.io/role/elb-internal",
      "Value": "1"
    }
  ]
]
```


- Create install-config

```bash
export CLUSTER_NAME_1B=${VPC_NAME}b
export BASE_DOMAIN=devcluster.openshift.com
export SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

INSTALL_DIR_1B=${CLUSTER_NAME_1B}
mkdir $INSTALL_DIR_1B

cat <<EOF > ${INSTALL_DIR_1B}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: ${BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME_1B}"
platform:
  aws:
    region: ${CLUSTER_REGION}
    subnets:
    - ${PUBLIC_SUBNET_ID_1B}
    - ${PRIVATE_SUBNET_ID_1B}
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
```

- Check install-config.yaml

```bash
$ grep -vE '(^pull|ssh)' ${INSTALL_DIR_1B}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: devcluster.openshift.com
metadata:
  name: "byonet-use1b"
platform:
  aws:
    region: us-east-1
    subnets:
    - subnet-034e4acc93f527772
    - subnet-0d39a85a25fc55f3b

```

- Create manifests

```bash
./openshift-install create manifests --dir $INSTALL_DIR_1B
```

- Check processed manifests

```bash
$ grep $CLUSTER_REGION $INSTALL_DIR_1B/openshift/*.yaml
byonet-use1b/openshift/99_openshift-cluster-api_master-machines-0.yaml:        availabilityZone: us-east-1b
byonet-use1b/openshift/99_openshift-cluster-api_master-machines-0.yaml:        region: us-east-1
byonet-use1b/openshift/99_openshift-cluster-api_master-machines-1.yaml:        availabilityZone: us-east-1b
byonet-use1b/openshift/99_openshift-cluster-api_master-machines-1.yaml:        region: us-east-1
byonet-use1b/openshift/99_openshift-cluster-api_master-machines-2.yaml:        availabilityZone: us-east-1b
byonet-use1b/openshift/99_openshift-cluster-api_master-machines-2.yaml:        region: us-east-1
byonet-use1b/openshift/99_openshift-cluster-api_worker-machineset-0.yaml:  name: byonet-use1b-fmgbp-worker-us-east-1b
byonet-use1b/openshift/99_openshift-cluster-api_worker-machineset-0.yaml:      machine.openshift.io/cluster-api-machineset: byonet-use1b-fmgbp-worker-us-east-1b
byonet-use1b/openshift/99_openshift-cluster-api_worker-machineset-0.yaml:        machine.openshift.io/cluster-api-machineset: byonet-use1b-fmgbp-worker-us-east-1b
byonet-use1b/openshift/99_openshift-cluster-api_worker-machineset-0.yaml:            availabilityZone: us-east-1b
byonet-use1b/openshift/99_openshift-cluster-api_worker-machineset-0.yaml:            region: us-east-1
byonet-use1b/openshift/99_openshift-machine-api_master-control-plane-machine-set.yaml:            availabilityZone: us-east-1b
byonet-use1b/openshift/99_openshift-machine-api_master-control-plane-machine-set.yaml:              region: us-east-1

```

- Create NLB manifest for ingress with single subnet annotation

```bash
cat <<EOF > ${INSTALL_DIR_1B}/manifests/cluster-ingress-default-ingresscontroller.yaml
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

- Create cluster

```bash
$ ./openshift-install create cluster --dir $INSTALL_DIR_1B

$ tail -n 8 $INSTALL_DIR_1B/.openshift_install.log
time="2023-06-14T22:40:02-03:00" level=debug msg="Time elapsed per stage:"
time="2023-06-14T22:40:02-03:00" level=debug msg="           cluster: 3m55s"
time="2023-06-14T22:40:02-03:00" level=debug msg="         bootstrap: 40s"
time="2023-06-14T22:40:02-03:00" level=debug msg="Bootstrap Complete: 16m47s"
time="2023-06-14T22:40:02-03:00" level=debug msg="               API: 1m33s"
time="2023-06-14T22:40:02-03:00" level=debug msg=" Bootstrap Destroy: 1m31s"
time="2023-06-14T22:40:02-03:00" level=debug msg=" Cluster Operators: 36s"
time="2023-06-14T22:40:02-03:00" level=info msg="Time elapsed: 24m25s"
```

- Check cluster

```bash
export KUBECONFIG=$INSTALL_DIR_1B/auth/kubeconfig
oc get co

$ oc get machines -n openshift-machine-api
NAME                                         PHASE     TYPE         REGION      ZONE         AGE
byonet-use1b-fmgbp-master-0                  Running   m6i.xlarge   us-east-1   us-east-1b   28m
byonet-use1b-fmgbp-master-1                  Running   m6i.xlarge   us-east-1   us-east-1b   28m
byonet-use1b-fmgbp-master-2                  Running   m6i.xlarge   us-east-1   us-east-1b   28m
byonet-use1b-fmgbp-worker-us-east-1b-4vtf9   Running   m6i.xlarge   us-east-1   us-east-1b   24m
byonet-use1b-fmgbp-worker-us-east-1b-gsf9l   Running   m6i.xlarge   us-east-1   us-east-1b   24m
byonet-use1b-fmgbp-worker-us-east-1b-tv6jl   Running   m6i.xlarge   us-east-1   us-east-1b   24m

```

- Check the subnet tags after the cluster install, expected only the subnet in the zone us-east-1a to be tagged by the installer:

> removing manually the `tag:Name=openshift_creationDate`

> Note that the cluster tags is correct for both subnets in AZ 1a and 1b, for each cluster

```bash
$ aws ec2 describe-subnets --filter Name=vpc-id,Values=$VPC_ID | jq -cr '.Subnets[] | [.AvailabilityZone, .SubnetId, [ .Tags[] | select(.Key | contains("aws:cloudformation") | not) ] ] '

["us-east-1a","subnet-03d8721dd76527772",
    [{"Key":"Name","Value":"byonet-use1-public-1"},
    {"Key":"kubernetes.io/cluster/byonet-use1a-4n424","Value":"shared"},
    {"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"}]]
["us-east-1a","subnet-00accc137becba0b2",
    [{"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"},
    {"Key":"kubernetes.io/cluster/byonet-use1a-4n424","Value":"shared"},
    {"Key":"Name","Value":"byonet-use1-private-1"}]]
["us-east-1b","subnet-034e4acc93f527772",
    [{"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"},
    {"Key":"kubernetes.io/cluster/byonet-use1b-fmgbp","Value":"shared"},
    {"Key":"kubernetes.io/role/elb","Value":"1"},
    {"Key":"Name","Value":"byonet-use1-public-2"}]]
["us-east-1b","subnet-0d39a85a25fc55f3b",
    [{"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"},
    {"Key":"Name","Value":"byonet-use1-private-2"},
    {"Key":"kubernetes.io/role/elb-internal","Value":"1"},
    {"Key":"kubernetes.io/cluster/byonet-use1b-fmgbp","Value":"shared"}]]
["us-east-1c","subnet-0ef652f1be3095813",
    [{"Key":"Name","Value":"byonet-use1-private-3"},
    {"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"}]]
["us-east-1c","subnet-058247e779d805066",
    [{"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"},
    {"Key":"Name","Value":"byonet-use1-public-3"}]]
```

- Check the subnets attached to the router's service/NLB:

```bash
ROUTER_LB_HOSTNAME_1B=$(oc get svc -n openshift-ingress -o json | jq -r '.items[] | select (.spec.type=="LoadBalancer").status.loadBalancer.ingress[0].hostname')

$ aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select (.DNSName==\"${ROUTER_LB_HOSTNAME_1B}\") | [.DNSName, .AvailabilityZones]"
[
  "ad6ebaad68b3a466c87d1a507bf097bb-ba6db01b4ab144eb.elb.us-east-1.amazonaws.com",
  [
    {
      "ZoneName": "us-east-1c",
      "SubnetId": "subnet-058247e779d805066",
      "LoadBalancerAddresses": []
    },
    {
      "ZoneName": "us-east-1b",
      "SubnetId": "subnet-034e4acc93f527772",
      "LoadBalancerAddresses": []
    }
  ]
]
```

### Actual results:

- API NLB created correctly
- Ingress NLB has been created wrongly, but selected only subnets us-east-1b and us-east-1c - from subnets that do not have cluster tags.
    - the LB tags don't take effect
    - A workaround could be added by tagging all the subnets with cluster tags
    - Maybe creating the subnets with an "unmanaged" tag could be one alternative (TODO)

## Scenario 03: Install in zone 1c (similar 1a)

### Expected

- OpenShift installer creates the API NLB into a single zone
- Considering the results of Scenarios 1 and 2, and that the subnets in 1a and 1b have already the cluster tags, is expected that the Load Balancer controller selects only the subnet in 1c

### Steps:

- Export Subnet and VPC ID

```bash
export PUBLIC_SUBNET_ID_1C=${PUBLIC_SUBNETS[2]}
export PRIVATE_SUBNET_ID_1C=${PRIVATE_SUBNETS[2]}

export ZONE_NAME_1C=$(aws ec2 describe-subnets --filter --subnet-ids ${PUBLIC_SUBNET_ID_1C} ${PRIVATE_SUBNET_ID_1C} | jq -r '.Subnets[0].AvailabilityZone')
```

- Check if subnets must be part of the same AZ:

```bash
$ aws ec2 describe-subnets --subnet-ids ${PUBLIC_SUBNET_ID_1C} ${PRIVATE_SUBNET_ID_1C} | jq -rc '.Subnets[] | [.AvailabilityZone, .CidrBlock, .SubnetId, .VpcId, [ .Tags[] | select(.Key=="Name").Value][0] ]'
```
```json
["us-east-1c","10.0.80.0/20","subnet-0ef652f1be3095813","vpc-09e41ea29d3f0b22d","byonet-use1-private-3"]
["us-east-1c","10.0.32.0/20","subnet-058247e779d805066","vpc-09e41ea29d3f0b22d","byonet-use1-public-3"]
```

- Check subnet tags

```bash
$ aws ec2 describe-subnets --subnet-ids ${PUBLIC_SUBNET_ID_1C} ${PRIVATE_SUBNET_ID_1C} | jq -cr '.Subnets[] | [.AvailabilityZone, .CidrBlock, .SubnetId, .VpcId, [ .Tags[] | select(.Key | contains("aws:cloudformation") | not) ] ] '
```
```json
["us-east-1c","10.0.80.0/20","subnet-0ef652f1be3095813","vpc-09e41ea29d3f0b22d",
    [{"Key":"Name","Value":"byonet-use1-private-3"},
    {"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"}]]
["us-east-1c","10.0.32.0/20","subnet-058247e779d805066","vpc-09e41ea29d3f0b22d",
    [{"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"},
    {"Key":"Name","Value":"byonet-use1-public-3"}]]
```

- Create install-config

```bash
export CLUSTER_NAME_1C=${VPC_NAME}c
export BASE_DOMAIN=devcluster.openshift.com
export SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

INSTALL_DIR_1C=${CLUSTER_NAME_1C}
mkdir $INSTALL_DIR_1C

cat <<EOF > ${INSTALL_DIR_1C}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: ${BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME_1C}"
platform:
  aws:
    region: ${CLUSTER_REGION}
    subnets:
    - ${PUBLIC_SUBNET_ID_1C}
    - ${PRIVATE_SUBNET_ID_1C}
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
```

- Check install-config.yaml

```bash
$ grep -vE '(^pull|ssh)' ${INSTALL_DIR_1C}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: devcluster.openshift.com
metadata:
  name: "byonet-use1c"
platform:
  aws:
    region: us-east-1
    subnets:
    - subnet-058247e779d805066
    - subnet-0ef652f1be3095813
```

- Create manifests

```bash
./openshift-install create manifests --dir $INSTALL_DIR_1C
```

- Check processed machineset manifests with region reference (expected single zone reference)

```bash
$ grep $CLUSTER_REGION $INSTALL_DIR_1C/openshift/*.yaml
```

- Create NLB manifest for ingress with single subnet annotation:

```bash
cat <<EOF > ${INSTALL_DIR_1C}/manifests/cluster-ingress-default-ingresscontroller.yaml
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

- Create cluster

```bash
$ ./openshift-install create cluster --dir $INSTALL_DIR_1C

$ tail -n 8 $INSTALL_DIR_1C/.openshift_install.log
```

- Check cluster

```bash
export KUBECONFIG=$INSTALL_DIR_1C/auth/kubeconfig
oc get co

$ oc get machines -n openshift-machine-api
NAME                                         PHASE     TYPE         REGION      ZONE         AGE
byonet-use1c-2bqjk-master-0                  Running   m6i.xlarge   us-east-1   us-east-1c   18m
byonet-use1c-2bqjk-master-1                  Running   m6i.xlarge   us-east-1   us-east-1c   18m
byonet-use1c-2bqjk-master-2                  Running   m6i.xlarge   us-east-1   us-east-1c   18m
byonet-use1c-2bqjk-worker-us-east-1c-6c5hm   Running   m6i.xlarge   us-east-1   us-east-1c   14m
byonet-use1c-2bqjk-worker-us-east-1c-dhhtr   Running   m6i.xlarge   us-east-1   us-east-1c   14m
byonet-use1c-2bqjk-worker-us-east-1c-vmbbf   Running   m6i.xlarge   us-east-1   us-east-1c   14m

```

- Check the subnet tags after the cluster install, expected only the subnet in the zone us-east-1a to be tagged by the installer:

> removing manually the `tag:Name=openshift_creationDate`

> Note that the cluster tags is correct for both subnets in AZ 1a and 1b, for each cluster

```bash
$ aws ec2 describe-subnets --filter Name=vpc-id,Values=$VPC_ID | jq -cr '.Subnets[] | [.AvailabilityZone, .SubnetId, [ .Tags[] | select(.Key | contains("aws:cloudformation") | not) ] ] '
["us-east-1c","subnet-0ef652f1be3095813",
    [{"Key":"Name","Value":"byonet-use1-private-3"},
    {"Key":"kubernetes.io/cluster/byonet-use1c-2bqjk","Value":"shared"},
    {"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"}]]
["us-east-1a","subnet-03d8721dd76527772",
    [{"Key":"Name","Value":"byonet-use1-public-1"},
    {"Key":"kubernetes.io/cluster/byonet-use1a-4n424","Value":"shared"},
    {"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"}]]
["us-east-1c","subnet-058247e779d805066",
    [{"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"},
    {"Key":"Name","Value":"byonet-use1-public-3"},
    {"Key":"kubernetes.io/cluster/byonet-use1c-2bqjk","Value":"shared"}]]
["us-east-1b","subnet-034e4acc93f527772",
    [{"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"},
    {"Key":"kubernetes.io/cluster/byonet-use1b-fmgbp","Value":"shared"},
    {"Key":"kubernetes.io/role/elb","Value":"1"},
    {"Key":"Name","Value":"byonet-use1-public-2"}]]
["us-east-1b","subnet-0d39a85a25fc55f3b",
    [{"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"},
    {"Key":"Name","Value":"byonet-use1-private-2"},
    {"Key":"kubernetes.io/role/elb-internal","Value":"1"},
    {"Key":"kubernetes.io/cluster/byonet-use1b-fmgbp","Value":"shared"}]]
["us-east-1a","subnet-00accc137becba0b2",
    [{"Key":"openshift_creationDate","Value":"2023-06-14T21:08:07.327545+00:00"},
    {"Key":"kubernetes.io/cluster/byonet-use1a-4n424","Value":"shared"},
    {"Key":"Name","Value":"byonet-use1-private-1"}]]
```

- Check the subnets attached to the router's service/NLB:

```bash
ROUTER_LB_HOSTNAME_1C=$(oc get svc -n openshift-ingress -o json | jq -r '.items[] | select (.spec.type=="LoadBalancer").status.loadBalancer.ingress[0].hostname')

$ aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select (.DNSName==\"${ROUTER_LB_HOSTNAME_1C}\") | [.DNSName, .AvailabilityZones]"
[
  "a1a78f5b3390d4e55addb84e3c4a8114-626609e41f9a1b00.elb.us-east-1.amazonaws.com",
  [
    {
      "ZoneName": "us-east-1c",
      "SubnetId": "subnet-058247e779d805066",
      "LoadBalancerAddresses": []
    }
  ]
]
```

### Actual results:

- API NLB created correctly
- Ingress NLB has been created correctly in a single zone

Conclusion:

- when the subnets have the cluster tags assigned, the controller will not use it in the subnet discovery.

## Section 2. Workaround tagging subnets

Tag the subnets with cluster tags, preventing the subnet discovery to select subnets already "assigned" to a cluster, then renaming the tag for a subnet before creating the cluster.

## Steps

- Create a new VPC tagging the subnets with "unmanaged" cluster tag: `kubernetes.io/cluster/unmanaged=shared`

```bash
cat << EOF > template-vpc-workaround.yaml
AWSTemplateFormatVersion: 2010-09-09
Description: Template for Best Practice VPC with 1-3 AZs

Parameters:
  ClusterName:
    Type: String
    Description: ClusterName used to prefix resource names
  VpcCidr:
    AllowedPattern: ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(1[6-9]|2[0-4]))$
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/16-24.
    Default: 10.0.0.0/16
    Description: CIDR block for VPC.
    Type: String
  AvailabilityZoneCount:
    ConstraintDescription: "The number of availability zones. (Min: 1, Max: 3)"
    MinValue: 1
    MaxValue: 3
    Default: 1
    Description: "How many AZs to create VPC subnets for. (Min: 1, Max: 3)"
    Type: Number
  SubnetBits:
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/19-27.
    MinValue: 5
    MaxValue: 13
    Default: 12
    Description: "Size of each subnet to create within the availability zones. (Min: 5 = /27, Max: 13 = /19)"
    Type: Number

Metadata:
  AWS::CloudFormation::Interface:
    ParameterGroups:
    - Label:
        default: "Network Configuration"
      Parameters:
      - VpcCidr
      - SubnetBits
    - Label:
        default: "Availability Zones"
      Parameters:
      - AvailabilityZoneCount
    ParameterLabels:
      ClusterName:
        default: ""
      AvailabilityZoneCount:
        default: "Availability Zone Count"
      VpcCidr:
        default: "VPC CIDR"
      SubnetBits:
        default: "Bits Per Subnet"

Conditions:
  DoAz3: !Equals [3, !Ref AvailabilityZoneCount]
  DoAz2: !Or [!Equals [2, !Ref AvailabilityZoneCount], Condition: DoAz3]

Resources:
  VPC:
    Type: "AWS::EC2::VPC"
    Properties:
      EnableDnsSupport: "true"
      EnableDnsHostnames: "true"
      CidrBlock: !Ref VpcCidr
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-vpc" ] ]
      - Key: !Join [ "", [ "kubernetes.io/cluster/unmanaged" ] ]
        Value: "shared"

  PublicSubnet:
    Type: "AWS::EC2::Subnet"
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [0, !Cidr [!Ref VpcCidr, 6, !Ref SubnetBits]]
      AvailabilityZone: !Select
      - 0
      - Fn::GetAZs: !Ref "AWS::Region"
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-public-1" ] ]
      - Key: !Join [ "", [ "kubernetes.io/cluster/unmanaged" ] ]
        Value: "shared"
  PublicSubnet2:
    Type: "AWS::EC2::Subnet"
    Condition: DoAz2
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [1, !Cidr [!Ref VpcCidr, 6, !Ref SubnetBits]]
      AvailabilityZone: !Select
      - 1
      - Fn::GetAZs: !Ref "AWS::Region"
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-public-2" ] ]
      - Key: !Join [ "", [ "kubernetes.io/cluster/unmanaged" ] ]
        Value: "shared"
  PublicSubnet3:
    Type: "AWS::EC2::Subnet"
    Condition: DoAz3
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [2, !Cidr [!Ref VpcCidr, 6, !Ref SubnetBits]]
      AvailabilityZone: !Select
        - 2
        - Fn::GetAZs: !Ref "AWS::Region"
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-public-3" ] ]
      - Key: !Join [ "", [ "kubernetes.io/cluster/unmanaged" ] ]
        Value: "shared"

  InternetGateway:
    Type: "AWS::EC2::InternetGateway"
    Properties:
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-igw" ] ]
  GatewayToInternet:
    Type: "AWS::EC2::VPCGatewayAttachment"
    Properties:
      VpcId: !Ref VPC
      InternetGatewayId: !Ref InternetGateway

  PublicRouteTable:
    Type: "AWS::EC2::RouteTable"
    Properties:
      VpcId: !Ref VPC
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-rtb-public" ] ]
  PublicRoute:
    Type: "AWS::EC2::Route"
    DependsOn: GatewayToInternet
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway
  PublicSubnetRouteTableAssociation:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Properties:
      SubnetId: !Ref PublicSubnet
      RouteTableId: !Ref PublicRouteTable
  PublicSubnetRouteTableAssociation2:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Properties:
      SubnetId: !Ref PublicSubnet2
      RouteTableId: !Ref PublicRouteTable
  PublicSubnetRouteTableAssociation3:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Properties:
      SubnetId: !Ref PublicSubnet3
      RouteTableId: !Ref PublicRouteTable

  PrivateSubnet:
    Type: "AWS::EC2::Subnet"
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [3, !Cidr [!Ref VpcCidr, 6, !Ref SubnetBits]]
      AvailabilityZone: !Select
      - 0
      - Fn::GetAZs: !Ref "AWS::Region"
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-private-1" ] ]
      - Key: !Join [ "", [ "kubernetes.io/cluster/unmanaged" ] ]
        Value: "shared"
  PrivateRouteTable:
    Type: "AWS::EC2::RouteTable"
    Properties:
      VpcId: !Ref VPC
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-rtb-private-1" ] ]
  PrivateSubnetRouteTableAssociation:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Properties:
      SubnetId: !Ref PrivateSubnet
      RouteTableId: !Ref PrivateRouteTable
  NAT:
    DependsOn:
    - GatewayToInternet
    Type: "AWS::EC2::NatGateway"
    Properties:
      AllocationId:
        "Fn::GetAtt":
        - EIP
        - AllocationId
      SubnetId: !Ref PublicSubnet
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-natgw-private-1" ] ]
  EIP:
    Type: "AWS::EC2::EIP"
    Properties:
      Domain: vpc
  Route:
    Type: "AWS::EC2::Route"
    Properties:
      RouteTableId:
        Ref: PrivateRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId:
        Ref: NAT

  PrivateSubnet2:
    Type: "AWS::EC2::Subnet"
    Condition: DoAz2
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [4, !Cidr [!Ref VpcCidr, 6, !Ref SubnetBits]]
      AvailabilityZone: !Select
      - 1
      - Fn::GetAZs: !Ref "AWS::Region"
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-private-2" ] ]
      - Key: !Join [ "", [ "kubernetes.io/cluster/unmanaged" ] ]
        Value: "shared"
  PrivateRouteTable2:
    Type: "AWS::EC2::RouteTable"
    Condition: DoAz2
    Properties:
      VpcId: !Ref VPC
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-rtb-private-2" ] ]
  PrivateSubnetRouteTableAssociation2:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Condition: DoAz2
    Properties:
      SubnetId: !Ref PrivateSubnet2
      RouteTableId: !Ref PrivateRouteTable2
  NAT2:
    DependsOn:
    - GatewayToInternet
    Type: "AWS::EC2::NatGateway"
    Condition: DoAz2
    Properties:
      AllocationId:
        "Fn::GetAtt":
        - EIP2
        - AllocationId
      SubnetId: !Ref PublicSubnet2
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-natgw-private-2" ] ]
  EIP2:
    Type: "AWS::EC2::EIP"
    Condition: DoAz2
    Properties:
      Domain: vpc
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-eip-private-2" ] ]
  Route2:
    Type: "AWS::EC2::Route"
    Condition: DoAz2
    Properties:
      RouteTableId:
        Ref: PrivateRouteTable2
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId:
        Ref: NAT2

  PrivateSubnet3:
    Type: "AWS::EC2::Subnet"
    Condition: DoAz3
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [5, !Cidr [!Ref VpcCidr, 6, !Ref SubnetBits]]
      AvailabilityZone: !Select
      - 2
      - Fn::GetAZs: !Ref "AWS::Region"
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-private-3" ] ]
      - Key: !Join [ "", [ "kubernetes.io/cluster/unmanaged" ] ]
        Value: "shared"
  PrivateRouteTable3:
    Type: "AWS::EC2::RouteTable"
    Condition: DoAz3
    Properties:
      VpcId: !Ref VPC
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-rtb-private-3" ] ]
  PrivateSubnetRouteTableAssociation3:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Condition: DoAz3
    Properties:
      SubnetId: !Ref PrivateSubnet3
      RouteTableId: !Ref PrivateRouteTable3
  NAT3:
    DependsOn:
    - GatewayToInternet
    Type: "AWS::EC2::NatGateway"
    Condition: DoAz3
    Properties:
      AllocationId:
        "Fn::GetAtt":
        - EIP3
        - AllocationId
      SubnetId: !Ref PublicSubnet3
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-natgw-private-3" ] ]
  EIP3:
    Type: "AWS::EC2::EIP"
    Condition: DoAz3
    Properties:
      Domain: vpc
      Tags:
      - Key: Name
        Value: !Join [ "", [ !Ref ClusterName, "-eip-private-3" ] ]
  Route3:
    Type: "AWS::EC2::Route"
    Condition: DoAz3
    Properties:
      RouteTableId:
        Ref: PrivateRouteTable3
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId:
        Ref: NAT3

  S3Endpoint:
    Type: AWS::EC2::VPCEndpoint
    Properties:
      PolicyDocument:
        Version: 2012-10-17
        Statement:
        - Effect: Allow
          Principal: '*'
          Action:
          - '*'
          Resource:
          - '*'
      RouteTableIds:
      - !Ref PublicRouteTable
      - !Ref PrivateRouteTable
      - !If [DoAz2, !Ref PrivateRouteTable2, !Ref "AWS::NoValue"]
      - !If [DoAz3, !Ref PrivateRouteTable3, !Ref "AWS::NoValue"]
      ServiceName: !Join
      - ''
      - - com.amazonaws.
        - !Ref 'AWS::Region'
        - .s3
      VpcId: !Ref VPC

Outputs:
  VpcId:
    Description: ID of the new VPC.
    Value: !Ref VPC
  PublicSubnetIds:
    Description: Subnet IDs of the public subnets.
    Value:
      !Join [
        ",",
        [!Ref PublicSubnet, !If [DoAz2, !Ref PublicSubnet2, !Ref "AWS::NoValue"], !If [DoAz3, !Ref PublicSubnet3, !Ref "AWS::NoValue"]]
      ]
  PrivateSubnetIds:
    Description: Subnet IDs of the private subnets.
    Value:
      !Join [
        ",",
        [!Ref PrivateSubnet, !If [DoAz2, !Ref PrivateSubnet2, !Ref "AWS::NoValue"], !If [DoAz3, !Ref PrivateSubnet3, !Ref "AWS::NoValue"]]
      ]
  PublicRouteTableId:
    Description: Public Route table ID
    Value: !Ref PublicRouteTable
  PrivateRouteTableIds:
    Description: Private Route table ID
    Value:
      !Join [
        ",",
        [!Ref PrivateRouteTable, !If [DoAz2, !Ref PrivateRouteTable2, !Ref "AWS::NoValue"], !If [DoAz3, !Ref PrivateRouteTable3, !Ref "AWS::NoValue"]]
      ]
EOF
```

- Create VPC

```bash
export CLUSTER_REGION=us-east-1
export VPC_NAME_WA=byonetwa-use1

export STACK_VPC_WA=${VPC_NAME_WA}-vpc
aws cloudformation create-stack \
  --region ${CLUSTER_REGION} \
  --stack-name ${STACK_VPC_WA} \
  --template-body file://template-vpc-workaround.yaml \
  --parameters \
      ParameterKey=ClusterName,ParameterValue=${STACK_VPC_WA} \
      ParameterKey=VpcCidr,ParameterValue="10.0.0.0/16" \
      ParameterKey=AvailabilityZoneCount,ParameterValue=3 \
      ParameterKey=SubnetBits,ParameterValue=12

aws --region ${CLUSTER_REGION} cloudformation wait stack-create-complete --stack-name ${STACK_VPC_WA}
aws --region ${CLUSTER_REGION} cloudformation describe-stacks --stack-name ${STACK_VPC_WA}
```

- Export Subnet and VPC ID

```bash
mapfile -t PRIVATE_SUBNETS_WA < <(aws --region ${CLUSTER_REGION} \
  cloudformation describe-stacks --stack-name "${STACK_VPC_WA}" \
  | jq -r '.Stacks[0].Outputs[0].OutputValue' | tr ',' '\n')

mapfile -t PUBLIC_SUBNETS_WA < <(aws --region ${CLUSTER_REGION} \
  cloudformation describe-stacks --stack-name "${STACK_VPC_WA}" \
  | jq -r '.Stacks[0].Outputs[1].OutputValue' | tr ',' '\n')

export VPC_ID_WA=$(aws --region ${CLUSTER_REGION} \
  cloudformation describe-stacks --stack-name "${STACK_VPC_WA}" \
  | jq -r '.Stacks[0].Outputs[2].OutputValue')
```

- Check the tags for each subnet in the VPC:

```bash
$ aws ec2 describe-subnets --filter Name=vpc-id,Values=$VPC_ID_WA | jq -cr '.Subnets[] | [.AvailabilityZone, .SubnetId, [ .Tags[] | select(.Key | contains("aws:") | not) ] ] '
["us-east-1c","subnet-0088147f2802d57c2",
    [{"Key":"kubernetes.io/cluster/unmanaged","Value":"shared"},
    {"Key":"Name","Value":"byonetwa-use1-vpc-private-3"}]]
["us-east-1b","subnet-09855162abffd86b0",
    [{"Key":"Name","Value":"byonetwa-use1-vpc-private-2"},
    {"Key":"kubernetes.io/cluster/unmanaged","Value":"shared"}]]
["us-east-1a","subnet-0b703440e41f57cab",
    [{"Key":"Name","Value":"byonetwa-use1-vpc-public-1"},
    {"Key":"kubernetes.io/cluster/unmanaged","Value":"shared"}]]
["us-east-1b","subnet-04238a15d9aafe15c",
    [{"Key":"Name","Value":"byonetwa-use1-vpc-public-2"},
    {"Key":"kubernetes.io/cluster/unmanaged","Value":"shared"}]]
["us-east-1c","subnet-03e6115c9c3eff5de",
    [{"Key":"Name","Value":"byonetwa-use1-vpc-public-3"},
    {"Key":"kubernetes.io/cluster/unmanaged","Value":"shared"}]]
["us-east-1a","subnet-0ecc11b754e8280e5",
    [{"Key":"kubernetes.io/cluster/unmanaged","Value":"shared"},
    {"Key":"Name","Value":"byonetwa-use1-vpc-private-1"}]]
```

### Create a cluster

 Export Subnet and VPC ID

```bash
export PUBLIC_SUBNET_ID_WA_1A=${PUBLIC_SUBNETS_WA[0]}
export PRIVATE_SUBNET_ID_WA_1A=${PRIVATE_SUBNETS_WA[0]}
```

- Check if subnets must be part of the same AZ:

```bash
$ aws ec2 describe-subnets --subnet-ids ${PUBLIC_SUBNET_ID_WA_1A} ${PRIVATE_SUBNET_ID_WA_1A} | jq -cr '.Subnets[] | [.AvailabilityZone, .CidrBlock, .SubnetId, .VpcId]'
["us-east-1a","10.0.0.0/20","subnet-0b703440e41f57cab","vpc-0c4e8e0cb6545e511"]
["us-east-1a","10.0.48.0/20","subnet-0ecc11b754e8280e5","vpc-0c4e8e0cb6545e511"]
```

- Create install-config

```bash
export CLUSTER_NAME_WA_1A=${VPC_NAME_WA}a
export BASE_DOMAIN=devcluster.openshift.com
export SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

INSTALL_DIR_WA_1A=${CLUSTER_NAME_WA_1A}
mkdir $INSTALL_DIR_WA_1A

cat <<EOF > ${INSTALL_DIR_WA_1A}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: ${BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME_WA_1A}"
platform:
  aws:
    region: ${CLUSTER_REGION}
    subnets:
    - ${PUBLIC_SUBNET_ID_WA_1A}
    - ${PRIVATE_SUBNET_ID_WA_1A}
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
```

- Check install-config.yaml

```bash
$ grep -vE '(^pull|ssh)' ${INSTALL_DIR_WA_1A}/install-config.yaml

```

- Create manifests

```bash
./openshift-install create manifests --dir $INSTALL_DIR_WA_1A
```

- Check processed manifests

```bash
$ grep $CLUSTER_REGION $INSTALL_DIR_WA_1A/openshift/*.yaml
```

- Create NLB manifest for ingress with single subnet annotation

```bash
cat <<EOF > ${INSTALL_DIR_WA_1A}/manifests/cluster-ingress-default-ingresscontroller.yaml
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

#### Patch/workaround steps for day-0

Discover the correct value for the cluster tags (from installer manifests) and update the subnet tags:

- Get the Infra ID generated by the installer:

```bash
INFRA_ID_WA_1A="$(awk '/infrastructureName: / {print $2}' ${INSTALL_DIR_WA_1A}/manifests/cluster-infrastructure-02-config.yml)"
```

- Delete the subnet tags

```bash
aws ec2 delete-tags --resources ${PUBLIC_SUBNET_ID_WA_1A} --tags Key=kubernetes.io/cluster/unmanaged
aws ec2 delete-tags --resources ${PRIVATE_SUBNET_ID_WA_1A} --tags Key=kubernetes.io/cluster/unmanaged
```

- Create new tags

```bash
aws ec2 create-tags --resources ${PUBLIC_SUBNET_ID_WA_1A} --tags Key=kubernetes.io/cluster/${INFRA_ID_WA_1A},Value=shared
aws ec2 create-tags --resources ${PRIVATE_SUBNET_ID_WA_1A} --tags Key=kubernetes.io/cluster/${INFRA_ID_WA_1A},Value=shared
```

- Check tags

```bash
$ aws ec2 describe-subnets --subnet-ids ${PUBLIC_SUBNET_ID_WA_1A} ${PRIVATE_SUBNET_ID_WA_1A} | jq -cr '.Subnets[] | [.AvailabilityZone, .SubnetId, [ .Tags[] | select(.Key | contains("kubernetes.io/cluster")) ] ] '
["us-east-1a","subnet-0b703440e41f57cab",
    [{"Key":"kubernetes.io/cluster/byonetwa-use1a-9xqtz","Value":"shared"}]]
["us-east-1a","subnet-0ecc11b754e8280e5",
    [{"Key":"kubernetes.io/cluster/byonetwa-use1a-9xqtz","Value":"shared"}]]
```

#### Create the cluster


- Create cluster

```bash
$ ./openshift-install create cluster --dir $INSTALL_DIR_WA_1A

$ tail -n 8 $INSTALL_DIR_WA_1A/.openshift_install.log

```

- Check cluster

```bash
export KUBECONFIG=$INSTALL_DIR_WA_1A/auth/kubeconfig
oc get co

$ oc get machines -n openshift-machine-api
NAME                                           PHASE     TYPE         REGION      ZONE         AGE
byonetwa-use1a-9xqtz-master-0                  Running   m6i.xlarge   us-east-1   us-east-1a   20m
byonetwa-use1a-9xqtz-master-1                  Running   m6i.xlarge   us-east-1   us-east-1a   20m
byonetwa-use1a-9xqtz-master-2                  Running   m6i.xlarge   us-east-1   us-east-1a   20m
byonetwa-use1a-9xqtz-worker-us-east-1a-5t9hz   Running   m6i.xlarge   us-east-1   us-east-1a   16m
byonetwa-use1a-9xqtz-worker-us-east-1a-7jls4   Running   m6i.xlarge   us-east-1   us-east-1a   16m
byonetwa-use1a-9xqtz-worker-us-east-1a-bkggz   Running   m6i.xlarge   us-east-1   us-east-1a   16m
```

- Check the subnet tags after the cluster install, expected only the subnet in the zone us-east-1a to be tagged by the installer:

```bash
$ aws ec2 describe-subnets --filter Name=vpc-id,Values=$VPC_ID_WA | jq -cr '.Subnets[] | [.AvailabilityZone, .SubnetId, [ .Tags[] | select(.Key | contains("aws:cloudformation") | not) ] ] '
["us-east-1c","subnet-0088147f2802d57c2",
    [{"Key":"kubernetes.io/cluster/unmanaged","Value":"shared"},
    {"Key":"Name","Value":"byonetwa-use1-vpc-private-3"},
    {"Key":"openshift_creationDate","Value":"2023-06-15T03:06:32.858471+00:00"}]]
["us-east-1b","subnet-09855162abffd86b0",
    [{"Key":"openshift_creationDate","Value":"2023-06-15T03:06:32.858471+00:00"},
    {"Key":"Name","Value":"byonetwa-use1-vpc-private-2"},
    {"Key":"kubernetes.io/cluster/unmanaged","Value":"shared"}]]
["us-east-1a","subnet-0b703440e41f57cab",
    [{"Key":"Name","Value":"byonetwa-use1-vpc-public-1"},
    {"Key":"kubernetes.io/cluster/byonetwa-use1a-9xqtz","Value":"shared"},
    {"Key":"openshift_creationDate","Value":"2023-06-15T03:06:32.858471+00:00"}]]
["us-east-1b","subnet-04238a15d9aafe15c",
    [{"Key":"openshift_creationDate","Value":"2023-06-15T03:06:32.858471+00:00"},
    {"Key":"Name","Value":"byonetwa-use1-vpc-public-2"},
    {"Key":"kubernetes.io/cluster/unmanaged","Value":"shared"}]]
["us-east-1c","subnet-03e6115c9c3eff5de",
    [{"Key":"Name","Value":"byonetwa-use1-vpc-public-3"},
    {"Key":"openshift_creationDate","Value":"2023-06-15T03:06:32.858471+00:00"},
    {"Key":"kubernetes.io/cluster/unmanaged","Value":"shared"}]]
["us-east-1a","subnet-0ecc11b754e8280e5",
    [{"Key":"openshift_creationDate","Value":"2023-06-15T03:06:32.858471+00:00"},
    {"Key":"kubernetes.io/cluster/byonetwa-use1a-9xqtz","Value":"shared"},
    {"Key":"Name","Value":"byonetwa-use1-vpc-private-1"}]]
```

- Check the subnets attached to the router's service/NLB:

```bash
ROUTER_LB_HOSTNAME_WA_1A=$(oc get svc -n openshift-ingress -o json | jq -r '.items[] | select (.spec.type=="LoadBalancer").status.loadBalancer.ingress[0].hostname')

$ aws elbv2 describe-load-balancers | jq -r ".LoadBalancers[] | select (.DNSName==\"${ROUTER_LB_HOSTNAME_WA_1A}\") | [.DNSName, .AvailabilityZones]"
[
  "ab1a8eb7c4a474462a4e9efa492406e4-a42a2e8bacefa0f7.elb.us-east-1.amazonaws.com",
  [
    {
      "ZoneName": "us-east-1a",
      "SubnetId": "subnet-0b703440e41f57cab",
      "LoadBalancerAddresses": []
    }
  ]
]
```

Success!

Conclusion: to create many clusters using the same VPC, in different subnets/zones, the cluster tag `kubernetes.io/cluster/<value>=shared` must be set **on all the subnets prior to creating the cluster.**