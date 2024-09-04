# OpenShift on AWS | Deploy BYO VPC with Multi CIDR

Deploy OpenShift on AWS in BYO VPC with multi-CDIR blocks.

> Those steps are part of investigation. Needs refinement before publish

## BYO VPC with Multi-CIDR

```sh
INSTALLER_BIN="./openshift-install"
PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
CLUSTER_NAME=byvpccidr-v0
INSTALL_DIR=${HOME}/openshift-labs/$CLUSTER_NAME
CLUSTER_BASE_DOMAIN=devcluster.openshift.com
SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

REGION=us-east-1
AWS_REGION=$REGION
mkdir -p $INSTALL_DIR && cd $INSTALL_DIR

MACHINE_CIDR="10.115.0.0/16"
#MACHINE_CIDR="10.190.0.0/16"

# Create VPC
cp ~/go/src/github.com/mtulio/mtulio.labs-articles/docs/guides/ocp-aws-byo-vpc-multi-cidr_cfn-vpc.yaml $INSTALL_DIR/vpc.yaml

STACK_VPC="${CLUSTER_NAME}-vpc"
aws cloudformation create-stack --region $REGION  --stack-name ${STACK_VPC} \
  --template-body file://$INSTALL_DIR/vpc.yaml \
  --parameters \
    ParameterKey=VpcCidr2,ParameterValue=${MACHINE_CIDR}

aws --region $REGION cloudformation wait stack-create-complete --stack-name ${STACK_VPC}
aws --region $REGION cloudformation describe-stacks --stack-name ${STACK_VPC}

# Extract subnet IDs
mapfile -t SUBNETS < <(aws --region $REGION cloudformation describe-stacks   --stack-name "${STACK_VPC}" --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetIds'].OutputValue" --output text | tr ',' '\n')

echo ${SUBNETS[@]}

mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws --region $REGION cloudformation describe-stacks   --stack-name "${STACK_VPC}" --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetIds'].OutputValue" --output text | tr ',' '\n')

echo ${SUBNETS[@]}

# Create IC
echo "> Creating install-config.yaml"
# Create a single-AZ install config
mkdir -p ${INSTALL_DIR}
cat <<EOF | envsubst > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${CLUSTER_BASE_DOMAIN}
featureSet: CustomNoUpgrade
featureGates:
- ClusterAPIInstall=true
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${REGION}
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)
    userTags:
      x-red-hat-clustertype: installer
      x-red-hat-managed: "true"
networking:
  machineNetwork:
  - cidr: ${MACHINE_CIDR}
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.16.0-ec.6-x86_64" \
$INSTALLER_BIN create cluster --dir $INSTALL_DIR --log-level=debug
```

