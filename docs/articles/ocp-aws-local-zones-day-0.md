# Install OpenShift in the cloud edge with AWS Local Zones

<!--METADATA_START
> Status: Published
> Published on [Dev.to](https://dev.to/mtulio/install-openshift-in-the-cloud-edge-with-aws-local-zones-3nh0)
METADATA_END-->


This article describes the steps to [install the OpenShift cluster in an existing VPC](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-vpc.html) with Local Zones subnets, extending compute nodes to the edge locations with [MachineSets](https://docs.openshift.com/container-platform/4.10/machine_management/creating_machinesets/creating-machineset-aws.html).

**Table Of Contents**:

- [Summary](#summary)
- [Steps to create the cluster](#steps-create)
  - [Create the network stack](#steps-create-net)
      - [Create the network (VPC and dependencies)](#steps-create-net-vpc)
      - [Create the Local Zones subnet](#steps-create-net-lz-subnet)
  - [Create the installer configuration](#steps-create-config)
  - [Create the installer manifests](#steps-create-manifests)
      - [Create the Machine Set manifest for Local Zones pool](#steps-create-manifests-ms)
      - [Create IngressController manifest to use NLB](#steps-create-manifests-ic)
  - [Update the VPC tag with the InfraID](#steps-create-update-vpc)
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

### Requirements

- OpenShift CLI (`oc`)
- AWS CLI (`aws`)

### Preparing the environment

- Export the common environment variables (change me)

```bash
export VERSION=4.11.0
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
# Using NYC Local Zone (choose yours)
export ZONE_GROUP_NAME="${CLUSTER_REGION}-nyc-1a"
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
    --group-name "${ZONE_GROUP_NAME}" \
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
export CLUSTER_NAME="lzdemo"
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

- Download the <a href="https://raw.githubusercontent.com/mtulio/mtulio.labs/article-ocp-aws-lz/docs/articles/assets/ocp-aws-local-zones-day-0_cfn-net-vpc.yaml" target="_blank">CloudFormation Template for VPC stack</a>


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
export LZ_ZONE_SHORTNAME="nyc1"
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

- Download the [CloudFormation Template for Local Zone subnet stack](https://raw.githubusercontent.com/mtulio/mtulio.labs/article-ocp-aws-lz/docs/articles/assets/ocp-aws-local-zones-day-0_cfn-net-lz.yaml)

- Create the Local Zones subnet stack

```bash
STACK_LZ=${CLUSTER_NAME}-lz-${LZ_ZONE_SHORTNAME}
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
export INSTANCE_TYPE="c5d.2xlarge"

export AMI_ID=$(grep ami \
  openshift/99_openshift-cluster-api_worker-machineset-0.yaml \
  | tail -n1 | awk '{print$2}')

export SUBNET_ID=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_LZ}" \
  | jq -r .Stacks[0].Outputs[0].OutputValue)
```

- Create the Machine Set for `nyc1` nodes

> `publicIp: true` should be set to deploy the node in the public subnet in Local Zone.

> The public IP mapping is used merely to get access to the internet (required), optionally you can modify the network topology to use a private subnet, associating correctly the Local Zone private subnet to a valid route table that has correct routing entries to the internet. Or explore the [disconnected installations](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-restricted-networks-aws-installer-provisioned.html). None of those options will be covered in this article.

```bash
cat <<EOF > openshift/99_openshift-cluster-api_worker-machineset-nyc1.yaml
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
          location: local-zone
          zone_group: ${LZ_ZONE_NAME::-1}
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
          publicIp: true
          tags:
          - name: kubernetes.io/cluster/${CLUSTER_ID}
            value: owned
          userDataSecret:
            name: worker-user-data
EOF
```

#### Create IngressController manifest to use NLB (optional) <a name="steps-create-manifests-ic"></a>

The OCP version used in this article, is using Classic Load Balancer as default router. This option will force to use the NLB by default.

> This section is based on the [official documentation](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-network-customizations.html#nw-aws-nlb-new-cluster_installing-aws-network-customizations).

- Create the IngressController manifest to use NLB by default

```bash
cat <<EOF > manifests/cluster-ingress-default-ingresscontroller.yaml
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  creationTimestamp: null
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

### Update the VPC tag with the InfraID <a name="steps-create-update-vpc"></a>

This step is required when the [ELB Operator (not covered)](https://github.com/openshift/aws-load-balancer-operator) will be installed. It will update the InfraID value on the VPC "cluster tag".

> The following error is expected when installing the ELB Operator without setting the cluster tag: `ERROR setup failed to get VPC ID  {"error": "no VPC with tag \"kubernetes.io/cluster/<infra_id>\" found"}`. Covered bug [this Bug](https://bugzilla.redhat.com/show_bug.cgi?id=2105351).

1. Edit the CloudFormation Template var file of the VPC stack

```bash
cat <<EOF | envsubst > ./stack-vpc-vars.json
[
  {
    "ParameterKey": "ClusterName",
    "ParameterValue": "${CLUSTER_NAME}"
  },
  {
    "ParameterKey": "ClusterInfraId",
    "ParameterValue": "${CLUSTER_ID}"
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

2. Update the stack

```bash
aws cloudformation update-stack \
  --stack-name ${STACK_VPC} \
  --template-body file://${STACK_VPC_TPL} \
  --parameters file://${STACK_VPC_VARS}
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
