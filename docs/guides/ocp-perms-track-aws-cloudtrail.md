# OCP on AWS | Experiment | Explore Cloud permissions requested and required

This experimental document describes how to collect and explore
events of API calls used by users when installing a cluster,
executed test suite, and destroy a cluster on AWS.

The CloudTrail will be created to track events and save logs to S3 bucket, once the logger is enabled, a dedicated user to installer
will be created to easily track all actions taken by that user.

Once the installation is finished, the e2e workload is added to
generate events by operators to exercise more Cloud API calls by the environment.

Once it finished, the destroy will be called.

The logs will be extracted from S3, parsed, and actions taken by each user (installer, operators) will be grouped by user.

CredentialsRequests manifests for the version of the cluster will be
extracted, parsed, linked to IAM users from CloudTrail, then
a compilation of what is required (API calls) and requested will
is created (`diff`) to compare what is missing or extrapolating from
the sample.

## Prerequisites

- Administrator permissions in AWS account to create privileged IAM Users
- Permissions to crete a new Trail

## Steps

### Prerequisites

- Export variables used in this guide

```sh
CLUSTER_NAME=lab-trail
INSTALL_USER=${CLUSTER_NAME}-installer
AWS_REGION=us-east-1
BASE_DOMAIN=devcluster.openshift.com

TRAIL_NAME=${CLUSTER_NAME}
BUCKET_NAME=cloudtrail-${CLUSTER_NAME}
```

### Setup CloudTrail

- Create a CloudTrail to collect events from an specific Region

```sh
# Create S3 bucket
aws s3api create-bucket --bucket $BUCKET_NAME --region $AWS_REGION
# Set the location when bucket is outside us-east-1
# --create-bucket-configuration LocationConstraint=$AWS_REGION

# Set bucket policy
cat > bucket-policy.json <<EOL
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::$BUCKET_NAME"
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::$BUCKET_NAME/AWSLogs/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    }
  ]
}
EOL

aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://bucket-policy.json

# Create CloudTrail
aws cloudtrail create-trail --name $TRAIL_NAME --s3-bucket-name $BUCKET_NAME \
--no-is-multi-region-trail \
--region $AWS_REGION
aws cloudtrail start-logging --name $TRAIL_NAME
```

- Wait until Trail start collecting events:

```sh
while true; do
    echo -ne "IsLogging? "
    isLogging=$(aws cloudtrail get-trail-status \
    --name $TRAIL_NAME \
    --query 'IsLogging' \
    --output text)
    echo $isLogging
    test $isLogging == "True" && break
    sleep 10
done
```

- Wait until some event appears in the Bucket:

```sh
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
while true; do
    DT_Y=$(date -u +%Y)
    DT_M=$(date -u +%m)
    DT_D=$(date -u +%d)
    aws s3 ls s3://$BUCKET_NAME/AWSLogs/${ACCOUNT_ID}/CloudTrail/${AWS_REGION}/${DT_Y}/${DT_M}/${DT_D}/
    sleep 10
done
```

### Setup IAM used by Instlaler user

- Create AWS user to run Installer

```sh
# Step 1: Create the IAM user
aws iam create-user --user-name ${INSTALL_USER}

# Step 2: Attach the AdministratorAccess policy to the user
aws iam attach-user-policy --user-name ${INSTALL_USER} --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Step 3: Create an access key for the user
aws iam create-access-key --user-name ${INSTALL_USER} | tee ./user-${INSTALL_USER}.json

# Step 4: Create a profile to be used by this user
cat << EOF >> ~/.aws/credentials
[${INSTALL_USER}]
region = ${AWS_REGION}
aws_access_key_id = $(jq -r .AccessKey.AccessKeyId ./user-${INSTALL_USER}.json)
aws_secret_access_key = $(jq -r .AccessKey.SecretAccessKey ./user-${INSTALL_USER}.json)
EOF
```

- Install OpenShift cluster

    - Prepare the environmet

```sh
VERSION=4.17.0-rc.2
RELEASE="quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64"
oc adm release extract --tools "${RELEASE}" -a "${PULL_SECRET_FILE}"

tar xvfz openshift-install-linux-${VERSION}.tar.gz

INSTALLER=./openshift-install
INSTALL_DIR=./install-dir-${CLUSTER_NAME}
mkdir -p ${INSTALL_DIR}


```
    - Generate the configuration

```sh
cat << EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
platform:
  aws:
    region: ${AWS_REGION}
pullSecret: '$(cat ${PULL_SECRET_FILE})'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
EOF
```

    - Install a cluster with custom user:

```sh
AWS_PROFILE=${INSTALL_USER} ${INSTALLER} create cluster --dir=${INSTALL_DIR}
```


## Collect events when the cluster is installed

```sh
mkdir events-cluster-install/
AWS_PROFILE=default aws s3 sync s3://${BUCKET_NAME}/ events-cluster-install/
```

## Run e2e

- extract client
```sh
export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig
TESTS_IMAGE=$(oc adm release info --image-for=tests)

oc image extract $(oc adm release info --image-for=tests) -a ${PULL_SECRET_FILE} \
    --file="/usr/bin/openshift-tests"
chmod u+x ./openshift-tests
```

- config client env
> https://github.com/openshift/release/blob/master/ci-operator/step-registry/openshift/e2e/test/openshift-e2e-test-commands.sh

```sh
export PROVIDER_ARGS="-provider=aws -gce-zone=${AWS_REGION}"
ZONE="$(oc get -o jsonpath='{.items[0].metadata.labels.failure-domain\.beta\.kubernetes\.io/zone}' nodes)"
export TEST_PROVIDER="{\"type\":\"aws\",\"region\":\"${AWS_REGION}\",\"zone\":\"${ZONE}\",\"multizone\":true,\"multimaster\":true}"
export KUBE_SSH_USER=core

export OPENSHIFT_TESTS_EXTRA_ARGS+="--provider ${TEST_PROVIDER}"
```

- create dedicated user to e2e

```sh
E2E_USER=${CLUSTER_NAME}-e2e

# Step 1: Create the IAM user
AWS_PROFILE=default aws iam create-user --user-name ${E2E_USER}

# Step 2: Attach the AdministratorAccess policy to the user
AWS_PROFILE=default aws iam attach-user-policy --user-name ${E2E_USER} --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Step 3: Create an access key for the user
AWS_PROFILE=default aws iam create-access-key --user-name ${E2E_USER} | tee ./user-${E2E_USER}.json

# Step 4: Create a profile to be used by this user
cat << EOF >> ~/.aws/credentials
[${E2E_USER}]
region = ${AWS_REGION}
aws_access_key_id = $(jq -r .AccessKey.AccessKeyId ./user-${E2E_USER}.json)
aws_secret_access_key = $(jq -r .AccessKey.SecretAccessKey ./user-${E2E_USER}.json)
EOF
```

- Run e2e

```sh
export AWS_PROFILE=${E2E_USER}
export TEST_SUITE="openshift/conformance"
export ARTIFACT_DIR=${PWD}/e2e
mkdir ${ARTIFACT_DIR}

AWS_PROFILE=${E2E_USER} openshift-tests run "${TEST_SUITE}" ${TEST_ARGS:-} \
        --provider "${TEST_PROVIDER}" \
        -o "${ARTIFACT_DIR}/e2e.log" \
        --junit-dir "${ARTIFACT_DIR}/junit"
```

## Collect events when the e2e has finished

```sh
AWS_PROFILE=default aws s3 sync s3://${BUCKET_NAME}/ events-cluster-e2e/
```

## Destroy the cluster

```sh
AWS_PROFILE=${INSTALL_USER} ${INSTALLER} destroy cluster --dir=${INSTALL_DIR}
```

## Collect events when the e2e has been destroyed

```sh
AWS_PROFILE=default aws s3 sync s3://${BUCKET_NAME}/ events-cluster-destroy/
```

## Extract Credential Requests for AWS

Extract CredentialsRequests objects for the cluster release to
be used later to compare required credentials (consumed during the
collected logs) VS required by CredentialsRequests objects in the release:

```sh
oc adm release extract \
    --credentials-requests \
    --cloud=aws \
    --to=$PWD/credrequests \
    --from=${RELEASE}
```

## Extract insights

Extract the API calls for each stage, considering the IAM Identity name would have the prefix of `$CLUSTER_NAME`

```sh
curl -s https://raw.githubusercontent.com/mtulio/mtulio.labs/devel/labs/ocp-identity/cloud-credentials-insights/cci.py > ./cci

python cci --cluster-name $CLUSTER_NAME \
    --cloud-trail-logs events-cluster-destroy/ \
    --output events-cluster-install-destroy.json \
    --skip-counters
```

Example results:

`$ head events-cluster-install-destroy.json`
```json
{
  "lab-trail-installer": [
    "ec2:AllocateAddress",
    "ec2:AssociateRouteTable",
    "ec2:AttachInternetGateway",
    "ec2:AuthorizeSecurityGroupIngress",
    "ec2:CreateInternetGateway",
    "ec2:CreateNatGateway",
    "ec2:CreateRoute",
    "ec2:CreateRouteTable",
...
```

Compare the required (API Calls) VS requested (CredentialsRequests) by user:

```sh
python cci --cluster-name $CLUSTER_NAME \
    --check-credentials-requests $PWD/credrequests \
    --processed-events ./events-cluster-install-destroy.json \
    --output events-compiled-install-destroy.json \
    --output-diff
```

Example output:

```text
Calculating differences from API calls and requested credentials
Output saved to compiled-credentials.json
Output Diff saved to compiled-credentials.json.diff.json
```

Example compiled file `events-compiled-install-destroy.json`:

`$ head -n 20 events-compiled-install-destroy.json`
```json
{
  "users": {
    "unknown": [],
    "lab-trail-installer": {
      "diff": {
        "missing": [],
        "extra": [],
        "unsupportedCheck": []
      },
      "required": {
        "ec2:DescribeInstanceTypeOfferings": 6,
        "ec2:DescribeAvailabilityZones": 31,
        "ec2:CreateNatGateway": 6,
        "ec2:DescribeSecurityGroups": 29,
        "ec2:CreateSecurityGroup": 4,
        "ec2:AuthorizeSecurityGroupIngress": 4,
```

Example diff file `events-compiled-install-destroy.json.diff.json`:

`$ head events-compiled-install-destroy.json.diff.json`
```json
{
  "lab-trail-lxqrw-openshift-machine-api-aws-s2nml": {
    "missing": [],
    "extra": [
      "ec2:CreateTags",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeRegions",
      "ec2:TerminateInstances",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "elasticloadbalancing:RegisterTargets",
```

### Expanding the checks

Additionally, you can get insights for each phase (install, e2e, destroy).

The example below will parse the events collected after the install phase, and the destroy phase to evaluate the differences.

> This example is supperficial and may not be accurated as events can be synchronized after the data has been collected, to refine you should improve the parser to look at the timestamp of cluster install complete.

- Parse events collected after the cluster has been installed

```sh
./cci --cluster-name $CLUSTER_NAME \
    --cloud-trail-logs events-cluster-install/ \
    --output events-cluster-install-only.json

./cci --cluster-name $CLUSTER_NAME \
    --check-credentials-requests $PWD/credrequests \
    --processed-events ./events-cluster-install-only.json \
    --output events-compiled-install-only.json \
    --output-diff
```

- (TODO) Compare the compiled files:

> TODO: `diff` compare line by line, we need to introduce a parser to compare the permissions itself to be more accurated. Otherwise the counts will trigger a "diff"

```sh
# full report
diff events-cluster-install-only.json events-cluster-install-destroy.json

# only the diffs
diff events-compiled-install-only.json events-compiled-install-destroy.json
```



## Conclusion

This guide explores how to check required AWS permissions by looking
at the API calls during a cluster lifecycle, used on CI, by: installing, testing/using/e2e, destroying.

The results can be used to fine granted permissions used to install an OpenShift cluster, and by operators for different variants.

Suggested next steps:

- Explore if it's possible to use Azure Monitor to explore log events to filter API calls by identities used to a cluster lifecycle on Azure (App/credential)
- How to handle variants?
- What would be a good workflow for CI jobs?

## `cci` CLI

Extract/process events:

```sh
./cci --command extract --events-path all/events/ --output all/output/ \
    --filters principal-name=lab-trail-installer,principal-prefix=lab-trail-lxqrw
```

Process CredentialsRequests versus required (API calls):

```sh
./cci --command compare --events-path all/output/events.json --output all/output/ \
    --credentials-requests-path all/credRequests-AWS \
    --filters cluster-name=lab-trail
```

TODOs:
- read CredentialsRequests
- compare with events
