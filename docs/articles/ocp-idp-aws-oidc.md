# Deep Dive into AWS OIDC identity provider when installing OpenShift with IAM STS (“manual-STS”) support

> Status: WIP

> Preview on [Dev.to](https://dev.to/mtulio/enhance-the-security-options-when-installing-openshift-with-iam-sts-manual-sts-on-aws-5048-temp-slug-3197013?preview=c9e9beb6b5be97e7b8f79527107c7a54847f6a62fab5d2735727e5875f1db843dfb3bfaf4907c49c6628b9014b72f40fc655ff604a033ba604e253ff)

> [PR to Collab](https://github.com/mtulio/mtulio.labs/pull/8) (feel free to review)

> [PR Preview](https://mtuliolabs-git-article-ocp-aws-idp-oidc-mtulio.vercel.app/articles/ocp-idp-aws-oidc/?h=oidc)

Hey! o/

Today I will share some options to install store OpenShift in AWS using IAM STS / manual-STS mode.

## Recap

IAM STS is the best way to provide credentials to access AWS resources as it uses short-lived.

When the application which wants to consume AWS services is the other AWS service (EC2, ECS, Lambda, etc) or application running in any AWS service, usually it uses temporary credentials provided by authentication service (EC2 is the metadata services / IMDS) to assume the role and get the temporary credentials from STS.

When the service is external from AWS (example mobile App), or it uses shared resources (like Kubernetes/OpenShift cluster running in EC2) it needs an extra layer of authentication to avoid any application be able to assume the role allowed by the service (example EC2 instance profile).

For that reason there is the managed service IAM OIDC (which implements OpenID spec) to allow from external services federating access to AWS services through STS when assuming the AWS IAM Role.

Basically the Kubernetes API Server uses the private key to sign service account tokens (JWT), the external service uses that token authenticate the STS API call method AssumeRoleWithWebIdentity informing the IAM Role name desired to be assumed, then the STS service access the **OIDC to validate it by accessing the JWTS files stored on the public URL**, once the token is validated, the IAM Role will be assumed with short-lived credentials returned to the service, then the service can authenticate on the target service endpoint API (S3, EC2, etc).

In OpenShift every cluster service that need to interact with AWS has one different token signed by KAS and IAM Role. Example of services:

- Machine API to create EC2
- Image Registry to create S3 Buckets
- CSI to create EBS block storage

Said that, let’s recap the steps to install OpenShift on AWS with manual-STS:

1. create config
2. Set to manual
3. Create the manifests
4. Extract the credentials requests
5. Process it creating the IAM roles
6. Generate the keys
7. Create the bucket
8. Upload the keys
9. Create the OIdC
10. Save the bucket UrL to manifest
11. Install the cluster

## Problem statement

The endpoint stores the JWKS keys should be public, as the OIDC will access the endpoint available on the JWT token when it is send by STS API call AssumeRoleWithWebIdentity. You can take a look into those items to confirm it:
- Enable the S3 bucket access log
- Filter the events to access the Bucket on the CloudTrail

The main motivation to write this article is that AWS accounts has restrictions on public S3 Bucket, so it needs more options to serve the files accessed by AWS IAM OpenID Connector.

The flow is something like that:

<diagram>

Said that, let me share some options to install a cluster using different approaches that should not impacting in the IAM OIDC managed service requirements.

## Installing a cluster with manual-STS

> "Option#0 : default store in public S3 bucket"

> Steps described on [Official documentation](https://docs.openshift.com/container-platform/4.10/authentication/managing_cloud_provider_credentials/cco-mode-sts.html#cco-mode-sts)


> TODO

Requirements:
- Export the `PULL_SECRET_FILE` pointing to your pull-secret file
```bash
export CLUSTER_NAME="oidc-def"
export CLUSTER_REGION=us-east-1
export VERSION=4.10.16
export PULL_SECRET_FILE=${HOME}/.openshift/pull-secret-latest.json

export SSH_PUB_KEY_FILE="${HOME}/.ssh/id_rsa.pub"
export OUTPUT_DIR_CCO="${PWD}/${CLUSTER_NAME}-cco/"
export INSTALL_DIR="${PWD}/${CLUSTER_NAME}-installer"
```

Steps:

- Get the clients (installer + oc)

```bash
oc adm release extract \
    --tools quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64 \
    -a ${PULL_SECRET_FILE}

tar xvfz openshift-client-linux-${VERSION}.tar.gz
tar xvfz openshift-install-linux-${VERSION}.tar.gz
```

- Get the cco utility

```bash
RELEASE_IMAGE=$(./openshift-install version | awk '/release image/ {print $3}')
CCO_IMAGE=$(oc adm release info --image-for='cloud-credential-operator' $RELEASE_IMAGE)
./oc image extract $CCO_IMAGE --file="/usr/bin/ccoctl" -a ${PULL_SECRET_FILE}
chmod 775 ccoctl
./ccoctl --help
```

- Setup the OIDC files

```bash
mkdir -p ${OUTPUT_DIR_CCO}
./ccoctl aws create-key-pair --output-dir ${OUTPUT_DIR_CCO}
```

- Create the OIDC (Should be change every option)

```bash
./ccoctl aws create-identity-provider \
    --name=${CLUSTER_NAME} \
    --region=${CLUSTER_REGION} \
    --public-key-file=${OUTPUT_DIR_CCO}/serviceaccount-signer.public \
    --output-dir=${OUTPUT_DIR_CCO}/
```

> A new bucket will be created
> `/keys.json` object will be generated and upload to bucket. This contain public information of OpenID and JWKS Keys. More [info about JWK Key Object](https://openid.net/specs/draft-jones-json-web-key-03.html)
> `/.well-know/openid-configuration` object will also upload with public information
> The file `$OUTPUT_DIR_CCO/manifests/cluster-authentication-02-config.yaml` will be created containing the IAM OIDC Issuer URI


- Extract the `CredentialRequests`

```bash
./oc adm release extract --credentials-requests \
    --cloud=aws \
    --to=${OUTPUT_DIR_CCO}/credrequests \
    ${RELEASE_IMAGE}
```

- Create the IAM Roles

```bash
AWS_IAM_OIDP_ARN=$(aws iam list-open-id-connect-providers \
    | jq -r ".OpenIDConnectProviderList[] | \
        select(.Arn | contains(\"${CLUSTER_NAME}-oidc\") ).Arn")
./ccoctl aws create-iam-roles \
    --name=${CLUSTER_NAME} \
    --region=${CLUSTER_REGION}\
    --credentials-requests-dir=${OUTPUT_DIR_CCO}/credrequests \
    --identity-provider-arn=${AWS_IAM_OIDP_ARN} \
    --output-dir ${OUTPUT_DIR_CCO}
```

- Gen install config

```bash
mkdir -p ${INSTALL_DIR}
cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: devcluster.openshift.com
credentialsMode: Manual
compute:
- name: worker
  replicas: 2
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: us-east-1
    defaultMachinePlatform:
      zones:
      - ${CLUSTER_REGION}a
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
./openshift-install create manifests --dir $INSTALL_DIR
```

- Copy manifests to install-dir

```
cp -rvf ${OUTPUT_DIR_CCO}/manifests/* ${INSTALL_DIR}/manifests
cp -rvf ${OUTPUT_DIR_CCO}/tls ${INSTALL_DIR}/
```

- Create a cluster

```bash
./openshift-install create cluster --dir $INSTALL_DIR
```

## Option#1: Serve URL using CloudFront, storing in S3 restricted

The procedures below describes how to deploy OpenShift cluster
with manual-STS with a private bucket to store JWKS files.

The JWKS files should be public accessible by the identity provider IAM OIDC, which is managed service (externally of cluster's VPC).

The flow expected to assume a role using IOpenID basically is:
- Client makes the API call AssumeRoleWithWebIdentity with JWT  signed by kube-apiserver containg the issuer URL
- The STS service access the issuer_url publically to retrieve openid-configuration and keys.json
- Token is validated, IAM Role assumed and STS credentials are returned to caller

```
service/pod > IAM STS > IAM OIDC > ISSUER_URI
```

The solution described here changes the ISSUER_URI from S3 to CloudFront, making the S3 Bucket privately, serving as an origin of CloudFront distribution.

```
service/pod > IAM STS > IAM OIDC > ISSUER_URI(CloudFront) > S3(restricted by OAI)
```

Step-by-step:

- Adjust and export the environment variables

```bash
export CLUSTER_NAME="mrb-sts"

export CLUSTER_REGION=us-east-1
export VERSION=4.10.16
export PULL_SECRET_FILE=${HOME}/.openshift/pull-secret-latest.json
export SSH_PUB_KEY_FILE="${HOME}/.ssh/id_rsa.pub"

export OUTPUT_DIR_CCO="${PWD}/${CLUSTER_NAME}-cco"
export INSTALL_DIR="${PWD}/${CLUSTER_NAME}-installer"

mkdir -p ${OUTPUT_DIR_CCO}
mkdir -p ${INSTALL_DIR}
```

- Create installer manifests

```bash
mkdir -p $INSTALL_DIR_CFN
cat <<EOF > ${INSTALL_DIR_CFN}/install-config.yaml
apiVersion: v1
baseDomain: devcluster.openshift.com
credentialsMode: Manual
compute:
- name: worker
  replicas: 2
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: us-east-1
    defaultMachinePlatform:
      zones:
      - ${CLUSTER_REGION}a
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
./openshift-install create manifests --dir ${INSTALL_DIR}
```

- Get clusterID

```bash
CLUSTER_ID="$(yq -r .status.infrastructureName ${INSTALL_DIR}/manifests/cluster-infrastructure-02-config.yml)"
```

- create origin identity

```bash
OIDC_BUCKET_NAME="${CLUSTER_NAME}-oidc"
aws cloudfront create-cloud-front-origin-access-identity \
    --cloud-front-origin-access-identity-config \
        CallerReference="${OIDC_BUCKET_NAME}",Comment="OAI-${OIDC_BUCKET_NAME}"

ORIGIN_IDENTITY_CFN_ID=$(aws cloudfront \
    list-cloud-front-origin-access-identities \
    --query "CloudFrontOriginAccessIdentityList.Items[?Comment==\`OAI-${OIDC_BUCKET_NAME}\`].Id" \
    --output text)
```

- Update bucket policy

```bash
cat <<EOF | envsubst > ${CLUSTER_NAME}-oidc-bucket-policy.json
{
    "Version": "2008-10-17",
    "Id": "PolicyForCloudFrontPrivateContent",
    "Statement": [
        {
            "Sid": "1",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${ORIGIN_IDENTITY_CFN_ID}"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${OIDC_BUCKET_NAME}/*"
        }
    ]
}
EOF

aws s3api create-bucket \
    --bucket ${OIDC_BUCKET_NAME} \
    --acl private

aws s3api put-bucket-policy \
    --bucket ${OIDC_BUCKET_NAME} \
    --policy file://${CLUSTER_NAME}-oidc-bucket-policy.json

aws s3api put-public-access-block \
    --bucket ${OIDC_BUCKET_NAME} \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

- create distribution
```bash

cat <<EOF | envsubst > ${CLUSTER_ID}-oidc-cloudfront.json
{
    "DistributionConfig": {
        "CallerReference": "${CLUSTER_NAME}",
        "Aliases": {
            "Quantity": 0
        },
        "Origins": {
            "Quantity": 1,
            "Items": [
            {
                "Id": "${OIDC_BUCKET_NAME}.s3.us-east-1.amazonaws.com",
                "DomainName": "${OIDC_BUCKET_NAME}.s3.us-east-1.amazonaws.com",
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0
                },
                "S3OriginConfig": {
                    "OriginAccessIdentity": "origin-access-identity/cloudfront/${ORIGIN_IDENTITY_CFN_ID}"
                },
                "ConnectionAttempts": 3,
                "ConnectionTimeout": 10,
                "OriginShield": {
                "Enabled": false
                }
            }
            ]
        },
        "DefaultCacheBehavior": {
            "TargetOriginId": "${OIDC_BUCKET_NAME}.s3.us-east-1.amazonaws.com",
            "TrustedSigners": {
                "Enabled": false,
                "Quantity": 0
            },
            "TrustedKeyGroups": {
                "Enabled": false,
                "Quantity": 0
            },
            "ViewerProtocolPolicy": "https-only",
            "AllowedMethods": {
                "Quantity": 2,
                "Items": [
                    "HEAD",
                    "GET"
                ],
                "CachedMethods": {
                    "Quantity": 2,
                    "Items": [
                        "HEAD",
                        "GET"
                    ]
                }
            },
            "SmoothStreaming": false,
            "Compress": false,
            "LambdaFunctionAssociations": {
                "Quantity": 0
            },
            "FunctionAssociations": {
                "Quantity": 0
            },
            "FieldLevelEncryptionId": "",
            "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
        },
        "CacheBehaviors": {
            "Quantity": 0
        },
        "CustomErrorResponses": {
            "Quantity": 0
        },
        "Comment": "${CLUSTER_NAME}",
        "Logging": {
            "Enabled": false,
            "IncludeCookies": false,
            "Bucket": "",
            "Prefix": ""
        },
        "PriceClass": "PriceClass_All",
        "Enabled": true,
        "ViewerCertificate": {
            "CloudFrontDefaultCertificate": true
        }
    },
    "Tags": {
        "Items": [
            {
                "Key": "Name",
                "Value": "${CLUSTER_NAME}"
            }
        ]
    }
}
EOF

aws cloudfront create-distribution-with-tags \
    --distribution-config-with-tags \
    file://${CLUSTER_ID}-oidc-cloudfront.json
```

- Get CFN URL

```bash
OIDC_URI=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Comment==\`${CLUSTER_NAME}\`].DomainName" \
    --output text)

echo ${OIDC_URI}
```

- Generate cco files without creating resources
```bash
./ccoctl aws create-key-pair --output-dir ${OUTPUT_DIR_CCO}
./ccoctl aws create-identity-provider \
    --name=${CLUSTER_NAME} \
    --region=${CLUSTER_REGION} \
    --public-key-file=${OUTPUT_DIR_CCO}/serviceaccount-signer.public \
    --output-dir=${OUTPUT_DIR_CCO}/ \
    --dry-run
```

- Update the OIDC URI to CloudFront:

0. Create bucket content dir

```bash
mkdir -p ${OUTPUT_DIR_CCO}-bucket-content/.well-known
```

1. OpenID Config
```bash
cat ${OUTPUT_DIR_CCO}/02-openid-configuration \
    | sed "s/https:\/\/${CLUSTER_NAME}[a-z.-].*\//https:\/\/${OIDC_URI}\//" \
    | sed "s/https:\/\/${CLUSTER_NAME}[a-z.-].*/https:\/\/${OIDC_URI}\",/" \
    > ${OUTPUT_DIR_CCO}-bucket-content/.well-known/openid-configuration
```

2. Keys.json

```bash
cp -v ${OUTPUT_DIR_CCO}/03-keys.json \
    ${OUTPUT_DIR_CCO}-bucket-content/keys.json
```

4. cluster-authentication-02-config.yaml

```bash
sed -i "s/https:\/\/[a-z.-].*/https:\/\/${OIDC_URI}/" \
    ${OUTPUT_DIR_CCO}/manifests/cluster-authentication-02-config.yaml
```

5. IdP Config

```bash
sed -i "s/https:\/\/[a-z.-].*/https:\/\/${OIDC_URI}\",/" \
    ${OUTPUT_DIR_CCO}/04-iam-identity-provider.json
jq . ${OUTPUT_DIR_CCO}/04-iam-identity-provider.json
```

- Upload the content to bucket

```bash
aws s3 sync ${OUTPUT_DIR_CCO}-bucket-content/ s3://${OIDC_BUCKET_NAME}
```

- Make sure you can access the content through public URL

```bash
curl https://${OIDC_URI}/keys.json
curl https://${OIDC_URI}/.well-known/openid-configuration
```

- Create the IdP

```bash
aws iam create-open-id-connect-provider \
    --cli-input-json file://${OUTPUT_DIR_CCO}/04-iam-identity-provider.json \
    > ${OUTPUT_DIR_CCO}/04-iam-identity-provider-object.json 

OIDC_ARN=$(jq -r .OpenIDConnectProviderArn ${OUTPUT_DIR_CCO}/04-iam-identity-provider-object.json)

echo $OIDC_ARN
```

- Extract CredentialRequests from Release image

```bash
./oc adm release extract --credentials-requests \
    --cloud=aws \
    --to=${OUTPUT_DIR_CCO}/credrequests \
    ${RELEASE_IMAGE}
```

- Create IAM Roles

```bash
./ccoctl aws create-iam-roles \
    --name=${CLUSTER_NAME} \
    --region=${CLUSTER_REGION}\
    --credentials-requests-dir=${OUTPUT_DIR_CCO}/credrequests \
    --identity-provider-arn=${OIDC_ARN} \
    --output-dir ${OUTPUT_DIR_CCO}
```

- Copy manifests to install-dir

```
cp -rvf ${OUTPUT_DIR_CCO}/manifests/* ${INSTALL_DIR}/manifests
cp -rvf ${OUTPUT_DIR_CCO}/tls ${INSTALL_DIR}/
```

- Create a cluster

```bash
./openshift-install create cluster \
    --dir $INSTALL_DIR \
    --log-level debug
```


### Cluster review / post-install

- Install logs

```
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.mrb-sts.devcluster.openshift.com 

DEBUG Time elapsed per stage:                      
DEBUG            cluster: 6m26s                    
DEBUG          bootstrap: 50s                      
DEBUG Bootstrap Complete: 9m43s                    
DEBUG                API: 2m1s                     
DEBUG  Bootstrap Destroy: 55s                      
DEBUG  Cluster Operators: 9m40s                    
INFO Time elapsed: 27m58s  
```

- Get Authentication CRD URL

```bash
$ oc get authentication cluster -o json |jq .spec.serviceAccountIssuer
"https://d15diimhmpdwiy.cloudfront.net"
```

- Check if CO are available

```bash
# CO Available
$ oc get co  -o json \
    | jq -r ".items[].status.conditions[] | select(.type==\"Available\").status" | sort |uniq -c
32 True

# COs Degraded
$ oc get co -o json \
    | jq -r ".items[].status.conditions[] | select(.type==\"Degraded\").status" | sort |uniq -c
32 False
```

- Deep dive into Machine API credentials

```bash
$ oc get co machine-api
NAME          VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
machine-api   4.10.16   True        False         False      17m     
```

- Check Credential presented to Componenet

```bash
oc get secrets aws-cloud-credentials -n openshift-machine-api -o jsonpath='{.data.credentials}'|base64 -d
[default]
role_arn = arn:aws:iam::${ACCOUNT_ID}:role/oidc-def-openshift-machine-api-aws-cloud-credentials
web_identity_token_file = /var/run/secrets/openshift/serviceaccount/token
```

- Get Token

<!--
https://guifreelife.com/blog/2022/03/10/Debugging-AWS-STS-Authentication-for-OpenShift-Operators/
-->

```bash
TOKEN_PATH=$(oc get secrets aws-cloud-credentials -n openshift-machine-api -o jsonpath='{.data.credentials}'|base64 -d |grep ^web |awk '{print$3}')
CAPI_POD=$(oc get pods -n openshift-machine-api -l api=clusterapi -o jsonpath='{.items[*].metadata.name}')
TOKEN=$(oc exec  -n openshift-machine-api ${CAPI_POD} -c machine-controller -- cat ${TOKEN_PATH})
```

- Inspect Key ID

```bash
$ echo $TOKEN | awk -F. '{ print $1 }' | base64 -d 2>/dev/null | jq .alg
"RS256"

```

- Inspect Token Issuer URI

```bash
$ echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null | jq .iss
"https://d15diimhmpdwiy.cloudfront.net"
```

All set!

## Option#2: Serve URL with direct Lambda endpoint

> TODO

## Option#3: Serve URL with APIGW, proxying to Lambda function

> TODO

## Option#4: Serve URL with ALB, using Lambda function as target

> TODO

## Option#5: Serve URL direct from hosted webserver  

> TODO
