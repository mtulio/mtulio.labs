# OpenShift on AWS | Deploy BYO VPC with Multi CIDR

Deploy OpenShift on AWS in BYO VPC with multi-CDIR blocks.

> Those steps are part of investigation. Needs refinement before publish.

## BYO VPC with Multi-CIDR

```sh
INSTALLER_BIN="openshift-install-devel-capa-t"
PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
CLUSTER_NAME=byvpccidr-v1
INSTALL_DIR=${HOME}/openshift-labs/$CLUSTER_NAME
CLUSTER_BASE_DOMAIN=devcluster.openshift.com
SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

REGION=us-east-1
AWS_REGION=$REGION
mkdir -p $INSTALL_DIR && cd $INSTALL_DIR

VPC_CIDR_PRIMARY="10.0.0.0/16"
VPC_CIDR_SECONDARY="10.134.0.0/16"
MACHINE_CIDR="$VPC_CIDR_SECONDARY"

# Create VPC
cp ~/go/src/github.com/mtulio/mtulio.labs-articles/docs/guides/ocp-install-profiles/ocp-aws-byo-vpc-multi-cidr_cfn-vpc.yaml $INSTALL_DIR/vpc.yaml

STACK_VPC="${CLUSTER_NAME}-vpc"
aws cloudformation create-stack --region $REGION  --stack-name ${STACK_VPC} \
  --template-body file://$INSTALL_DIR/vpc.yaml \
  --parameters \
    ParameterKey=VpcCidr,ParameterValue=${VPC_CIDR_PRIMARY} \
    ParameterKey=VpcCidr2,ParameterValue=${VPC_CIDR_SECONDARY}

aws --region $REGION cloudformation wait stack-create-complete --stack-name ${STACK_VPC}
aws --region $REGION cloudformation describe-stacks --stack-name ${STACK_VPC}

# Extract subnet IDs
mapfile -t SUBNETS < <(aws --region $REGION cloudformation describe-stacks   --stack-name "${STACK_VPC}" --query "Stacks[0].Outputs[?OutputKey=='SubnetsIdsForCidr2'].OutputValue" --output text | tr ',' '\n')

echo ${SUBNETS[@]}

# Create IC
echo "> Creating install-config.yaml"
# Create a single-AZ install config
mkdir -p ${INSTALL_DIR}
cat <<EOF | envsubst > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${CLUSTER_BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
featureSet: CustomNoUpgrade
featureGates:
- ClusterAPIInstall=true
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

OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.17.0-rc.1-x86_64" \
$INSTALLER_BIN create cluster --dir $INSTALL_DIR --log-level=debug
```
