# OpenShift | AWS | Steps to Create a node manually

Steps:

- Create the subnet

```
CLUSTER_ID=mrb-ffj2l
VPC_NAME=${CLUSTER_ID}-vpc
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=${VPC_NAME} |jq -r .Vpcs[0].VpcId)
REGION=us-east-1
AZ_NAME=${REGION}-bos-1a
SUBNET_NAME=${CLUSTER_ID}-public-us-east-1-bos-1a
SUBNET_CIDR="10.0.208.0/20"

cat <<EOF | envsubst > subnet-new.json
{
    "TagSpecifications": [
        {
            "ResourceType": "subnet",
            "Tags": [
                {
                    "Key": "Name",
                    "Value": "$SUBNET_NAME"
                }
            ]
        }
    ],
    "AvailabilityZone": "$AZ_NAME",
    "VpcId": "$VPC_ID",
    "CidrBlock": "$SUBNET_CIDR"
}
EOF

aws ec2 create-subnet --cli-input-json "$(cat subnet-new.json)"

```

- Check instance availability

```
$ aws ec2 describe-instance-type-offerings --location-type availability-zone --filters Name=location,Values=${AZ_NAME} --region ${REGION}
```

- Create the instance
```
# CHANGE_ME:
REGION="us-east-1"
# Subnet in us-east-1-bos-1a
SUBNET="subnet-XX"
TYPE="t3.xlarge"

# AUTO
USERDATA="/tmp/worker.ign"
DISK_SIZE="120"

NAME="$(oc get machines -n openshift-machine-api  -l machine.openshift.io/cluster-api-machine-role=worker -o json | jq -r '.items[0].metadata.name' | awk -F 'east-1' '{print$1"east-1-bos-1a"}')"

# Get user-data
oc get secret -n openshift-machine-api $(oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=worker -o json |jq -r '.items[0].spec.providerSpec.value.userDataSecret.name') -o json |jq -r .data.userData |base64 -d > ${USERDATA}

IMAGE="$(oc get machines -n openshift-machine-api  -l machine.openshift.io/cluster-api-machine-role=worker -o json |jq -r '.items[0].spec.providerSpec.value.ami.id')"

SECURITY_GROUPS="$(oc get machines -n openshift-machine-api  -l machine.openshift.io/cluster-api-machine-role=worker -o json |jq -r '.items[0].spec.providerSpec.value.securityGroups[0].filters[0].values[0]')"
SG_ID=$(aws ec2 describe-security-groups --filters Name=tag:Name,Values=$SECURITY_GROUPS | jq  -r .SecurityGroups[0].GroupId)

PROFILE_NAME="$(oc get machines -n openshift-machine-api  -l machine.openshift.io/cluster-api-machine-role=worker -o json | jq -r '.items[0].spec.providerSpec.value.iamInstanceProfile.id')"


K8S_TAG_KEY="$(oc get machines -n openshift-machine-api  -l machine.openshift.io/cluster-api-machine-role=worker -o json |jq -r '.items[0].spec.providerSpec.value.tags[0].name')"

aws ec2 run-instances                     \
    --region $REGION                      \
    --image-id $IMAGE                     \
    --instance-type $TYPE                 \
    --subnet-id $SUBNET                   \
    --security-group-ids $SG_ID \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME}},{Key=${K8S_TAG_KEY},Value=owned}]" \
    --block-device-mappings "VirtualName=/dev/nvme0n1,DeviceName=/dev/xvda,Ebs={VolumeSize=${DISK_SIZE}}" \
    --user-data "file://${USERDATA}" \
    --iam-instance-profile Name=${PROFILE_NAME}

```
