
Lab to validate accessing shared hosted zone from a different account.

Steps:

- Create IAM Role on Account A
- Create VPC on Account A
- Create Privated Hosted Zone on Account A, associating to VPC
- Create IAM Role on Account A with the following Trusted Policy

> TODO need to improve to not allow root, but specificy identity

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::[redacted:Account_B_ID]:root"
            },
            "Action": "sts:AssumeRole",
            "Condition": {}
        }
    ]
} 
```
- Attach the IAM Policy to the IAM Role:
> The ideal world need to allow only the principal of the IAM Role on Account A
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:GetHostedZone",
                "route53:ChangeTagsForResource"
            ],
            "Resource": "*"
        }
    ]
} 
```
- Create the AWS credentials file
```
[default]
aws_access_key_id = AKIAXXX
aws_secret_access_key = XXX

[openshift-shared-vpc]
role_arn=arn:aws:iam::[redacted:Account_A_ID]:role/test-shared-vpc
source_profile=default    
```
- Call the CLI to test it

```json
 $ AWS_PROFILE=openshift-shared-vpc aws sts get-caller-identity
{
    "UserId": "AROAXXXX:botocore-session-1682612666",
    "Account": "[redacted:Account_A_ID]",
    "Arn": "arn:aws:sts::[redacted:Account_A_ID]:assumed-role/test-shared-vpc/botocore-session-XXX"
}
```
- Build and run the code (instructions below)


## Build


```bash
go build
```

## Run

```bash
LAB_AWS_REGION="us-east-2" \
    LAB_KEY_PREFIX="me" \
    LAB_HOSTEDZONE="ZXXXX" \
    ./aws-tag-external-hostedzone
```

Expected results

```
$ LAB_AWS_REGION="us-east-2" \
>     LAB_KEY_PREFIX="me" \
>     LAB_HOSTEDZONE="ZXXXX" \
>     ./aws-tag-external-hostedzone
Attempting tagging with default session
===ERROR===
(*awserr.requestError)(0xc0000a2ec0)(AccessDenied: User: arn:aws:iam::[redacted:Account_B_ID]:user/myuser is not authorized to access this resource
	status code: 403, request id: 2daf1ad7-2baf-403d-8075-38a80337babf)
Attempting tagging with named profile to assume role in phz account
Success!
```