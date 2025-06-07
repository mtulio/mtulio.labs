# Validate IAM Policy for user when running ccoctl with flag `--create-private-s3-bucket`

- Create IAM User

```bash
export IAM_USER_NAME=tmp-test-ccoctl-cfn
aws iam create-user --user-name $IAM_USER_NAME
```

- Create the inline policy

```bash
cat <<EOF > ./ccoctl-aws-create-all.json
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
                "s3:PutObjectTagging"
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

aws iam put-user-policy --user-name $IAM_USER_NAME --policy-name ccoctl-create-all --policy-document file://ccoctl-aws-create-all.json
```

- Generate AK/SK

```bash
aws iam create-access-key --user-name $IAM_USER_NAME | tee ./user-ak.json
```

- Create the Profile and export it

```bash
cat <<EOF >> ~/.aws/credentials
[$IAM_USER_NAME]
aws_access_key_id=$(jq -r .AccessKey.AccessKeyId ./user-ak.json)
aws_secret_access_key=$(jq -r .AccessKey.SecretAccessKey ./user-ak.json)
EOF

export AWS_PROFILE=$IAM_USER_NAME
```

- Get caller ID

```bash
$ aws sts get-caller-identity | jq .Arn
"arn:aws:iam::[redacted:ACCOUN_ID]:user/tmp-test-ccoctl-cfn"
```

- Download ccoctl

```bash
OCP_VERSION=4.13.0
oc image extract $(oc adm release info --image-for='cloud-credential-operator' $OCP_VERSION) \
    --file="/usr/bin/ccoctl" \
    -a ${PULL_SECRET_FILE}
chmod u+x ./ccoctl
```

- Extract CredentialsRequests

```bash
oc adm release extract \
--credentials-requests \
--cloud=aws \
--to=$PWD/credrequests \
--from=$(oc adm release info $OCP_VERSION -o jsonpath='{.image}' 2>/dev/null)
```

- Create resources

```bash
./ccoctl aws create-all \
  --name=$IAM_USER_NAME \
  --region=us-east-1 \
  --credentials-requests-dir=./credrequests \
  --output-dir=./ \
  --create-private-s3-bucket
```

- Destroy

```bash
./ccoctl aws create-all --name=$IAM_USER_NAME --region=us-east-1
```
