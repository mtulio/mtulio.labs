# Deploying OpenShift on AWS bringing Your Own Infrastructure

This guide describes how to install am OpenShift cluster on AWS using custom Encrypted AMI, encrypted with a KMS Customer Managed Key (CMK).

### Installing dependencies

- [Install `awscli` v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- Install `yq`:
```sh
yq_version=v4.34.2
yq_bin_arch=yq_linux_amd64
yq_url="https://github.com/mikefarah/yq/releases/download/${yq_version}/${yq_bin_arch}"
BIN_YQ=${PWD}/yq

wget -O ${BIN_YQ} ${yq_url} && chmod +x ${BIN_YQ}
```
- Download `openshift-install`

```sh
export OCP_VERSION=4.18.8
export OCP_ARCH=x86_64
export OCP_RELEASE=quay.io/openshift-release-dev/ocp-release:${OCP_VERSION}-${OCP_ARCH}

oc adm release extract -a $PULL_SECRET_FILE --tools ${OCP_RELEASE}
tar xvzf openshift-install-linux-${OCP_VERSION}.tar.gz
tar xvzf ccoctl-linux-${OCP_VERSION}.tar.gz
```

## Choose and Deploy your BYO infrastructure <a name="byo-infra"></a>

### BYO Encrypted AMI

This setup will ensure each step runs with minimum permission, using the identities for different agents. Those are agents:
- Identity used to create/mirror and encrypted the AMI
- Identity used to executed ccoctl - create IAM Roles
- Identity used to executed openshift-install


Prerequisites:

- Create IAM User to setup KMS
- Create KMS Key
- Create IAM User to setup AMI
- Mirror the AMI ID to your Account encrypting with custom KMS Key

```sh
export AWS_REGION=us-east-1
export INFRA_REF="RFE-5733v6"

WORKDIR=$PWD/${INFRA_REF}
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
INSTALL_DIR=${WORKDIR}/install
mkdir -p ${INSTALL_DIR}

export AWS_SHARED_CREDENTIALS_FILE=${WORKDIR}/credentials
IAM_USER_KMS="${INFRA_REF}-usr-kms"
IAM_USER_AMI="${INFRA_REF}-usr-ami"
IAM_USER_CCOCTL="${INFRA_REF}-usr-ccoctl"
IAM_USER_INST="${INFRA_REF}-usr-inst"

# create_user_and_keys creates user, policy and credentials for each user
function create_user_and_keys() {
  local user_name=$1; shift
  local policy_doc=$1;
  
  AWS_SHARED_CREDENTIALS_FILE=$HOME/.aws/credentials aws iam create-user --user-name $user_name
  echo "[${user_name}] User Created!"

  # generate keys
  AWS_SHARED_CREDENTIALS_FILE=$HOME/.aws/credentials aws iam create-access-key --user-name $user_name > ./${user_name}-keys.json
  echo "[${user_name}] User's Credentials Extracted!"

  cat <<EOF >> ${AWS_SHARED_CREDENTIALS_FILE}

[${user_name}]
aws_region = ${AWS_REGION}
aws_access_key_id = $(jq -r .AccessKey.AccessKeyId ./${user_name}-keys.json)
aws_secret_access_key = $(jq -r .AccessKey.SecretAccessKey ./${user_name}-keys.json)

EOF
  echo "[${user_name}] ${AWS_SHARED_CREDENTIALS_FILE} updated!"

  # Creating custom policy to prevent size limitations with inline policy
  AWS_SHARED_CREDENTIALS_FILE=$HOME/.aws/credentials aws iam create-policy --policy-name "${user_name}" --policy-document file://${policy_doc}
  echo "[${user_name}] Policy Created!"

  AWS_SHARED_CREDENTIALS_FILE=$HOME/.aws/credentials aws iam attach-user-policy --user-name "${user_name}" --policy-arn arn:aws:iam::${AWS_ACCOUNT}:policy/${user_name}
  echo "[${user_name}] Policy Attached to user!"

}

# IAM User to manipulate KMS
cat <<EOF > ./${IAM_USER_KMS}-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "KMSKeyManagement",
            "Effect": "Allow",
            "Action": [
                "kms:CreateKey",
                "kms:DescribeKey",
                "kms:ListKeys",
                "kms:ListAliases",
                "kms:CreateAlias",
                "kms:DeleteAlias",
                "kms:EnableKey",
                "kms:DisableKey",
                "kms:ScheduleKeyDeletion",
                "kms:CancelKeyDeletion",
                "kms:TagResource",
                "kms:UntagResource",
                "kms:UpdateKeyDescription",
                "kms:UpdateAlias"
            ],
            "Resource": "*"
        },
        {
            "Sid": "KMSPolicyModification",
            "Effect": "Allow",
            "Action": [
                "kms:PutKeyPolicy",
                "kms:GetKeyPolicy",
                "kms:ListKeyPolicies"
            ],
            "Resource": "*"
        }
    ]
}
EOF

create_user_and_keys "${IAM_USER_KMS}" "./${IAM_USER_KMS}-policy.json"


# Create the key
AWS_PROFILE=$IAM_USER_KMS aws kms create-key --region ${AWS_REGION} \
  --description "Devel Key for ${INFRA_REF}" \
  --key-usage ENCRYPT_DECRYPT \
  --customer-master-key-spec SYMMETRIC_DEFAULT \
  | tee -a ${INFRA_REF}-kms-key.json

export KMS_KEY_ID=$(jq -r .KeyMetadata.KeyId ./${INFRA_REF}-kms-key.json)
export KMS_KEY_ALIAS=${INFRA_REF}
export KMS_KEY_ARN="arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT}:key/${KMS_KEY_ID}"

AWS_PROFILE=$IAM_USER_KMS aws kms create-alias --region ${AWS_REGION} \
  --alias-name alias/${KMS_KEY_ALIAS} \
  --target-key-id ${KMS_KEY_ID}
 

# Create the IAM User to operate/mirror AMI
cat <<EOF > ./${IAM_USER_AMI}-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AMIOperations",
            "Action": [
                "ec2:CopyImage",
                "ec2:DescribeImages",
                "ec2:ModifyImageAttribute"
            ],
            "Effect": "Allow",
            "Resource": "*"
        },
        {
            "Sid": "KMSKeyUsage",
            "Effect": "Allow",
            "Action": [
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:GenerateDataKey",
                "kms:DescribeKey"
            ],
            "Resource": "${KMS_KEY_ARN}"
        }
    ]
}
EOF
create_user_and_keys "${IAM_USER_AMI}" "./${IAM_USER_AMI}-policy.json"

# Ensuring the user has permissions to the KMS Resource Policy
AWS_PROFILE=$IAM_USER_KMS aws kms get-key-policy --key-id $KMS_KEY_ID --query Policy --output text | jq '.' > ./kms-policy.json

# TODO: limit the permission scope. Using the permissions below didn't worked:
# kms:Encrypt", "kms:Decrypt","kms:GenerateDataKey","kms:DescribeKey"
jq --arg aws_account "$AWS_ACCOUNT" \
   --arg iam_user_ami "$IAM_USER_AMI" \
  '.Statement += [{
  "Sid": "AllowUseUserAMI",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::\($aws_account):user/\($iam_user_ami)"
  },
  "Action" : "*",
  "Resource": "*"
}]' ./kms-policy.json > ./kms-policy-0.json

AWS_PROFILE=$IAM_USER_KMS aws kms put-key-policy \
    --policy-name default \
    --key-id ${KMS_KEY_ID} \
    --policy file://./kms-policy-0.json

# Extract AMI ID
export OCP_IMAGE_ID=$(./openshift-install coreos print-stream-json | jq -r ".architectures[\"$OCP_ARCH\"].images.aws.regions[\"$AWS_REGION\"].image ")

# Mirror AMI
OCP_IMAGE_ID_ENC=$(AWS_PROFILE=$IAM_USER_AMI aws ec2 copy-image \
  --source-image-id "$OCP_IMAGE_ID" \
  --source-region "$AWS_REGION" \
  --region "$AWS_REGION" \
  --name "${INFRA_REF}-RHCOS-${OCP_VERSION}" \
  --encrypted \
  --kms-key-id "$KMS_KEY_ID" | jq -r .ImageId)

# Wait AMI to complete: Must transictioned from Pending to Active in a few minutes
# When failed, describe the image and investigate it
while true; do
  echo $(date): $(AWS_PROFILE=$IAM_USER_AMI aws ec2 describe-images --filters "Name=name,Values=${INFRA_REF}-RHCOS-${OCP_VERSION}" | jq -cr '.Images[]|{State, StateMessage}');
  sleep 10;
done

# Alternatively, if you find any issues, check if the user have correct permissions.
AWS_PROFILE=$IAM_USER_AMI aws iam simulate-principal-policy \
    --policy-source-arn "arn:aws:iam::$AWS_ACCOUNT:user/$IAM_USER_AMI" \
    --action-names kms:Encrypt kms:GenerateDataKey kms:DescribeKey \
    --resource-arns arn:aws:kms:us-east-1:${AWS_ACCOUNT}:key/${KMS_KEY_ID}


# Create the patch file
cat <<EOF > ${INSTALL_DIR}/install-config.patch.yaml
platform:
  aws:
    defaultMachinePlatform:
      amiID: ${OCP_IMAGE_ID_ENC}
EOF

# Create generic install-config

# patch the install-config. Depends on the #setup section
export CLUSTER_NAME=$(echo "$INFRA_REF" | tr '[:upper:]' '[:lower:]')
export CLUSTER_BASEDOMAIN="devcluster.openshift.com"
export PULL_SECRET_PATH="$HOME/.openshift/pull-secret-latest.json"
export SSH_KEYS="$(cat ~/.ssh/id_rsa.pub)"
export AWS_DEFAULT_REGION=us-east-1
cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: "${CLUSTER_BASEDOMAIN}"
metadata:
  name: "${CLUSTER_NAME}"
pullSecret: '$(cat ${PULL_SECRET_PATH} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  ${SSH_KEYS}
platform:
  aws:
    region: ${AWS_DEFAULT_REGION}
EOF
```

Next Step (choose one):
- [BYO Encrypted AMI with Manual with STS Authenticated mode (IAM Role)](#byo-ami-enc-sts)
- [BYO Encrypted AMI with Mint Authenticated mode (IAM User)](#byo-ami-enc-mint)

##### BYO Encrypted AMI with Passthrough Authenticated mode (IAM User)<a name="byo-ami-enc-user"></a>>


Steps:

> TBDescribed

```sh
# Append the credentials mode to the patch:
cat <<EOF >> ${INSTALL_DIR}/install-config.patch.yaml
credentialsMode: Passthrough
EOF

# Generate final install-config
${BIN_YQ} -i ". *= load(\"${INSTALL_DIR}/install-config.patch.yaml\")" ${INSTALL_DIR}/install-config.yaml

# Check and back up the policy
${BIN_YQ} ea .platform.aws ${INSTALL_DIR}/install-config.yaml

cp ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config-bkp.yaml

# Generate the IAM policy used by installer
./openshift-install create permissions-policy --dir $INSTALL_DIR


cp -v $INSTALL_DIR/aws-permissions-policy-creds.json ./${IAM_USER_INST}-policy.json
create_user_and_keys "${IAM_USER_INST}" "./${IAM_USER_INST}-policy.json"

# create the installer manifests with installer user
AWS_PROFILE=$IAM_USER_INST ./openshift-install create manifests --dir $INSTALL_DIR

# Get current KMS policy
AWS_PROFILE=$IAM_USER_KMS aws kms get-key-policy --key-id $KMS_KEY_ID --query Policy --output text | jq '.' > ./kms-policy.json


# Patch to allow new users
jq --arg aws_account "$AWS_ACCOUNT" --arg user_installer "$IAM_USER_INST" \
  '.Statement += [{
  "Sid": "AllowInstaller",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::\($aws_account):user/\($user_installer)"
  },
  "Action" : "*",
  "Resource": "*"
}]' ./kms-policy.json > ./kms-policy-2.json

# Check if the policies is appending to the original in ./kms-policy-1.json

# Update
AWS_PROFILE=$IAM_USER_KMS aws kms put-key-policy \
    --policy-name default \
    --key-id ${KMS_KEY_ID} \
    --policy file://./kms-policy-2.json


# Check if workers manifest set the correct AMI ID
yq ea .spec.template.spec.providerSpec.value.blockDevices $INSTALL_DIR/openshift/99_openshift-cluster-api_worker-machineset-*.yaml

echo $OCP_IMAGE_ID_ENC
yq ea .spec.template.spec.providerSpec.value.ami $INSTALL_DIR/openshift/99_openshift-cluster-api_worker-mac*.yaml

yq ea .spec.providerSpec.value.ami $INSTALL_DIR/openshift/99_openshift-cluster-api_master-mac*.yaml


```

Create a cluster with custom user:

```sh
AWS_PROFILE=$IAM_USER_INST ./openshift-install create cluster --dir $INSTALL_DIR --log-level=debug
```


### BYO Encrypted AMI with Manual with Manual Credentials mode (IAM Role/STS) <a name="byo-ami-enc-sts"></a>>

Install Option 01) Dedicated IAM user for each component (Failing)

Quickly deploy a cluster using STS with [automated shell script (automates the required manual steps)](https://mtulio.dev/playbooks/openshift/ocp-aws-cco-sts-install-quickly/)

```sh
# Change the function setup_installer appending the AMI to:
# platform.aws.defaultMachinePlatform.amiID
# Install a cluter 4.18.8
CLUSTER_VERSION="4.18.8" &&\
  CLUSTER_NAME="sts418ami" &&\
  CLUSTER_BASE_DOMAIN="devcluster.openshift.com" &&\
  create_cluster $CLUSTER_NAME

# Access the cluster
export KUBECONFIG=$INSTALL_DIR/auth/kubeconfig

# Collect relevant information to ensure readiness:
oc get clusterversion

# Credentials mode  
$ oc get -n kube-system cm cluster-config-v1 -o yaml | yq4 '.data["install-config"]' | yq4 .credentialsMode

# AMI Used in the install-config
$ oc get -n kube-system cm cluster-config-v1 -o yaml | yq4 '.data["install-config"]' | yq4 .platform.aws.defaultMachinePlatform.amiID

# Check AMIs used in machines are same added to install-config
$ oc get machines -n openshift-machine-api -o yaml | yq ea .items[].spec.providerSpec.value.ami -

# Check encrypted AMI - mirrored from RHCOS payload
$ aws ec2 describe-images --image-ids $(aws ec2 describe-instances --instance-ids $(oc get machines -n openshift-machine-api $(oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=worker -ojsonpath='{.items[0].metadata.name}') -o yaml | yq4 .status.providerStatus.instanceId ) --query Reservations[].Instances[].ImageId --output text) | jq '.Images[]|{ImageId, Name, Description, BlockDeviceMappings}'

# AMI (Snapshot) is encrypted with KMS CMK
$ aws ec2 describe-snapshots --snapshot-ids $(aws ec2 describe-images --image-ids $(aws ec2 describe-instances --instance-ids $(oc get machines -n openshift-machine-api $(oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=worker -ojsonpath='{.items[0].metadata.name}') -o yaml | yq4 .status.providerStatus.instanceId ) --query Reservations[].Instances[].ImageId --output text) | jq -r '.Images[].BlockDeviceMappings[0].Ebs.SnapshotId') | jq -r '.Snapshots[]|{SnapshotId, StartTime, CompletionTime, Encrypted, KmsKeyId, Description}'

# KMS CMK policy have enough permissions
$ aws kms get-key-policy --key-id $(aws ec2 describe-snapshots --snapshot-ids $(aws ec2 describe-images --image-ids $(aws ec2 describe-instances --instance-ids $(oc get machines -n openshift-machine-api $(oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=worker -ojsonpath='{.items[0].metadata.name}') -o yaml | yq4 .status.providerStatus.instanceId ) --query Reservations[].Instances[].ImageId --output text) | jq -r '.Images[].BlockDeviceMappings[0].Ebs.SnapshotId') | jq -r '.Snapshots[].KmsKeyId') | jq -r .Policy
```


**Install Option 02) Dedicated IAM user for each component (Failing)**

!!! warn "Failing option"
    Don't use this option as there is no enough information to determine the root cause of failure in OIDC Authnz (unrelated with encrypted AMI). Use Option 1 to quickly acces STS cluster using standard deployment method.

Steps:
- Create the install-config with:
    - `manual` autentication mode
- Generate the IAM Policy required to the installer user (minimum permissions)
- Create the IAM User used by installer
- Create the IAM User used by ccoctl
- Create the installer manifests
- Create the IAM Roles with ccoctl
- Update/Patch the KMS Key policy allowing identities:
  - installer IAM User
  - IAM Role for Machine API
- Deploy the cluster
- Observe install complete

```sh
# Append the credentials mode to the patch:
cat <<EOF >> ${INSTALL_DIR}/install-config.patch.yaml
credentialsMode: Manual
EOF

# Generate final install-config
${BIN_YQ} -i ". *= load(\"${INSTALL_DIR}/install-config.patch.yaml\")" ${INSTALL_DIR}/install-config.yaml

# Check and back up the policy
${BIN_YQ} ea .platform.aws ${INSTALL_DIR}/install-config.yaml

cp ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config-bkp.yaml

# Generate the IAM policy used by installer
./openshift-install create permissions-policy --dir $INSTALL_DIR

## TODO: file a bug to fix the policy when manual mode. Error:
# An error occurred (LimitExceeded) when calling the PutUserPolicy operation: Maximum policy size of 2048 bytes exceeded for user RFE-5733-usr-inst
# TODO move to managed policy (instead of inline)

## Generate policy document for each user

cp -v $INSTALL_DIR/aws-permissions-policy-creds.json ./${IAM_USER_INST}-policy.json
cat <<EOF > ./${IAM_USER_CCOCTL}-policy.json
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Sid": "ccoctlIAM",
			"Action": [
				"iam:CreateOpenIDConnectProvider",
				"iam:CreateRole",
				"iam:DeleteOpenIDConnectProvider",
				"iam:DeleteRole",
				"iam:DeleteRolePolicy",
				"iam:GetOpenIDConnectProvider",
				"iam:GetRole",
				"iam:GetUser",
				"iam:ListOpenIDConnectProviders",
				"iam:ListRolePolicies",
				"iam:ListRoles",
				"iam:PutRolePolicy",
				"iam:TagOpenIDConnectProvider",
				"iam:TagRole"
			],
			"Effect": "Allow",
			"Resource": "*"
		},
		{
			"Sid": "ccoctlS3",
			"Action": [
				"s3:CreateBucket",
				"s3:DeleteBucket",
				"s3:DeleteObject",
				"s3:GetBucketAcl",
				"s3:GetBucketTagging",
				"s3:GetObject",
				"s3:GetObjectAcl",
				"s3:GetObjectTagging",
				"s3:ListBucket",
				"s3:PutBucketAcl",
				"s3:PutBucketTagging",
				"s3:PutObject",
				"s3:PutObjectAcl",
				"s3:PutObjectTagging",
				"s3:PutBucketPublicAccessBlock",
				"s3:PutBucketPolicy"
			],
			"Effect": "Allow",
			"Resource": "*"
		},
    {
        "Sid": "ccoctlCloudFront",
        "Action": [
            "cloudfront:GetCloudFrontOriginAccessIdentityConfig",
            "cloudfront:ListCloudFrontOriginAccessIdentities",
            "cloudfront:ListTagsForResource",
            "cloudfront:DeleteCloudFrontOriginAccessIdentity",
            "cloudfront:ListDistributions",
            "cloudfront:GetCloudFrontOriginAccessIdentity",
            "cloudfront:UpdateDistribution",
            "cloudfront:CreateDistribution",
            "cloudfront:CreateCloudFrontOriginAccessIdentity",
            "cloudfront:TagResource",
            "cloudfront:GetDistribution",
            "cloudfront:DeleteDistribution"
        ],
        "Effect": "Allow",
        "Resource": "*"
    },
    {
        "Sid": "ccoctlCloudFrontS3",
        "Action": [
            "s3:PutBucketPolicy",
            "s3:PutBucketPublicAccessBlock"
        ],
        "Effect": "Allow",
        "Resource": "*"
    }
	]
}
EOF

# Create users
create_user_and_keys "${IAM_USER_CCOCTL}" "./${IAM_USER_CCOCTL}-policy.json"
create_user_and_keys "${IAM_USER_INST}" "./${IAM_USER_INST}-policy.json"

RELEASE_IMAGE=$(./openshift-install version | awk '/release image/ {print $3}')
oc adm release extract \
  --from=$RELEASE_IMAGE \
  --credentials-requests \
  --included \
  --install-config=${INSTALL_DIR}/install-config.yaml \
  --to=./creds-requests

# create the installer manifests with installer user
AWS_PROFILE=$IAM_USER_INST ./openshift-install create manifests --dir $INSTALL_DIR

CLUSTER_INFRA_ID=$(${BIN_YQ} ea .status.infrastructureName $INSTALL_DIR/manifests/cluster-infrastructure-02-config.yml)

echo $CLUSTER_INFRA_ID

# generate manifests for release
# Creating according to https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html-single/installing_on_aws/index#cco-ccoctl-creating-at-once_installing-aws-customizations


# create IAM roles with cco user
AWS_PROFILE=$IAM_USER_CCOCTL ./ccoctl aws create-all \
  --name=${CLUSTER_NAME} \
  --region=${AWS_REGION} \
  --credentials-requests-dir=./creds-requests \
  --output-dir=./creds-output \
  --create-private-s3-bucket

# Copy to install dir
cp -v ./creds-output/manifests/* $INSTALL_DIR/manifests/
cp -v ./creds-output/tls $INSTALL_DIR/

# Patch the KMS key to allow components which requires manipulate with AMI: installer and MAPI

# Get current KMS policy
AWS_PROFILE=$IAM_USER_KMS aws kms get-key-policy --key-id $KMS_KEY_ID --query Policy --output text | jq '.' > ./kms-policy.json

IAM_ROLE_ARN_MAPI=$(grep role_arn $INSTALL_DIR/manifests/openshift-machine-api-aws-cloud-credentials-credentials.yaml | awk -F'= ' '{print$2}')

# Patch to allow new users
jq --arg aws_account "$AWS_ACCOUNT" --arg user_installer "$IAM_USER_INST" --arg role_arn_mapi "$IAM_ROLE_ARN_MAPI" \
  '.Statement += [{
  "Sid": "AllowInstaller",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::\($aws_account):user/\($user_installer)"
  },
  "Action" : "*",
  "Resource": "*"
},{
  "Sid": "AllowMAPI",
  "Effect": "Allow",
  "Principal": {
    "AWS": "\($role_arn_mapi)"
  },
  "Action" : "*",
  "Resource": "*"
}]' ./kms-policy.json > ./kms-policy-2.json

# Check if the policies is appending to the original in ./kms-policy-1.json

# Update
AWS_PROFILE=$IAM_USER_KMS aws kms put-key-policy \
    --policy-name default \
    --key-id ${KMS_KEY_ID} \
    --policy file://./kms-policy-2.json
```

Checks before installing:

```sh
# Check if the encrypted flag is set to the machine manifests
$ yq ea .spec.template.spec.providerSpec.value.blockDevices $INSTALL_DIR/openshift/99_openshift-cluster-api_worker-machineset-*.yaml
- ebs:
    encrypted: true
    iops: 0
    kmsKey:
      arn: ""
    volumeSize: 120
    volumeType: gp3
...

# Check if workers manifest set the correct AMI ID
echo $OCP_IMAGE_ID_ENC
yq ea .spec.template.spec.providerSpec.value.ami $INSTALL_DIR/openshift/99_openshift-cluster-api_worker-mac*.yaml

yq ea .spec.providerSpec.value.ami $INSTALL_DIR/openshift/99_openshift-cluster-api_master-mac*.yaml
```

Create a cluster with custom user:

```sh
AWS_PROFILE=$IAM_USER_INST ./openshift-install create cluster --dir $INSTALL_DIR --log-level=debug
```


## Troubleshooting

OIDC token validation:

TODO: investigate credentials issues
```sh
export KUBECONFIG=$INSTALL_DIR/auth/kubeconfig

```

Issue:
```sh
An error occurred (InvalidIdentityToken) when calling the AssumeRoleWithWebIdentity operation: Couldn't retrieve verification key from your identity provider,  please reference AssumeRoleWithWebIdentity documentation for requirements

```

Validation script:

```sh
echo "---"
echo "=> Secret has been created: "
# Check if credentials secret has been created
oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' \
    | base64 -d

echo "---"
echo "=> Component | Secret has been created: "
# Extracts the token
# Get Token path from AWS credentials mounted to pod
TOKEN_PATH=$(oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' |\
    base64 -d |\
    grep ^web_identity_token_file |\
    awk '{print$3}')

echo "---"
echo "=> Component | Can read signed service account token: "
# Get Controler's pod
CAPI_POD=$(oc get pods -n openshift-machine-api \
    -l api=clusterapi \
    -o jsonpath='{.items[*].metadata.name}')

# Extract tokens from pod
TOKEN=$(oc exec -n openshift-machine-api ${CAPI_POD} \
    -c machine-controller -- cat ${TOKEN_PATH})

echo "Token size from pod $CAPI_POD: $(echo $TOKEN|wc)"

echo "---"
echo "=> Component | Can extract information from JWT token: "

# Get insigits
echo $TOKEN | awk -F. '{ print $1 }' | base64 -d 2>/dev/null | jq .alg
echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null | jq .iss


echo "---"
echo "=> Component | Can extract IAM Role from secret: "

# Test token
IAM_ROLE=$(oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' |\
    base64 -d |\
    grep ^role_arn |\
    awk '{print$3}')

echo $IAM_ROLE

echo "---"
echo "=> Component | Can assume IAM role with bound token: "
AWS_SHARED_CREDENTIALS_FILE=$HOME/.aws/credentials aws sts assume-role-with-web-identity \
    --role-arn "${IAM_ROLE}" \
    --role-session-name "my-session" \
    --web-identity-token "${TOKEN}"


echo "---"
echo "=> ServiceAccountIssuer can be accessed through the internet:"
if command curl -sl $(oc get authentication cluster -o jsonpath='{.spec.serviceAccountIssuer}')/.well-known/openid-configuration | jq -cr .issuer; then
  echo -ne " OK"
else
  echo "ERROR accessing public OIDC endpoint"
fi

# https://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation
# .2
# Checking issuer
echo "---"
echo "=> Issuer provided by kube: "
kubectl get --raw /.well-known/openid-configuration | jq -r .issuer

echo "=> Issuer in public JWKS: "
curl -sk $(kubectl get --raw /.well-known/openid-configuration | jq -r .issuer)/.well-known/openid-configuration | jq -r .issuer

echo "=> Issuer in the token: "
echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null  | jq -r .iss

# Checking kid
echo "---"
echo "=> kid in public JWKS: "
kid_public=$(curl -sk $(kubectl get --raw /.well-known/openid-configuration | jq -r .issuer)/keys.json  | jq -r .keys[0].kid)
echo $kid_public

echo "=> kid kube keys: "
kubectl get --raw /openid/v1/jwks | jq -r ".keys[] | select(.kid==\"${kid_public}\")"

if [[ -z $(kubectl get --raw /openid/v1/jwks | jq -r ".keys[] | select(.kid==\"${kid_public}\")") ]]; then
  echo "ERROR kid published in S3 not found in kube"
fi

echo "=> kid token: "
kid_token=$(echo $TOKEN | awk -F. '{ print $1 }' | base64 -d 2>/dev/null  | jq -r .kid)
echo $kid_token

echo "=> kid token in kube: "
kubectl get --raw /openid/v1/jwks | jq -r ".keys[] | select(.kid==\"${kid_token}\").kid"

if [[ "${kid_public}" != "${kid_token}" ]]; then
  echo "ERROR kid missmatch from signed token and published public keys"
fi
```

other checks:
```sh
# check if public keys are accessible
curl -sk $(echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null  | jq -r .iss)/keys.json

# checkif config is accessible
curl -sk $(echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null  | jq -r .iss)/.well-known/openid-configuration

kubectl get --raw /.well-known/openid-configuration | jq .
kubectl get --raw /openid/v1/jwks | jq .
```
