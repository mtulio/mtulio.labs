# OCP on AWS - Hacking STS running instance using CLI

The steps below describes how to create EC2 instances using AWS CLI using credentials provided by STS when using OCP cluster with short-lived credentials in manual authentication mode.

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

- Check IAM Role permission

```bash
export IAM_ROLE=$(oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' |\
    base64 -d |\
    grep ^role_arn |\
    awk '{print$3}' |\
    awk -F 'role/' '{print$2}')

test_credentials() {
    # get token path
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
    diff cco-check-mapi-actions-cco.txt cco-check-mapi-actions-iam.txt | tee cco-check-mapi-actions_diff.txt
    echo "<<END_DIFF"
}

collect_cco_info() {
    echo "#check_cco> $(date)"
    test_credentials
    get_role_info
    get_cco_credrequests
    check_permissions
}

collect_cco_info | tee -a cco-check.log
echo "# Data collected: $(ls cco-check*)"
```

## Test RunInstance using AWS CLI

Steps to get worker attributes and run the instance using aws-cli with credentials provided by STS

> using aws-cli to RunInstance using MAPI Credentials provided by CCO

```bash
run_instance_worker() {

    # Setup credentials to run using MAPI
    STS_ID=$(jq -r .Credentials.AccessKeyId session-credentials.json)
    STS_KEY=$(jq -r .Credentials.SecretAccessKey session-credentials.json)
    STS_TOKEN=$(jq -r .Credentials.SessionToken session-credentials.json)

    echo "# Using STS credentials, expected to see the Role Name ARN: $ROLE_NAME_ARN"
    AWS_ACCESS_KEY_ID=${STS_ID} \
        AWS_SECRET_ACCESS_KEY=${STS_KEY} \
        AWS_SESSION_TOKEN=${STS_TOKEN} \
        aws sts get-caller-identity

    # RunInstnace
    oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=worker -o json |jq '.items[0]' > worker.json

    # Setting default machine path (if there's no custom fields, otherwise you should adapt it)
    REGION=$(jq -r '.metadata.labels["machine.openshift.io/region"]' worker.json)
    AMI_ID=$(jq -r .spec.providerSpec.value.ami.id worker.json)

    CLUSTER_ID=$(jq -r '.metadata.labels["machine.openshift.io/cluster-api-cluster"]' worker.json)
    INSTANCE_TYPE=$(jq -r .spec.providerSpec.value.instanceType worker.json)
    USER_DATA_SECRET=$(jq -r .spec.providerSpec.value.userDataSecret.name worker.json)
    SUBNET_NAME=$(jq -r .spec.providerSpec.value.subnet.filters[].values[] worker.json)
    SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=${SUBNET_NAME}" \
    --query 'Subnets[].SubnetId' \
    --output text)
    SG_NAME=$(jq -r .spec.providerSpec.value.securityGroups[].filters[].values[0] worker.json)
    SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=${SG_NAME}" \
    --query 'SecurityGroups[].GroupId' \
    --output text)

    INSTANCE_NAME="${CLUSTER_ID}-test-RunInstance-01"

    # Extract user data
    USER_DATA_FILE=worker-user-data.txt
    oc get secret \
    -n openshift-machine-api ${USER_DATA_SECRET} \
    -o jsonpath="{.data.userData}" \
    | base64 -d > ${USER_DATA_FILE}

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

run_instance_worker | tee -a cco-check-run-worker.log
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
