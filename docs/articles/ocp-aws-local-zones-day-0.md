<!--METADATA_START-->

# [review] Install OpenShift cluster on the edge with AWS Local Zones

__info__:

> Status: WIP

> [PR to Collab](): 

> [PR Preview]()

> Preview on [Dev.to](#)

<!--METADATA_END-->

> TODO/WIP

Goal: Install one OpenShift cluster..
- in an existing network (VPC)
- the VPC should have at least one Local Zone subnet created
- the installation should be finished successfully

**What you need to know**

> TODO

- Installing a cluster with network customizations: https://docs.openshift.com/container-platform/4.6/installing/installing_aws/installing-aws-network-customizations.html


## **Reference Architecture**

> TODO

## **Requirements and considerations**

> TODO

## **Preparing the environment**

> TODO

- Export common environment variables (change me)

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

### Create the network stack

> TODO

- Create the Network (VPC, subnets, Nat Gateways) in the parent/main zone
- Create the subnet on the Local Zone location

#### Main Zones subnets

<!--
> WIP

References:
- OpenShift UPI, Network Stack (VPC, Network and R53): https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-user-infra.html#installation-cloudformation-vpc_installing-aws-user-infra
- EKS VPC Guide: https://docs.aws.amazon.com/eks/latest/userguide/creating-a-vpc.html
- NLB Controller subnet: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/guide/service/annotations/#subnets
- NLB Discovery by tags> https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/deploy/subnet_discovery/
-->

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
    "ParameterKey": "ClusterInfraId",
    "ParameterValue": ""
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

- Wait for the stack to be finished (`StackStatus=CREATE_COMPLETE`)

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

#### Local Zones subnet

- Set the environment the variables to create the Local Zone subnet

```bash
export VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId").OutputValue' )
export VPC_RTB_PUB=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PublicRouteTableId").OutputValue' )

export CLUSTER_REGION="us-east-1"
export LZ_ZONE_NAME="${CLUSTER_REGION}-nyc-1a"
export LZ_ZONE_SHORTNAME="nyc1"
export LZ_ZONE_CIDR="10.0.128.0/20"
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
    "ParameterKey": "PublicRouteTable",
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

- Create the Local Zone subnet stack

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

- (optional) Update if you need

```bash
aws cloudformation update-stack \
  --stack-name ${STACK_LZ} \
  --template-body file://${STACK_LZ_TPL} \
  --parameters file://${STACK_LZ_VARS}
```

Repeat those steps for each location.

## Create the installer configuration

- Set tje vars to be used on installer configuration

```bash
export BASE_DOMAIN="devcluster.openshift.com"

# Parent zone subnets only
mapfile -t SUBNETS < <(aws cloudformation describe-stacks --stack-name "${STACK_VPC}" |jq -r '.Stacks[0].Outputs[0].OutputValue' |tr ',' '\n')
mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks --stack-name "${STACK_VPC}" |jq -r '.Stacks[0].Outputs[1].OutputValue' |tr ',' '\n')
```

- Create the `install-config.yaml` - setting the subnets recently created (parent zone only)

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

### Create the installer manifests

- Create manifests

```bash
./openshift-install create manifests
```

- Update the VPC cluster tag

> Required when installing the ELB Operator: `ERROR	setup	failed to get VPC ID	{"error": "no VPC with tag \"kubernetes.io/cluster/lzdemo-ds2dn\" found"}`
> Q. to NE: Is it a bug? Should be required?
> Q. to Installer: Is it impact the destroy flow?

0. Get the InfraID

```bash
export CLUSTER_ID="lzdemo-ds2dn"
```

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


### Create the Machine Set manifest

- Set the variables used to create the Machine Set

```bash
export CLUSTER_ID=$(grep infrastructureName:  manifests/cluster-infrastructure-02-config.yml |awk '{print$2}')
export AMI_ID=$(grep ami openshift/99_openshift-cluster-api_worker-machineset-0.yaml |tail -n1 |awk '{print$2}')
export INSTANCE_TYPE="c5d.2xlarge"
export SUBNET_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_LZ}" |jq -r .Stacks[0].Outputs[0].OutputValue)
```

- Create the Machine Set for nyc1

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


### Use NLB on Ingress Controller (optional?)

> `4.11.0-fc.0` still install Classic LB. This option will force to use NLB by default

Reference: https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-network-customizations.html#nw-aws-nlb-new-cluster_installing-aws-network-customizations

Is it possible to specify the subnet when creating the ingress controller?

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

## Install a cluster

- create cluster

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

- Cluster operatos summary

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

- Machines

```bash
$ oc get machines -n openshift-machine-api -l machine.openshift.io/zone=us-east-1-nyc-1a
NAME                                       PHASE     TYPE          REGION      ZONE               AGE
lzdemo-ds2dn-edge-us-east-1-nyc-1a-6645q   Running   c5d.2xlarge   us-east-1   us-east-1-nyc-1a   12m
```

- Nodes in Local Zone filtering by custom labels defined on Machine Set (location, zone_group)

```bash
$ oc get nodes -l location=local-zone
NAME                           STATUS   ROLES         AGE   VERSION
ip-10-0-143-104.ec2.internal   Ready    edge,worker   11m   v1.24.0+beaaed6
```

## Destroy

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


## Conclusion

> TODO/WIP

Goal review: Install one OpenShift cluster...DONE

Resources produced:
- UPI CloudFormation template for VPC reviewed/updated
- New CloudFormation template to create Local Zone subnets created
- Steps for: OpenShift 4.11 installing with support of compute nodes in Local Zones

Takeaways / Important notes:
- All the subnets should be tagged properly with the correct tag to be discovered by Ingress Controller
- The LocalZone subnets **should** have the tag cluster to "unmanaged"
- Local Zones does not support Nat Gateways, so there are two options to nodes on Local Zones access the internet:
  1) Use public subnet on Local Zone and map public IP (Machine spec). There's no security constraints here as the Security Group rules blocks all the access outside the VPC.
  2) Create the private subnet, associating the Local Zone subnet to the main zone's route table, then create the machine in the private subnet.

Tests performed:
- Install a cluster with LB subnets tagging. Result: fail, the Controller discoverer added the LZ subnet to the list to create the IG
- Install a cluster with LB subnets tagging on the zones on parent region, and unmanaed to the LZ subnet. Result: success. The discoverer ignored the LZ subnet
- Install a cluster with no LB subnets tagging, and unmanaged on LZ subnet: Result: TODO
- Install the ELB Operator on LZ subnet which has unmanaged tag. Result: TODO

## References

> TODO/WIP

- [OpenShift Documentation / Installing a cluster on AWS with network customizations](https://docs.openshift.com/container-platform/4.6/installing/installing_aws/installing-aws-network-customizations.html)
- [OpenShift Documentation / Installing a cluster on AWS using CloudFormation templates /CloudFormation template for the VPC](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-user-infra.html#installation-cloudformation-vpc_installing-aws-user-infra)
- [AWS EKS User Guide/Creating a VPC for your Amazon EKS cluster](https://docs.aws.amazon.com/eks/latest/userguide/creating-a-vpc.html)
- [AWS Load Balancer Controller/Annotations/subnets](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/guide/service/annotations/#subnets)
- [AWS Load Balancer Controller/Subnet Auto Discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/deploy/subnet_discovery/)
