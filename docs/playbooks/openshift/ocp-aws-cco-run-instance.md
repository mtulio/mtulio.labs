# OCP on AWS - Hacking STS running instance using CLI

The steps below describe how to create EC2 instances using AWS CLI using credentials provided by STS when using an OCP cluster with short-lived credentials in manual authentication mode.

References:

- [OpenShift CCO with manual credentials with STS](https://docs.openshift.com/container-platform/4.10/authentication/managing_cloud_provider_credentials/cco-mode-sts.html)
- [aws cli run-instance](https://docs.aws.amazon.com/cli/latest/reference/ec2/run-instances.html)


Required tools:

- jq
- aws cli
- oc

Required permissions:

- authenticated with AWS user which has IAM Role List grants
- authenticated with OCP User with cluster-admin grants


### Check permissions IAM vs CCO

- Make sure the session (user, role, or instance profile) has enough permissions to run the IAM operations. These permissions are required:
```
iam:GetPolicy
iam:GetPolicyVersion
iam:GetRole
iam:GetRolePolicy
iam:ListAttachedRolePolicies
iam:ListEntitiesForPolicy
iam:ListPolicies
iam:ListPolicyTags
iam:ListPolicyVersions
iam:ListRolePolicies
iam:ListRoleTags
iam:ListRoles
iam:PassRole
sts:AssumeRole
sts:GetCallerIdentity
```

- Check IAM Role permission

```bash
test_credentials() {
    # get the token path
    TOKEN_PATH=$(oc get secrets aws-cloud-credentials \
        -n openshift-machine-api \
        -o jsonpath='{.data.credentials}' |\
        base64 -d |\
        grep ^web_identity_token_file |\
        awk '{print$3}')

    # Get Controler's pod
    CAPI_POD=$(oc get pods -n openshift-machine-api \
        -l api=clusterapi \
        -o jsonpath='{.items[*].metadata.name}')

    # Extract tokens from the pod
    TOKEN=$(oc exec -n openshift-machine-api ${CAPI_POD} \
        -c machine-controller -- cat ${TOKEN_PATH})

    export IAM_ROLE_ARN=$(oc get secrets aws-cloud-credentials \
        -n openshift-machine-api \
        -o jsonpath='{.data.credentials}' |\
        base64 -d |\
        grep ^role_arn |\
        awk '{print$3}')

    # Assumin role
    aws sts assume-role-with-web-identity \
        --role-arn "${IAM_ROLE_ARN}" \
        --role-session-name "my-session" \
        --web-identity-token "${TOKEN}" \
        > session-credentials.json
    
    echo "#> Check if the Role has been assumed correctly (preserving sensitive data): "
    jq -r '.|(.AssumedRoleUser, .SubjectFromWebIdentityToken, .Provider, .Credentials.Expiration)' session-credentials.json
}

get_role_info() {
    aws sts get-caller-identity
    IAM_ROLE_NAME=$(echo $IAM_ROLE_ARN  | awk -F 'role/' '{print$2}')
    echo "#>> Role=[$IAM_ROLE_NAME];"
    aws iam get-role --role-name ${IAM_ROLE_NAME} | tee cco-check-iam-role-mapi.json

    for ROLE_POL in $(aws iam list-role-policies --role-name ${IAM_ROLE_NAME} |jq -r .PolicyNames[]); do
        echo "#>> Role=[$IAM_ROLE_NAME] Policy=[$ROLE_POL]";
        aws iam get-role-policy \
            --role-name ${IAM_ROLE_NAME} \
            --policy-name ${ROLE_POL} \
            | tee cco-check-iam-role-policy-$ROLE_POL.json
    done
}

get_cco_credrequests() {
    oc get -n openshift-cloud-credential-operator -o json  \
        credentialsrequests openshift-machine-api-aws \
        | tee cco-check-cco-credreq.json
}

check_permissions() {
    jq -r .spec.providerSpec.statementEntries[].action[] cco-check-cco-credreq.json |\
        sort > cco-check-mapi-actions-cco.txt
    jq -r .PolicyDocument.Statement[].Action[]  cco-check-iam-role-policy-*.json |\
        sort > cco-check-mapi-actions-iam.txt
    echo "# Checking difference between IAM and CCO CredentialRequest permissions (expected to be empty diff): "
    echo "START_DIFF>>"
    diff \
        cco-check-mapi-actions-cco.txt \
        cco-check-mapi-actions-iam.txt \
        | tee cco-check-mapi-actions_diff.txt
    echo "<<END_DIFF"
}

collect_cco_info() {
    echo "#check_cco> $(date)"
    test_credentials
    get_role_info
    get_cco_credrequests
    check_permissions
}

collect_cco_info >>./cco-check.log 2>&1
echo "# Data collected: $(ls cco-check*)"
```

## Test RunInstance using AWS CLI

Steps to get worker attributes and run the instance using aws-cli with credentials provided by STS

> using aws-cli to RunInstance using MAPI Credentials provided by CCO

```bash
run_instance_worker() {

    local INST_IDX=${1:-'01'}

    # Setup credentials to run using MAPI
    WORKER_MACHINE_COPY="cco-check-worker_base.json"
    STS_ID=$(jq -r .Credentials.AccessKeyId session-credentials.json)
    STS_KEY=$(jq -r .Credentials.SecretAccessKey session-credentials.json)
    STS_TOKEN=$(jq -r .Credentials.SessionToken session-credentials.json)

    echo "# Using STS credentials, expected to match the IAM Role Arn: $IAM_ROLE_ARN"
    AWS_ACCESS_KEY_ID=${STS_ID} \
        AWS_SECRET_ACCESS_KEY=${STS_KEY} \
        AWS_SESSION_TOKEN=${STS_TOKEN} \
        aws sts get-caller-identity

    echo "# Getting worker machine to be used as base manifest [${WORKER_MACHINE_COPY}]..."
    oc get machines \
        -n openshift-machine-api \
        -l machine.openshift.io/cluster-api-machine-role=worker \
        -o json \
        | jq '.items[0]' > ${WORKER_MACHINE_COPY}

    echo "# Extracting values from machine base manifest [${WORKER_MACHINE_COPY}]..."

    # Setting default machine path (if there are no custom fields, otherwise you should adapt it)
    REGION=$(jq -r '.metadata.labels["machine.openshift.io/region"]' ${WORKER_MACHINE_COPY})
    AMI_ID=$(jq -r .spec.providerSpec.value.ami.id ${WORKER_MACHINE_COPY})

    CLUSTER_ID=$(jq -r '.metadata.labels["machine.openshift.io/cluster-api-cluster"]' ${WORKER_MACHINE_COPY})
    INSTANCE_TYPE=$(jq -r .spec.providerSpec.value.instanceType ${WORKER_MACHINE_COPY})
    USER_DATA_SECRET=$(jq -r .spec.providerSpec.value.userDataSecret.name ${WORKER_MACHINE_COPY})
    SUBNET_NAME=$(jq -r .spec.providerSpec.value.subnet.filters[].values[] ${WORKER_MACHINE_COPY})
    SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=${SUBNET_NAME}" \
        --query 'Subnets[].SubnetId' \
        --output text)
    SG_NAME=$(jq -r .spec.providerSpec.value.securityGroups[].filters[].values[0] ${WORKER_MACHINE_COPY})
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Name,Values=${SG_NAME}" \
        --query 'SecurityGroups[].GroupId' \
        --output text)

    INSTANCE_NAME="${CLUSTER_ID}-test-RunInstance-${INST_IDX}"

    # Extract user data
    USER_DATA_FILE=worker-user-data.txt
    oc get secret \
        -n openshift-machine-api ${USER_DATA_SECRET} \
        -o jsonpath="{.data.userData}" \
        | base64 -d > ${USER_DATA_FILE}

    echo "# Dumping variables collected to perform RunInstance using AWS CLI:
STS_ID=${STS_ID}
REGION=${REGION}
AMI_ID=${AMI_ID}
CLUSTER_ID=${CLUSTER_ID}
INSTANCE_TYPE=${INSTANCE_TYPE}
SUBNET_ID=${SUBNET_ID}
SG_ID=${SG_ID}
INSTANCE_NAME=${INSTANCE_NAME}
USER_DATA_FILE=${USER_DATA_FILE}"
    echo "# Running 'aws ec2 run-instance (...)' with STS token"
    # Run instance using STS credentials
    AWS_ACCESS_KEY_ID=${STS_ID} \
        AWS_SECRET_ACCESS_KEY=${STS_KEY} \
        AWS_SESSION_TOKEN=${STS_TOKEN} \
        aws ec2 run-instances \
            --region ${REGION} \
            --image-id ${AMI_ID} \
            --iam-instance-profile Name="${CLUSTER_ID}-worker-profile"  \
            --instance-type ${INSTANCE_TYPE} \
            --network-interfaces "[{\"DeviceIndex\":0, \"SubnetId\": \"${SUBNET_ID}\", \"Groups\": [\"${SG_ID}\"]}]" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=\"${INSTANCE_NAME}\"},{Key=kubernetes.io/cluster/${CLUSTER_ID},Value=owned}]" \
            --user-data file://${USER_DATA_FILE} \
            | tee cco-check-run-worker-result.json
}

run_instance_worker "01" >>./cco-check-run-worker.log 2>&1
```

- You should see the certificates pending to be approved

```
oc get csr
```

- Approving certs

```
for CSR in $(oc get csr -o jsonpath={.items[*].metadata.name}); do oc adm  certificate approve $CSR; done
```

## Collect the data

- Check the results

```
ls cco-check*
```

- Create the archive

```
tar cfz cco-check.tar.gz cco-check*
```

## FAQ

### What happens when there are missing RunInstance permissions

A) What happens when the IAM Role policy has no ec2:RunInstance permission on the inline policy created by CCO?

**Steps to reproduce:**

- Remove ec2:RunInstnace from an inline policy for IAM Role `$CLUSTER_NAME-openshift-machine-api-aws-cloud-credentials`
- Run the `aws ec2 run-instance (...)`

**Expected results:**

- Run
```bash
$ run_instance_worker "02" | tee -a cco-check-run-worker-02.log
An error occurred (UnauthorizedOperation) when calling the RunInstances operation: You are not authorized to perform this operation. Encoded authorization failure message: <[redacted:value set to ERROR_MESSAGE]>
```
- Decode the message and check the details (replace `ERROR_MESSAGE`):
```bash
echo $(aws sts decode-authorization-message \
    --encoded-message $ERROR_MESSAGE \
    | jq -r .DecodedMessage) \
    | jq .
```
- Decode the error message - attention on the field `allowed=false`:
```json
{
  "allowed": false,
  "explicitDeny": false,
  "matchedStatements": {
    "items": []
  },
  "failures": {
    "items": []
  },
  "context": {
    "principal": {
      "id": "AROAT[redacted]:my-session",
      "arn": "arn:aws:sts::[redacted:AWS_ACCOUNT]:assumed-role/[redacted:CLUSTER_NAME]-openshift-machine-api-aws-cloud-credentials/my-session"
    },
    "action": "ec2:RunInstances",
    "resource": "arn:aws:ec2:us-east-1:[redacted:AWS_ACCOUNT]:instance/*",
    "conditions": {
(...)
    }
  }
}
```

B) What happens when the IAM Role `$CLUSTER_NAME-openshift-machine-api-aws-cloud-credentials` has permission boundaries set to block ec2:RunInstance operations?


**Steps to reproduce:**

- Create the policy with the below permission document, and attach it to the IAM Role `$CLUSTER_NAME-openshift-machine-api-aws-cloud-credentials`
```json
{
   "Version": "2012-10-17",
   "Statement": [{
      "Effect":"Deny",
      "Action":["ec2:RunInstances"],
      "Resource":"*"
    },
    {
      "Effect":"Allow",
      "Action":["iam:PassRole"],
      "Resource":"*"
    }]
}
```
- Run the `aws ec2 run-instance (...)`

**Expected results:**

- Run
```
$ run_instance_worker "03" | tee -a cco-check-run-worker-03.log
# Using STS credentials, expected to see the Role Name ARN: 
{
    "UserId": "[redacted]:my-session",
    "Account": "[redacted]",
    "Arn": "arn:aws:sts::[redacted]:assumed-role/[redacted]-openshift-machine-api-aws-cloud-credentials/my-session"
}


An error occurred (UnauthorizedOperation) when calling the RunInstances operation: You are not authorized to perform this operation. Encoded authorization failure message: <redacted:$ERROR_MESSAGE>
```
- Decode the error message - attention to the field `explicitDeny=true`:
```json
$ echo $(aws sts decode-authorization-message \
>     --encoded-message $ERROR_MESSAGE \
>     | jq -r .DecodedMessage) \
>     | jq .
{
  "allowed": false,
  "explicitDeny": true,
  "matchedStatements": {
    "items": [
      {
        "statementId": "",
        "effect": "DENY",
        "principals": {
          "items": [
            {
              "value": "SCOPE_POLICY_ISSUER"
            }
          ]
        },
        "principalGroups": {
          "items": []
        },
        "actions": {
          "items": [
            {
              "value": "ec2:RunInstances"
            }
          ]
        },
        "resources": {
          "items": [
            {
              "value": "*"
            }
          ]
        },
        "conditions": {
          "items": []
        }
      }
    ]
  },
  "failures": {
    "items": []
  },
  "context": {
    "principal": {
      "id": "AROAT[redacted]:my-session",
      "arn": "arn:aws:sts::[redacted]:assumed-role/[redacted]-openshift-machine-api-aws-cloud-credentials/my-session"
    },
    "action": "ec2:RunInstances",
    "resource": "arn:aws:ec2:us-east-1:[redacted]:instance/*",
    "conditions": {
(...)
    }
  }
}
```

C) What happens when the AWS Account has SCP denying ec2:RunInstance?

**Steps to reproduce:**

- Create the SCP blocking ec2:RunInstnace on the AWS Organizations, then attach that policy to the AWS Account (or to the Organization Unit):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Statement1",
      "Effect": "Deny",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
```
- Run the `aws ec2 run-instance --dry-run (...)`

**Expected results:**

- Run the --dry-run
```bash
$ aws ec2 run-instances --dry-run --image-id ami-0cff7528ff583bf9a

An error occurred (UnauthorizedOperation) when calling the RunInstances operation: You are not authorized to perform this operation. Encoded authorization failure message: $ERROR_MESSAGE
```

- Decode the error
```json
$ echo $(aws sts decode-authorization-message \
>     --encoded-message $ERROR_MESSAGE \
>     | jq -r .DecodedMessage) \
>     | jq .
{
  "allowed": false,
  "explicitDeny": true,
  "matchedStatements": {
    "items": [
      {
        "statementId": "Statement1",
        "effect": "DENY",
        "principals": {
          "items": [
            {
              "value": "[redacted]"
            }
          ]
        },
        "principalGroups": {
          "items": []
        },
        "actions": {
          "items": [
            {
              "value": "ec2:RunInstances"
            }
          ]
        },
        "resources": {
          "items": [
            {
              "value": "*"
            }
          ]
        },
        "conditions": {
          "items": []
        }
      }
    ]
  },
  "failures": {
    "items": []
  },
  "context": {
    "principal": {
      "id": "[redacted]:braga",
      "arn": "arn:aws:sts::[redacted]:assumed-role/AWSReservedSSO_AdministratorAccess_[redacted]/braga"
    },
    "action": "ec2:RunInstances",
    "resource": "arn:aws:ec2:us-east-1:[redacted]:instance/*",
    "conditions": {
(...)
    }
  }
}
```
