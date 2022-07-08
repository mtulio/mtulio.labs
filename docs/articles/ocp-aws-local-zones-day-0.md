# Install OpenShift cluster in the edge with AWS Local Zones

This article describes the steps to install the OpenShift cluster in an existing VPC with Local Zones subnets.

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

### Requirements and considerations

- OpenShift CLI (`oc`)
- AWS CLI (`aws`)

### Preparing the environment

- Export the common environment variables (change me)

```bash
export VERSION=4.11.0-fc.0
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

- Download the [CloudFormation Template for VPC stack](./assets/ocp-aws-local-zones-day-0_cfn-net-vpc.yaml)

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

- Download the [CloudFormation Template for Local Zone subnet stack](./assets/ocp-aws-local-zones-day-0_cfn-net-lz.yaml)

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

> Adapt it as your usage, the requirement is to set the field `platform.aws.subnets` with the subnet IDs

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

export AMI_ID=$(grep ami openshift/99_openshift-cluster-api_worker-machineset-0.yaml | tail -n1 |awk '{print$2}')
export SUBNET_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_LZ}" | jq -r .Stacks[0].Outputs[0].OutputValue)
```

- Create the Machine Set for `nyc1` nodes

> `publicIp: true` will be used as the Local Zone subnet is public.

```bash
cat <<EOF > manifests/99_openshift-cluster-api_worker-machineset-nyc1.yaml
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

> The `4.11.0-fc.0` still installing Classic LB. This option will force to use the NLB by default.

> Optional as the intention in this article is to validate the default IPI behavior. NLB is nice to have by default, should be tested either.

> Section based on the [official documentation](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-network-customizations.html#nw-aws-nlb-new-cluster_installing-aws-network-customizations).

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

- Update the VPC cluster tag

> Required when installing the ELB Operator: `ERROR setup failed to get VPC ID  {"error": "no VPC with tag \"kubernetes.io/cluster/<infra_id>\" found"}`

> Q. to NE: Is it a bug? Should it be required? Can we use VPCs owned by subnets where the cluster was installed?

1. Edit the VPC var file

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
$ oc get machines -n openshift-machine-api -l machine.openshift.io/zone=us-east-1-nyc-1a
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

## Tests performed <a name="tests"></a>

<!--
Tests log:

- 1: Install a cluster with LB subnets tagging. Result: fail, the Controller discoverer added the LZ subnet to the list to create the IG
- 2: Install a cluster with LB subnets tagging on the zones on the parent region and `unmanaged` to the LZ subnet. Result: success. The discoverer ignored the LZ subnet
- 3A: Install a cluster with no LB subnets tagging, and unmanaged on LZ subnet: Result: Succes
- 3B: Install the ELB Operator on the LZ subnet which has an `unmanaged` tag. Result: Controller is not finding the VPC tagged by cluster tag
- 4: Install with tags: Subn for LB, LZ Unmanaged, VPC cluster shared. Results: OK. There were wrong credentials granted to the controller, so the tag for VPC may be useless. Need to run more tests
- 5: Install with tags: Subn for LB. Results: Success
- 6: Install #4 + using NLB as default. Result: Success. The NLB has more unrestrictive security group rules, installing the compute nodes in the public subnets could expose the node ports directly to the internet.
- 7: Install with tags on Subn for LZ, No LB tags on All Subn. Results: Success. We don't need the Sub ELB tags on the parent zone, we need the unmanaged on the LZ zone
- 8: Install with tag kubernetes.io/role/elb=0 for LZ, and no tags for all Subn. Results: Failed. The Ingress does not look to the ELB tag and tries to add the subnet to the default router lb. It was fixed only when I added kubernetes.io/cluster/unmanaged=true tag (It is OK for provided network, but can be a problem on installer)
- 9: Install with LB tags on parent region, and no tags on LZ subnet. Result: failed
- 10: VPC Tag, LZ unmanaged tag. Result: Success
- 11: Check if the installer modifies the subnets to cluster tags when installing in existing VPCs
-->

A quick review of the goal of this post:

- install an OpenShift cluster successfully in existing VPC which has, at least one, subnet on the Local Zone
- Make sure all the cluster operators has been finished without issues
- Make sure the Local Zone subnet can be used further deploying ingress exclusively for it using AWS ELB Operator (Local Zone supports only Application Load Balancers)

Said that, several combinations of tagging were executed to find the correct approach to install a cluster in existing VPC without falling into the Load Balancer controller add the Local Zone subnet automatically to the default router - which should be located only in the subnets in the parent region (non-edge/Local Zones).

The following matrix was created to document all the tests performed and the results:

| #   | VPC tag | ELB tag | LZ tag | Res Install | Res ELB Op | Desc |
| --  | --        | --        | --          | --          | --          | -- |
| 1   | --        | X         | --          | Fail        | NT          | `ERR#1` |
| 2   | --        | X         | X           | Success     | NT          | -- |
| 3A  | --        | --        | X           | Success     | NT          | -- |
| 3B  | --        | --        | X           | Success     | Failed      | `ERR#2`: ELB Oper expects cluster tag on VPC |
| 4   | X         | X         | X           | Success     | Success     | Needs retest, creds issues |
| 5   | X         | X         | X           | Success     | Success     | -- |
| 6   | X         | X         | X           | Success     | Success     | NLB as default ingress |
| 7   | --        | --        | X           | Success     | NT          | -- |
| 8   | --        | --        | X*          | Failed      | NT          | `ERR#1`: `*elb=0`: IG Controller ignored the '0' value |
| 9   | X         | X         | --          | Failed      | NT          | `ERR#1`: Controller tries to add the LZ Subnet |
| 10  | X         | --        | X           | Success | Success | -- |

- `VPC tag` is the cluster tag created on the VPC `kubernetes.io/cluster/<infraID>=.*`
- `ELB tag` is the Load Balancer tags created on the subnets on the parent zone (only) used by [Controler Subnet Auto Discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/deploy/subnet_discovery/): `kubernetes.io/role/elb=1` or `kubernetes.io/role/internal-elb=1`
- `LZ tag` is the "unmanaged" cluster tag set on the Local Zone subnet (only): `kubernetes.io/cluster/unmanaged=true`
- `Res Install` is the result of the installer execution
- `Res ELB Oper` is the result of the setup of ALB Operator and provisioning the ingress in the Local Zone Subnet (only)


`ERR#1`: Error when KCM tries to add the Local Zone subnet (`oc get co`):
```
ingress                                                  False       True          True       92s     The "default" ingress controller reports Available=False: IngressControllerUnavailable: One or more status conditions indicate unavailable: LoadBalancerReady=False (SyncLoadBalancerFailed: The service-controller component is reporting SyncLoadBalancerFailed events like: Error syncing load balancer: failed to ensure load balancer: ValidationError: You cannot have any Local Zone subnets for load balancers of type 'classic'...
```

`ERR#2`: ELB Controller cannot find the VPC cluster tag (`oc logs pod/aws-load-balancer-operator-controller-manager-[redacted] -n aws-load-balancer-operator`)
```
1.6572192750063934e+09	ERROR	setup	failed to get VPC ID	{"error": "no VPC with tag \"kubernetes.io/cluster/lzdemo-b88kd\" found"}
main.main
	/workspace/main.go:133
runtime.main
	/usr/local/go/src/runtime/proc.go:255
```

### Expectations

For default router/ingress/controller:

- Should not auto discovery all the subnets on the VPC when the subnets has been set on the install-config.yaml
- Should not auto discovery all the subnets on the VPC when the `kubernetes.io/role/elb=1` has been added to public subnets
- Should not try to add subnets not supported (Local Zones, Wavelength) to the technology used by Load Balancer (CLB/NLB) on the ingress
- The controller auto discover ignores the `kubernetes.io/role/elb=0`, so we can specify what subnets we would not like to be added/used by Load Balancer

For the AWS ELB Operator/Controller:

- Must not expect cluster tag set on the VPC as it is not required when installing clusters in existing VPCs. [See the documentation fragment](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-vpc.html#installation-custom-aws-vpc-requirements_installing-aws-vpc).
- Should not add all the nodes on the target groups, only the nodes which are running the service pods, or compute nodes which are in the zones of ALB. It will: 1) decrease the number of Health checks arriving to nodes not running the application; 2) decrease the number of unused nodes on the targets

For the uninstalling:

- Any ELB Created by ALB Operator should be deleted on the installer destroy flow
- Any SGs created to attach to ELB should be deleted


## Final notes / Conclusion <a name="review"></a>

The OpenShift cluster can be installed successfully in existing VPC which has subnets in the Local Zones when the tags have been set correctly. So new Machines Sets can be added to any new location.

It was not found any technical blocker to install OpenShift cluster in existing VPC which has subnets in AWS Local Zones, although there is a sort of configuration to be asserted to avoid issues on the default router and ELB Operator.

As described on the steps section, the setup created one Machine Set setting it to unscheduled, creating the node-role.kubernetes.io/edge=’’. The suggestion to create a custom MachineSet named “edge” was to keep easy the management of resources operating in the Local Zones, which is in general more expensive than the parent zone (the costs are almost 20%). This is a design pattern, the label topology.kubernetes.io/zone can be mixed with taint rules when operating in many locations.

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
