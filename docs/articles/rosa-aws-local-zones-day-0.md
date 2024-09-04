# [incomplete/limited/draft] Extend ROSA to the edge with Local Zones and Wavelenght

> STATUS NOTE: Article not finished as ROSA does not support to create Machine Sets through `oc` cli, and ACM or `rosa create machinepool` does not support edge zones (error below)

> Article will wait for ACM support to specify zones

## Create the cluster

```bash
CLUSTER_NAME="edge-demo2"
CLUSTER_REGION="us-east-1"
CLUSTER_VERSION="4.10.20"
COMPUTE_TYPE="m5.xlarge"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

$ rosa create account-roles --mode auto --yes --prefix "${CLUSTER_NAME}"


```

- Create cluster

```bash
rosa create cluster --cluster-name "${CLUSTER_NAME}" --sts \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-Installer-Role" \
  --support-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-Support-Role" \
  --controlplane-iam-role "arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-ControlPlane-Role" \
  --worker-iam-role "arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-Worker-Role" \
  --region "${CLUSTER_REGION}" \
  --version "${CLUSTER_VERSION}" \
  --multi-az \
  --compute-nodes 3 \
  --compute-machine-type "${COMPUTE_TYPE}" \
  --machine-cidr 10.0.0.0/16 \
  --service-cidr 172.30.0.0/16 \
  --pod-cidr 10.128.0.0/14 \
  --host-prefix 23 \
  --yes
```

- removidos
```
  --operator-roles-prefix edge-rosa-f0c4 \
```

- Create operator roles

```
rosa create operator-roles --cluster "${CLUSTER_NAME}" --yes -m auto
```

- Create OIDC
```
rosa create oidc-provider --cluster "${CLUSTER_NAME}" --mode auto --yes
```

- Check the cluster
```
rosa describe cluster --cluster "${CLUSTER_NAME}"
```

- Create `admin` user
> Note the login command to be used on the next step
```bash
rosa create admin --cluster $CLUSTER_NAME
```

- Login to cluster

```
oc login <API_URL> --username cluster-admin --password <ADMIN_PASS>
```

## Setup VPC to the edge locations

### Network Design

As we installed the ROSA cluster in `--multi-az`, the default installation will create one VPC in 3 subnets with netmask `/19` each one.

For edge locations we will create subnets with capacity of 1024 address (networks `/22`), allowing the VPC to be extended up to 8 more subnets starting from `10.0.224.0/22` - considering the VPC CIDR `10.0.0.0/24`.

### Opt-in the zone groups

> https://us-east-1.console.aws.amazon.com/ec2/v2/home?region=us-east-1#Settings:tab=zones


### Discovery the VPC resource identifiers

- Get the VPC information (created by rosa installer)

```bash
# Discovery the Infrastructure Name
export INFRA_NAME=$(oc get infrastructure cluster -o jsonpath="{.status.infrastructureName}")

# Discovery the VPC ID
export VPC_NAME="${INFRA_NAME}-vpc"
export VPC_ID=$(aws ec2 describe-vpcs \
    --filters Name=tag:Name,Values=${VPC_NAME} \
    --query 'Vpcs[].VpcId' --output text)

# Discovery the Route Table ID (used to the edge public Subnet)
export VPC_RTB_PUB_NAME="${INFRA_NAME}-public"
export VPC_RTB_PUB=$(aws ec2 describe-route-tables \
    --filters Name=tag:Name,Values=${VPC_RTB_PUB_NAME} \
    --query 'RouteTables[].RouteTableId' \
    --output text)
```

### Setup NYC Local Zone subnet

- Opt-in the Local Zone group

```bash
export AZ_GROUP_LZ_NYC="${CLUSTER_REGION}-nyc-1"
export AZ_NAME_LZ_NYC="${CLUSTER_REGION}-nyc-1a"
export AZ_NAME_LZ_NYC_SHORT="nyc-lz"
export VPC_SUBNET_CIDR_LZ="10.0.224.0/22"

aws ec2 modify-availability-zone-group \
    --group-name "${AZ_GROUP_LZ_NYC}" \
    --opt-in-status opted-in
```

- Create the CloudFormation template variables

```bash
cat <<EOF | envsubst > ./stack-edge-vars-${AZ_NAME_LZ_NYC}.json
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
    "ParameterValue": "${AZ_NAME_LZ_NYC}"
  },
  {
    "ParameterKey": "LocalZoneNameShort",
    "ParameterValue": "${AZ_NAME_LZ_NYC_SHORT}"
  },
  {
    "ParameterKey": "PublicSubnetCidr",
    "ParameterValue": "${VPC_SUBNET_CIDR_LZ}"
  }
]
EOF
```

- Create the subnet

```bash
STACK_LZ=${CLUSTER_NAME}-edge-${AZ_NAME_LZ_NYC}
STACK_LZ_TPL="${PWD}/ocp-aws-local-zones-day-0_cfn-net-lz.yaml"
STACK_LZ_VARS="${PWD}/stack-edge-vars-${AZ_NAME_LZ_NYC}.json"
aws cloudformation create-stack \
  --stack-name ${STACK_LZ} \
  --template-body file://${STACK_LZ_TPL} \
  --parameters file://${STACK_LZ_VARS}
```

- Check the status (wait to be finished)

```bash
aws cloudformation describe-stacks --stack-name ${STACK_LZ}
```

### Setup NYC Wavelenght subnet

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

- Create the CloudFormation template variables

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

- Create the subnet

```bash
STACK_WL=${CLUSTER_NAME}-edge-wl-${AZ_NAME_WL_NYC}
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


## Create the MachineSets

ROSA does not support to create the MachinePool[1] into the new AZs created manually[2], thus we need to create the Machine Set custom resource manually[3].

> [1] [ROSA Documentation: Managing compute nodes](https://docs.openshift.com/rosa/rosa_cluster_admin/rosa_nodes/rosa-managing-worker-nodes.html#rosa-managing-worker-nodes)

> [2] Error creating machinepool: `E: Availability zone 'us-east-1-nyc-1a' doesn't belong to the cluster's availability zones`

> [3] [Creating a machine set on AWS](https://docs.openshift.com/container-platform/4.10/machine_management/creating_machinesets/creating-machineset-aws.html)


### Create Machine Set on the Local Zone subnet

Due the amount of fields to be changed, we will use `envsubst` instead of `kustomize`.

- Download the Machine Set template with the environment variables reference

- Export the variables to be substituted:

```bash
export CLUSTER_INFRA_NAME=$(oc get infrastructures cluster \
  -o jsonpath="{.status.infrastructureName}")
export CLUSTER_REGION=$(oc get infrastructures cluster \
  -o jsonpath="{.status.platformStatus.aws.region}")
export AMI_ID=$(oc get machinesets ${CLUSTER_INFRA_NAME}-worker-us-east-1a \
  -n openshift-machine-api -o jsonpath="{.spec.template.spec.providerSpec.value.ami.id}")

export ZONE_NAME="${AZ_NAME_LZ_NYC}"
export SUBNET_NAME="${CLUSTER_NAME}-public-${AZ_NAME_LZ_NYC_SHORT}-1"
export LOCATION_TYPE=local-zone
export DISK_SIZE=120
export DISK_TYPE=gp2
export INSTANCE_TYPE=t3.xlarge
export CARRIER_GW_ENABLED=false
```

- Create the MachineSet resource

```bash
cat ocp-aws-edge-machine-set.yaml.tpl | envsubst | oc create -f -
```

**ERROR: lab stopped, the ROSA does not allow to create custom MachineSet**
```
Error from server (Prevented from accessing Red Hat managed resources. This is in an effort to prevent harmful actions that may cause unintended consequences or affect the stability of the cluster. If you have any questions about this, please reach out to Red Hat support at https://access.redhat.com/support): error when creating "STDIN": admission webhook "regular-user-validation.managed.openshift.io" denied the request: Prevented from accessing Red Hat managed resources. This is in an effort to prevent harmful actions that may cause unintended consequences or affect the stability of the cluster. If you have any questions about this, please reach out to Red Hat support at https://access.redhat.com/support
```

### Create Machine Set on the Wavelength zone subnet

> TODO

## Test it

> TODO

## Final notes / Conclusion

> TODO

ROSA Network:
- On the version that this article has been written, the ROSA installer tries to fill the entire VPC CIDR on the subnets, so you can't create new subnets in the default installation. So the network design should be something to be planned before installing the cluster to be used with edge network.


