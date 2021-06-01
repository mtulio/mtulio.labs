# AWS IAM

## Setting up Cross account using temporary KMS

in short:
  Scenário: AccountA has a DynamoDB table that must be access from instance from AccountB
  
* [AccountA] Create KMS for instance role from AccountB
* [AccountA] Create IAM role in AccountA with these permissions to give access to DynamoDB and KMS:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "kms:Decrypt"
            ],
            "Effect": "Allow",
            "Resource": "arn:aws:kms:us-east-1:AccountA:key/b535d0f6-299f-4499-bf69-c19c63d822b1"
        },
        {
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Effect": "Allow",
            "Resource": "arn:aws:dynamodb:us-east-1:AccountA:table/my-table"
        }
    ]
}
```
* [AccountB] Give the IAM role with **inline policy** to assume role in AccountA:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Resource": "arn:aws:iam::AccountA:role/accountb-instance-role-dynamodb"
        }
    ]
}
```
* [AccountA] Give the IAM role a Trust Relationship that looks like:
```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::AccountB:role/instance-role"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```
* [AccountB] access SSH instance and create the script to get temporary KMS credentials.
* [AccountB][instance ssh] create the script to generate credentials:
```
#!/bin/bash -e
#
# Adapted from https://gist.github.com/ambakshi/ba0fe456bb6da24da7c2
#
# Clear out existing AWS session environment, or the awscli call will fail
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
ROLE_ARN="${1:-arn:aws:iam::AccountA:role/accountb-instance-role-dynamodb}"
DURATION="${2:-900}"
NAME="${3:-$LOGNAME@`hostname -s`}"
# KST=access*K*ey, *S*ecretkey, session*T*oken
KST=(`aws sts assume-role --role-arn "${ROLE_ARN}" \
                          --role-session-name "${NAME}" \
                          --duration-seconds ${DURATION} \
                          --query '[Credentials.AccessKeyId,Credentials.SecretAccessKey,Credentials.SessionToken]' \
                          --output text`)
echo 'export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}'
echo "export AWS_ACCESS_KEY_ID='${KST[0]}'"
echo "export AWS_SECRET_ACCESS_KEY='${KST[1]}'"
echo "export AWS_SESSION_TOKEN='${KST[2]}'"      # older var seems to work the same way
echo "export AWS_SECURITY_TOKEN='${KST[2]}'"
```
* [AccountB][instance ssh] export credentials each time you want to access the resource (DynamoDB)
```
eval $(./iam-assume-role.sh)
```
* [AccountB][instance ssh] Just test the sync with table:
```
AWS_DEFAULT_REGION="us-east-1" aws dynamodb scan --table-name my-table
```
1. http://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html
1. https://github.com/fugue/credstash/wiki/Setting-up-cross-account-access
