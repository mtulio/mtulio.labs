# [incomplete/limited/draft] Install OpenShift cluster in the edge with AWS Local Zones and Wavelength

> WIP/Paused

> STATUS Note: Red Hat OpenShift does not provide a way to setup the Carrier Gateway directly, nor editing the network settings on the MachineSet. Reference: https://issues.redhat.com/browse/RFE-3045

This article describes the steps to [install the OpenShift cluster in an existing VPC](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-vpc.html) with [Local Zones](https://aws.amazon.com/about-aws/global-infrastructure/localzones/) and [Wavelength](https://aws.amazon.com/wavelength/) subnets, extending compute nodes to the edge locations with [MachineSets](https://docs.openshift.com/container-platform/4.10/machine_management/creating_machinesets/creating-machineset-aws.html).

**Table Of Contents**:

- [Summary](#summary)
- [Steps to create the cluster](#steps-create)
  - [Create the network stack](#steps-create-net)
    - [Create the network (VPC and dependencies)](#steps-create-net-vpc)
    - [Create the Local Zone subnet](#steps-create-net-lz-subnet)
    - [Create the Wavelength zone subnet](#steps-create-net-wl-subnet)
  - [Create the installer configuration](#steps-create-config)
  - [Create the installer manifests](#steps-create-manifests)
    - [Create the Machine Set manifest for Local Zone subnet](#steps-create-manifests-ms)
    - [Create the Machine Set manifest for Wavelength subnet](#steps-create-manifests-ms)
  - [Install the cluster](#steps-create-install)
- [Steps to Destroy the Cluster](#steps-destroy)
- [Final notes / conclusion](#review)
- [References](#references)

## Summary <a name="summary"></a>

### Reference Architecture

The following network assets will be created in this article:

- 1 VPC with CIDR 10.0.0.0/16
- 4 Public subnets on the zones: us-east-1a, us-east-1b, us-east-1c, us-east-1-nyc-1a
- 3 Private subnets on the zones: us-east-1a, us-east-1b, us-east-1c
- 3 NAT Gateway, one per private subnet
- 1 Internet gateway
- 4 route tables, 3 for private subnets and one for public subnets

The following OpenShift cluster nodes will be created:

- 3 Control Plane nodes running in the subnets on the "parent region" (us-east-1{a,b,c})
- 3 Compute nodes (Machine Set) running in the subnets on the "parent region" (us-east-1{a,b,c})
- 1 Compute node (Machine Set) running in the edge location us-east-1-nyc-1a (NYC Local Zone)
- 1 Compute node (Machine Set) running in the edge location us-east-1-nyc-1a (NYC Wavelength by Verizon)

### Requirements

- OpenShift CLI (`oc`)
- AWS CLI (`aws`)

### Preparing the environment

- Export the common environment variables (change me)

```bash
export VERSION=4.11.0-rc.1
export PULL_SECRET_FILE=${HOME}/.openshift/pull-secret-latest.json
export SSH_PUB_KEY_FILE="${HOME}/.ssh/id_rsa.pub"
```

- Install the clients

```bash
oc adm release extract \
    --tools "quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64" \
    -a "${PULL_SECRET_FILE}"

tar xvfz openshift-client-linux-${VERSION}.tar.gz
tar xvfz openshift-install-linux-${VERSION}.tar.gz
```

### Opt-in the Local Zone locations

For each Local Zone location, you must opt-in on the EC2 configuration - it's opt-out by default.

You can use the `describe-availability-zones` to check the location available in the region running your cluster.

Export the region of your OpenShift cluster will be created:

```bash
export CLUSTER_REGION="us-east-1"
```

Check the AZs available in your region:

```bash
aws ec2 describe-availability-zones \
    --filters Name=region-name,Values=${CLUSTER_REGION} \
    --query 'AvailabilityZones[].ZoneName' \
    --all-availability-zones
```

Depending on the region, that list can be long. Things you need to know:

- `${REGION}[a-z]` : Availability Zones available in the Region (parent)
- `${REGION}-LID-N[a-z]` : Local Zones available, where `LID-N` is the location identifier, and `[a-z]` is the zone identifier.
- `${REGION}-wl1-LID-wlz-[1-9]` : [Available Wavelength zones](https://aws.amazon.com/wavelength/)


Opt-in the location to your AWS Account - in this example `US East (New York)`:

```bash
aws ec2 modify-availability-zone-group \
    --group-name "${CLUSTER_REGION}-nyc-1a" \
    --opt-in-status opted-in
```

## Steps to create the Cluster <a name="steps-create"></a>

### Create the network stack <a name="steps-create-net"></a>

Steps to network stack describe how to:

- create the Network (VPC, subnets, Nat Gateways) in the parent/main zone
- create the subnet on the Local Zone location

#### Create the network (VPC and dependencies) <a name="steps-create-net-vpc"></a>

The first step is to create the network resources in the zones located in the parent region. Those steps reuse the VPC stack as described in the documentation[1], adapting it to tag the subnets with proper values[2] used by Kubernetes Controller Manager to discover the subnets used to create the Load Balancer used by the default router (ingress).

> [1] [OpenShift documentation / CloudFormation template for the VPC](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-user-infra.html#installation-cloudformation-vpc_installing-aws-user-infra)

> [2] [AWS Load Balancer Controller / Subnet Auto Discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/deploy/subnet_discovery/)

Steps to create the VPC stack:

- Set the environment variables

```bash
export CLUSTER_NAME="edge-demo"
export VPC_CIDR="10.0.0.0/16"
```

- Create the Template vars file

```bash
cat <<EOF | envsubst > ./stack-vpc-vars.json
[
  {
    "ParameterKey": "ClusterName",
    "ParameterValue": "${CLUSTER_NAME}"
  },
  {
    "ParameterKey": "VpcCidr",
    "ParameterValue": "${VPC_CIDR}"
  },
  {
    "ParameterKey": "AvailabilityZoneCount",
    "ParameterValue": "3"
  },
  {
    "ParameterKey": "SubnetBits",
    "ParameterValue": "12"
  }
]
EOF
```

- Download the <a href="https://raw.githubusercontent.com/mtulio/mtulio.labs/2c1d3761b5f21a94d8a458db48636c4c2d8a478f/docs/articles/assets/ocp-aws-local-zones-day-0_cfn-net-vpc.yaml" target="_blank">CloudFormation Template for VPC stack</a>


- Create the VPC Stack

```bash
STACK_VPC=${CLUSTER_NAME}-vpc
STACK_VPC_TPL="${PWD}/ocp-aws-local-zones-day-0_cfn-net-vpc.yaml"
STACK_VPC_VARS="${PWD}/stack-vpc-vars.json"
aws cloudformation create-stack --stack-name ${STACK_VPC} \
     --template-body file://${STACK_VPC_TPL} \
     --parameters file://${STACK_VPC_VARS}
```

- **Wait for the stack** to be completed (`StackStatus=CREATE_COMPLETE`)

```bash
aws cloudformation describe-stacks --stack-name ${STACK_VPC}
```

- (optional) Update the stack

```bash
aws cloudformation update-stack \
  --stack-name ${STACK_VPC} \
  --template-body file://${STACK_VPC_TPL} \
  --parameters file://${STACK_VPC_VARS}
```

#### Create the Local Zones subnet <a name="steps-create-net-lz-subnet"></a>

- Set the environment the variables to create the Local Zone subnet

```bash
export CLUSTER_REGION="us-east-1"
export LZ_ZONE_NAME="${CLUSTER_REGION}-nyc-1a"
export LZ_ZONE_SHORTNAME="nyc-lz"
export LZ_ZONE_CIDR="10.0.128.0/20"

export VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId").OutputValue' )
export VPC_RTB_PUB=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PublicRouteTableId").OutputValue' )
```

- Create the template vars file

```bash
cat <<EOF | envsubst > ./stack-lz-vars-${LZ_ZONE_SHORTNAME}.json
[
  {
    "ParameterKey": "ClusterName",
    "ParameterValue": "${CLUSTER_NAME}"
  },
  {
    "ParameterKey": "VpcId",
    "ParameterValue": "${VPC_ID}"
  },
  {
    "ParameterKey": "PublicRouteTableId",
    "ParameterValue": "${VPC_RTB_PUB}"
  },
  {
    "ParameterKey": "LocalZoneName",
    "ParameterValue": "${LZ_ZONE_NAME}"
  },
  {
    "ParameterKey": "LocalZoneNameShort",
    "ParameterValue": "${LZ_ZONE_SHORTNAME}"
  },
  {
    "ParameterKey": "PublicSubnetCidr",
    "ParameterValue": "${LZ_ZONE_CIDR}"
  }
]
EOF
```

- Download the [CloudFormation Template for Local Zone subnet stack](https://raw.githubusercontent.com/mtulio/mtulio.labs/2c1d3761b5f21a94d8a458db48636c4c2d8a478f/docs/articles/assets/ocp-aws-local-zones-day-0_cfn-net-lz.yaml)

- Create the Local Zones subnet stack

```bash
STACK_LZ=${CLUSTER_NAME}-net-lz-${LZ_ZONE_SHORTNAME}
STACK_LZ_TPL="${PWD}/ocp-aws-local-zones-day-0_cfn-net-lz.yaml"
STACK_LZ_VARS="${PWD}/stack-lz-vars-${LZ_ZONE_SHORTNAME}.json"
aws cloudformation create-stack \
  --stack-name ${STACK_LZ} \
  --template-body file://${STACK_LZ_TPL} \
  --parameters file://${STACK_LZ_VARS}
```

- Check the status (wait to be finished)

```bash
aws cloudformation describe-stacks --stack-name ${STACK_LZ}
```

Repeat the steps above for each location.

#### Create the Wavelength subnet <a name="steps-create-net-lz-subnet"></a>

- Opt-in the Wavelenght zone group

```bash
export AZ_GROUP_WL_NYC="${CLUSTER_REGION}-wl1"
export AZ_NAME_WL_NYC="${AZ_GROUP_LZ_NYC}-nyc-wlz-1"

aws ec2 modify-availability-zone-group \
    --group-name "${AZ_GROUP_WL_NYC}" \
    --opt-in-status opted-in
```

- Opt-in the Local Zone group

> Wavelenght zone groups are grouped by carrier on the region, so you need to enable it as it's available. On `us-east-1` the carrier operator is the `Verizon` identified by `us-east-1-wl1`

```bash
export AZ_GROUP_WL_NYC="${CLUSTER_REGION}-wl1"
export AZ_NAME_WL_NYC="${AZ_GROUP_WL_NYC}-nyc-wlz-1"
export AZ_NAME_WL_NYC_SHORT="nyc-wl"
export VPC_SUBNET_CIDR_WL="10.0.228.0/22"

aws ec2 modify-availability-zone-group \
    --group-name "${AZ_GROUP_WL_NYC}" \
    --opt-in-status opted-in
```

- Create the template vars file

```bash
cat <<EOF | envsubst > ./stack-edge-vars-${AZ_NAME_WL_NYC}.json
[
  {
    "ParameterKey": "ClusterName",
    "ParameterValue": "${CLUSTER_NAME}"
  },
  {
    "ParameterKey": "VpcId",
    "ParameterValue": "${VPC_ID}"
  },
  {
    "ParameterKey": "WavelengthZoneName",
    "ParameterValue": "${AZ_NAME_WL_NYC}"
  },
  {
    "ParameterKey": "WavelengthZoneNameShort",
    "ParameterValue": "${AZ_NAME_WL_NYC_SHORT}"
  },
  {
    "ParameterKey": "PublicSubnetCidr",
    "ParameterValue": "${VPC_SUBNET_CIDR_WL}"
  }
]
EOF
```

- Download the [CloudFormation Template for Local Zone subnet stack](https://raw.githubusercontent.com/mtulio/mtulio.labs/2c1d3761b5f21a94d8a458db48636c4c2d8a478f/docs/articles/assets/ocp-aws-local-zones-day-0_cfn-net-wl.yaml)

- Create the Local Zones subnet stack

```bash
STACK_WL=${CLUSTER_NAME}-net-wl-${AZ_NAME_WL_NYC}
STACK_WL_TPL="${PWD}/ocp-aws-local-zones-day-0_cfn-net-wl.yaml"
STACK_WL_VARS="${PWD}/stack-edge-vars-${AZ_NAME_WL_NYC}.json"
aws cloudformation create-stack \
  --stack-name ${STACK_WL} \
  --template-body file://${STACK_WL_TPL} \
  --parameters file://${STACK_WL_VARS}
```

- Check the status (wait to be finished)

```bash
aws cloudformation describe-stacks --stack-name ${STACK_WL}
```

Repeat the steps above for each location.

### Create the installer configuration <a name="steps-create-config"></a>

- Set the vars used on the installer configuration

```bash
export BASE_DOMAIN="devcluster.openshift.com"

# Parent region (main) subnets only: Public and Private
mapfile -t SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[0].OutputValue' | tr ',' '\n')
mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[1].OutputValue' | tr ',' '\n')
```

- Create the `install-config.yaml` file, setting the subnets recently created (**parent region only**)

> Adapt it as your usage, the requirement is to set the field `platform.aws.subnets` with the subnet IDs recently created

```bash
cat <<EOF > ${PWD}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: ${BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${CLUSTER_REGION}
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
```

- (Optional) Back up the install-config.yaml

```bash
cp -v ${PWD}/install-config.yaml \
    ${PWD}/install-config-bkp.yaml
```

### Create the installer manifests <a name="steps-create-manifests"></a>

- Create the manifests

```bash
./openshift-install create manifests
```

- Get the `InfraId` used in the next sections

```bash
export CLUSTER_ID="$(awk '/infrastructureName: / {print $2}' manifests/cluster-infrastructure-02-config.yml)"
```


#### Create the Machine Set manifest for Local Zones pool <a name="steps-create-manifests-ms"></a>

- Set the variables used to create the Machine Set

> Adapt the instance type as you need, as supported on the Local Zone

```bash
export INSTANCE_TYPE="t3.xlarge"

export AMI_ID=$(grep ami \
  openshift/99_openshift-cluster-api_worker-machineset-0.yaml \
  | tail -n1 | awk '{print$2}')
export SUBNET_ID=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_LZ}" \
  | jq -r .Stacks[0].Outputs[0].OutputValue)

export MAP_PUBLIC_IP=true
export CARRIER_GW_ENABLED=false
export LOCATION_TYPE=local-zone
```

- Create the Machine Set for `nyc-lz` nodes

> `publicIp: true` should be set to deploy the node in the public subnet in Local Zone.

> The public IP mapping is used merely to get access to the internet (required), optionally you can modify the network topology to use a private subnet, associating correctly the Local Zone private subnet to a valid route table that has correct routing entries to the internet. Or explore the [disconnected installations](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-restricted-networks-aws-installer-provisioned.html). None of those options will be covered in this article.

```bash
cat <<EOF > manifests/99_openshift-cluster-api_worker-machineset-nyc-lz.yaml
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
  name: ${CLUSTER_ID}-edge-${LZ_ZONE_NAME}
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-edge-${LZ_ZONE_NAME}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: edge
        machine.openshift.io/cluster-api-machine-type: edge
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-edge-${LZ_ZONE_NAME}
    spec:
      metadata:
        labels:
          location: ${LOCATION_TYPE}
          node-role.kubernetes.io/edge: ""
      taints:
        - key: node-role.kubernetes.io/edge
          effect: NoSchedule
      providerSpec:
        value:
          ami:
            id: ${AMI_ID}
          apiVersion: awsproviderconfig.openshift.io/v1beta1
          blockDevices:
          - ebs:
              volumeSize: 120
              volumeType: gp2
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: ${CLUSTER_ID}-worker-profile
          instanceType: ${INSTANCE_TYPE}
          kind: AWSMachineProviderConfig
          placement:
            availabilityZone: ${LZ_ZONE_NAME}
            region: ${CLUSTER_REGION}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - ${CLUSTER_ID}-worker-sg
          subnet:
            id: ${SUBNET_ID}
          publicIp: ${MAP_PUBLIC_IP}
          associateCarrierIpAddress: ${CARRIER_GW_ENABLED}
          tags:
          - name: kubernetes.io/cluster/${CLUSTER_ID}
            value: owned
          userDataSecret:
            name: worker-user-data
EOF
```

#### Create the Machine Set manifest for Wavelength zone pool <a name="steps-create-manifests-ms"></a>

- Set the variables used to create the Machine Set

> Adapt the instance type as you need, as supported on the Local Zone

```bash
export INSTANCE_TYPE="t3.xlarge"

export AMI_ID=$(grep ami \
  openshift/99_openshift-cluster-api_worker-machineset-0.yaml \
  | tail -n1 | awk '{print$2}')
export SUBNET_ID=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_WL}" \
  | jq -r .Stacks[0].Outputs[0].OutputValue)

export LOCATION_TYPE=wavelength
export MAP_PUBLIC_IP=false
export CARRIER_GW_ENABLED=true
```

- Create the Machine Set for `nyc-wl` nodes

```bash
cat <<EOF > manifests/99_openshift-cluster-api_worker-machineset-nyc-wl.yaml
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
  name: ${CLUSTER_ID}-edge-${AZ_NAME_WL_NYC}
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-edge-${AZ_NAME_WL_NYC}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: edge
        machine.openshift.io/cluster-api-machine-type: edge
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-edge-${AZ_NAME_WL_NYC}
    spec:
      metadata:
        labels:
          location: ${LOCATION_TYPE}
          node-role.kubernetes.io/edge: ""
      taints:
        - key: node-role.kubernetes.io/edge
          effect: NoSchedule
      providerSpec:
        value:
          ami:
            id: ${AMI_ID}
          apiVersion: awsproviderconfig.openshift.io/v1beta1
          blockDevices:
          - ebs:
              volumeSize: 120
              volumeType: gp2
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: ${CLUSTER_ID}-worker-profile
          instanceType: ${INSTANCE_TYPE}
          kind: AWSMachineProviderConfig
          placement:
            availabilityZone: ${AZ_NAME_WL_NYC}
            region: ${CLUSTER_REGION}
          #securityGroups:
          #- filters:
          #  - name: tag:Name
          #    values:
          #    - ${CLUSTER_ID}-worker-sg
          networkInterfaces:
          - deviceIndex: 0
            associateCarrierIpAddress: true
            groups:
              - sg-0400677e5c80e833f
            subnetId: subnet-06a02db2d750501b2
          subnet:
            id: ${SUBNET_ID}
          publicIp: ${MAP_PUBLIC_IP}
          associateCarrierIpAddress: ${CARRIER_GW_ENABLED}
          tags:
          - name: kubernetes.io/cluster/${CLUSTER_ID}
            value: owned
          userDataSecret:
            name: worker-user-data
EOF
```


### Install the cluster <a name="steps-create-install"></a>

Now it's time to create the cluster and check the results.

- Create the cluster

```bash
./openshift-install create cluster --log-level=debug
```

- Install summary

```
DEBUG Time elapsed per stage:
DEBUG            cluster: 4m28s
DEBUG          bootstrap: 36s
DEBUG Bootstrap Complete: 10m30s
DEBUG                API: 2m18s
DEBUG  Bootstrap Destroy: 57s
DEBUG  Cluster Operators: 8m39s
INFO Time elapsed: 25m50s
```

- Cluster operator's summary

```
$ oc get co -o json \
    | jq -r ".items[].status.conditions[] | select(.type==\"Available\").status" \
    | sort |uniq -c
     32 True

$ oc get co -o json \
    | jq -r ".items[].status.conditions[] | select(.type==\"Degraded\").status" \
    | sort |uniq -c
     32 False
```

- Machines in Local Zones

```bash
$ oc get machines -n openshift-machine-api \
  -l machine.openshift.io/zone=us-east-1-nyc-1a
NAME                                       PHASE     TYPE          REGION      ZONE               AGE
lzdemo-ds2dn-edge-us-east-1-nyc-1a-6645q   Running   c5d.2xlarge   us-east-1   us-east-1-nyc-1a   12m
```

- Nodes in Local Zones filtering by custom labels defined on Machine Set (location, zone_group)

```bash
$ oc get nodes -l location=local-zone
NAME                           STATUS   ROLES         AGE   VERSION
ip-10-0-143-104.ec2.internal   Ready    edge,worker   11m   v1.24.0+beaaed6
```

### Troubleshooting: MAPI is not setting `associateCarrierIpAddress`

The MAPI seems not to send to the API the attribute `associateCarrierIpAddress`, thus the public IP is not set to the instance and it can't access the internet to download the images, consequently the instace stuck in Provisioned phase.


Export UserData

```bash
oc --kubeconfig auth/kubeconfig get secret \
  -n openshift-machine-api worker-user-data \
  -o jsonpath="{.data.userData}" \
  | base64 -d > worker-user-data.txt

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
```

Running by AWS CLI:

```bash
aws ec2 run-instances \
  --region ${CLUSTER_REGION} \
  --network-interfaces "[{\"DeviceIndex\":0, \"AssociateCarrierIpAddress\": true, \"SubnetId\": \"${SUBNET_ID}\", \"Groups\": [\"sg-0400677e5c80e833f\"]}]" \
  --image-id ${AMI_ID} \
  --iam-instance-profile Name="${CLUSTER_ID}-worker-profile"  \
  --instance-type ${INSTANCE_TYPE} \
  --key-name openshift-dev \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=\"${CLUSTER_ID}-edge-${AZ_NAME_WL_NYC}-02\"},{Key=kubernetes.io/cluster/${CLUSTER_ID},Value=owned}]" \
  --user-data file://worker-user-data.txt
```

Approve CSRs

```
for CSR in $(oc --kubeconfig auth/kubeconfig get csr |awk '{print$1}' |grep -v ^NAME); do oc --kubeconfig auth/kubeconfig adm  certificate approve $CSR; done
```

Set the edge label and taints

```
oc label node/ip-10-0-229-75.ec2.internal node-role.kubernetes.io/edge=''
oc adm taint node ip-10-0-229-75.ec2.internal node-role.kubernetes.io/edge='':NoSchedule
```

Show nodes

```
$ oc get nodes
NAME                          STATUS   ROLES         AGE     VERSION
ip-10-0-134-72.ec2.internal   Ready    edge,worker   3h39m   v1.24.0+2dd8bb1
ip-10-0-229-75.ec2.internal   Ready    edge,worker   4m45s   v1.24.0+2dd8bb1

$ oc get nodes -l node-role.kubernetes.io/edge='' -o json \
  | jq -r '.items[].metadata.labels["topology.kubernetes.io/zone"]'
us-east-1-nyc-1a
us-east-1-wl1-nyc-wlz-1
```

## Steps to Destroy the Cluster <a name="steps-destroy"></a>

To destroy the resources created, you need to first delete the cluster and then the CloudFormation stacks used to build the network.

- Destroy the cluster

```bash
./openshift-install destroy cluster --log-level=debug
```

- Destroy the Local Zone subnet(s) stack(s)

```bash
aws cloudformation delete-stack --stack-name ${STACK_LZ}
```

- Destroy the Network Stack (VPC)

```bash
aws cloudformation delete-stack --stack-name ${STACK_VPC}
```

## Final notes / Conclusion <a name="review"></a>

The OpenShift cluster can be installed successfully in existing VPC which has subnets in the Local Zones when the tags have been set correctly. So new Machines Sets can be added to any new location.

It was not found any technical blocker to install OpenShift cluster in existing VPC which has subnets in AWS Local Zones, although there is a sort of configuration to be asserted to avoid issues on the default router and ELB Operator.

As described on the steps section, the setup created one Machine Set setting it to unscheduled, creating the `node-role.kubernetes.io/edge=''`. The suggestion to create a custom MachineSet named `edge` was to keep easy the management of resources operating in the Local Zones, which is in general more expensive than the parent zone (the costs are almost 20%). This is a design pattern, the label topology.kubernetes.io/zone can be mixed with taint rules when operating in many locations.

The installation process runs correctly as Day-0 Operation, the only limitation we have found when installing was the ingress controller trying to discover all the public subnets on the VPC to create the service for the default router. The workaround was provided by **tagging** the Local Zone subnets with `kubernetes.io/cluster/unmanaged=true` to avoid the [Subnets Auto Discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/deploy/subnet_discovery/) including the Local Zone Subnets into the default router.

Additionally, when installing the ALB Operator in Day 2 (available on 4.11), the operator requires the cluster tag `kubernetes.io/cluster/<infraID>=.*` to run successfully, although the installer does not require it when installing a cluster in existing VPC[1]. The steps to use ALB on services deployed in Local Zones exploring the low-latency feature are not covered in this document, an experiment creating the operator from source can be found [here](https://github.com/openshift/aws-load-balancer-operator#aws-load-balancer-operator).

Resources produced:

- UPI CloudFormation template for VPC reviewed/updated
- New CloudFormation template to create Local Zone subnets created
- Steps for OpenShift 4.11 installing with support to create compute nodes in Local Zones

Takeaways / Important notes:

- The Local Zone subnets **should** have the tag `kubernetes.io/cluster/unmanaged=true` to avoid the Subnet Discovery for load balancer controller automatically add the subnet located on the Local Zone to the default router.
- The VPC **should** have the tag `kubernetes.io/cluster/<infraID>=shared` to install correctly the AWS ELB Operator (not covered in this post)
- Local Zones do not support Nat Gateways, so there are two options for nodes on Local Zones to access the internet:
  1) Create the private subnet, associating the Local Zones subnet to one parent region route table, then create the machine in the private subnet without mapping public IP.
  2) Use a public subnet on Local Zone and map the public IP to the instance (Machine spec). There are no security constraints as the Security Group rules block all the access outside the VPC (default installation). The NLB has more unrestrictive rules on the security groups. Option 1 should be better until it is not improved. That option also implies extra data transfer fees from the instance located on the Local Zone to the parent zone, in addition to the standard costs to the internet.


## References <a name="references"></a>

- [OpenShift Documentation / Installing a cluster on AWS with network customizations](https://docs.openshift.com/container-platform/4.6/installing/installing_aws/installing-aws-network-customizations.html)
- [OpenShift Documentation / Installing a cluster on AWS using CloudFormation templates /CloudFormation template for the VPC](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-user-infra.html#installation-cloudformation-vpc_installing-aws-user-infra)
- [AWS EKS User Guide/Creating a VPC for your Amazon EKS cluster](https://docs.aws.amazon.com/eks/latest/userguide/creating-a-vpc.html)
- [AWS Load Balancer Controller/Annotations/subnets](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/guide/service/annotations/#subnets)
- [AWS Load Balancer Controller/Subnet Auto Discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/deploy/subnet_discovery/)



<!--METADATA_START

__info__:

> Status: WIP

> [PR](https://github.com/mtulio/mtulio.labs/pull/9):

> [PR Preview](https://mtuliolabs-git-article-ocp-aws-lz-mtulio.vercel.app/articles/ocp-aws-local-zones-day-0/)

> Preview on [Dev.to](#)

METADATA_END-->
