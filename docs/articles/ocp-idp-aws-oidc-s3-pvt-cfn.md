# Installing OpenShift in AWS with STS (manual-STS) using private S3 Bucket for an OpenID Connect endpoint

In this article, I will share hands-on steps to replace the default public endpoint used by IAM OpenID Connect (OIDC) from a public S3 Bucket to a CloudFront Distribution URL, when installing an OpenShift cluster with STS support.


## Table Of Contents
  * [Summary](#summary)
    * [Quick recap](#summary-recap)
    * [Goal](#summary-goal)
  * [Steps](#steps)
    * [Requirements](#step-requirements)
    * [Setup](#step-setup)
    * [Creating Installer Manifests](#step-create-manifests)
    * [Creating Origin Access Identity](#step-create-oai)
    * [Creating Bucket](#step-create-bucket)
    * [Creating CloudFront Distribution](#step-create-cloudfront-dist)
    * [Generating OIDC configuration and keys](#step-gen-oidc)
    * [Creating the OpenID Connector identity provider](#step-create-oidc)
    * [Creating IAM Roles](#step-create-iam-roles)
    * [Creating the Cluster](#step-create-cluster)
  * [Post-installation review and tests](#post-review)
    * [Installer overview](#post-review-installer)
    * [Component overview](#post-review-component)
    * [Testing the token with `AssumeRoleWithWebIdentity`](#post-review-test-token)
  * [Solution Review](#solution-review)
  * [Conclusion](#conclusion)
  * [References](#references)

## Summary<a name="summary"></a>

### _Quick recap_<a name="summary-recap"></a>

The endpoint identifier, that also names the OpenID Connector resource, should be public access as it's used by IAM managed service to retrieve the public keys (JWKS) used on `ProjectedServiceAccountToken` JSON web tokens. This way external systems, like IAM, can validate and accept the Kubernetes-issued OIDC tokens.

The `ccoctl` is the utility used to automate the OIDC setup to install an OpenShift cluster in AWS with STS support.

Currently, the default `ccoctl` deployment creates one public S3 Bucket per cluster with JWKS objects, directly exposing the Bucket's URL the OIDC discovery endpoint. In some AWS Accounts, public buckets or objects are unwanted or blocked. This is the main motivation to explore this topic and share some options we have nowadays to use a Bucket in a more restrictive mode.

If you would like to know more about this topic, I highly advise you read:
- [AWS Doc: Restricting access to Amazon S3 content by using an origin access identity (OAI)](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [Blog: Deep Dive into AWS OIDC identity provider when installing OpenShift with IAM STS (“manual-STS”) support](https://dev.to/mtulio/enhance-the-security-options-when-installing-openshift-with-iam-sts-manual-sts-on-aws-5048-temp-slug-3197013?preview=c9e9beb6b5be97e7b8f79527107c7a54847f6a62fab5d2735727e5875f1db843dfb3bfaf4907c49c6628b9014b72f40fc655ff604a033ba604e253ff)

### _Goal_<a name="summary-goal"></a>

We will walk through those steps to:
- create one CloudFront Distribution to be used as the public endpoint for OIDC
- create one private S3 Bucket
- create one [origin access identity (OAI) to access the S3 from CloudFront Distribution](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- patch the JWKS files with the new CloudFront Distribution URL when setting up the [manual-STS](https://docs.openshift.com/container-platform/4.10/authentication/managing_cloud_provider_credentials/cco-mode-sts.html#cco-mode-sts) during the OpenShift installation
- create the OIDC identity provider using the CloudFront URL
- create the IAM Roles with Trusted Policy allowing Federated OIDC service ARN with proper service account restrictions
- create the OpenShift cluster with STS support with no public buckets

## Steps<a name="steps"></a>

### Requirements<a name="step-requirements"></a>

- OpenShift installer client (`openshift-installer`)
- OpenShift client (`oc`)
- `ccoctl` utility
- AWS credentials with permissions to install a cluster with manual-STS support
- aws-cli
- jq
- yq

### Setup<a name="step-setup"></a>

- Adjust and export the environment variables

```bash
export CLUSTER_NAME="my-sts"
export BASE_DOMAIN="devcluster.example.com"

export CLUSTER_REGION=us-east-1
export VERSION=4.10.16
export PULL_SECRET_FILE=${HOME}/.openshift/pull-secret-latest.json
export SSH_PUB_KEY_FILE="${HOME}/.ssh/id_rsa.pub"

export WORKDIR="${CLUSTER_NAME}"
export DIR_CCO="${WORKDIR}/cco"
export DIR_INSTALLER="${WORKDIR}/installer"
export OIDC_BUCKET_NAME="${CLUSTER_NAME}-oidc"
export OIDC_BUCKET_CONTENT="${WORKDIR}/bucket-content"

mkdir -p ${WORKDIR}/{cco,installer,bucket-content}
```

- Install the clients (optional): `oc`, `openshift-installer` and `ccoctl`

```bash
# oc and openshift-install
oc adm release extract \
    --tools quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64 \
    -a ${PULL_SECRET_FILE}

tar xvfz openshift-client-linux-${VERSION}.tar.gz
tar xvfz openshift-install-linux-${VERSION}.tar.gz

# ccoctl
RELEASE_IMAGE=$(./openshift-install version \
    | awk '/release image/ {print $3}')
CCO_IMAGE=$(./oc adm release info \
    --image-for='cloud-credential-operator' \
    ${RELEASE_IMAGE})

./oc image extract ${CCO_IMAGE} \
    --file="/usr/bin/ccoctl" \
    -a ${PULL_SECRET_FILE}

chmod 775 ccoctl
```

You must now be able to see the client's binaries in your current directory.

### Create the Installer manifests<a name="step-create-manifests"></a>

- Create the installer configuration

> This is the only mandatory change: `credentialsMode: Manual`

```bash
cat <<EOF > ${DIR_INSTALLER}/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
credentialsMode: Manual
compute:
- name: worker
  replicas: 2
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${CLUSTER_REGION}
    defaultMachinePlatform:
      zones:
      - ${CLUSTER_REGION}a
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

echo "# Backup install-config.yaml (Optional)"
cp -v ${DIR_INSTALLER}/install-config.yaml \
    ${DIR_INSTALLER}/install-config-bkp.yaml
```

- Create the Installer manifests

```bash
./openshift-install create manifests \
    --dir ${DIR_INSTALLER}
```

- Set the `CLUSTER_ID` environment variable

```bash
CLUSTER_ID="$(yq -r .status.infrastructureName \
    ${DIR_INSTALLER}/manifests/cluster-infrastructure-02-config.yml)"
```

### Create the Origin Access Identity<a name="step-create-oai"></a>

Steps to create the Origin Access Identity (OAI) to be used to access the bucket through CloudFront Distribution:

- Create the OAI and set the variable `OAI_CLODUFRONT_ID`:

```bash
aws cloudfront create-cloud-front-origin-access-identity \
    --cloud-front-origin-access-identity-config \
    CallerReference="${OIDC_BUCKET_NAME}",Comment="OAI-${OIDC_BUCKET_NAME}"

OAI_CLODUFRONT_ID=$(aws cloudfront \
    list-cloud-front-origin-access-identities \
    --query "CloudFrontOriginAccessIdentityList.Items[?Comment==\`OAI-${OIDC_BUCKET_NAME}\`].Id" \
    --output text)
```

### Create the Bucket<a name="step-create-bucket"></a>

- Create the private Bucket

```bash
aws s3api create-bucket \
    --bucket ${OIDC_BUCKET_NAME} \
    --acl private
```

- Create the Bucket Policy document, that allows OAI to retrieve objects

```bash
cat <<EOF | envsubst > ${WORKDIR}/oidc-bucket-policy.json
{
    "Version": "2008-10-17",
    "Id": "PolicyForCloudFrontPrivateContent",
    "Statement": [
        {
            "Sid": "1",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${OAI_CLODUFRONT_ID}"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${OIDC_BUCKET_NAME}/*"
        }
    ]
}
EOF
```

- Apply the policy to the Bucket and block public access

```bash
aws s3api put-bucket-policy \
    --bucket ${OIDC_BUCKET_NAME} \
    --policy file://${WORKDIR}/oidc-bucket-policy.json

aws s3api put-public-access-block \
    --bucket ${OIDC_BUCKET_NAME} \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

## Create CloudFront Distribution<a name="step-create-cloudfront-dist"></a>

- Create the Distribution document

```bash
cat <<EOF | envsubst > ${WORKDIR}/oidc-cloudfront.json
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
                "Id": "${OIDC_BUCKET_NAME}.s3.${CLUSTER_REGION}.amazonaws.com",
                "DomainName": "${OIDC_BUCKET_NAME}.s3.${CLUSTER_REGION}.amazonaws.com",
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0
                },
                "S3OriginConfig": {
                    "OriginAccessIdentity": "origin-access-identity/cloudfront/${OAI_CLODUFRONT_ID}"
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
            "TargetOriginId": "${OIDC_BUCKET_NAME}.s3.${CLUSTER_REGION}.amazonaws.com",
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
```

- Create the CloudFront Distribution with Tags

```bash
aws cloudfront create-distribution-with-tags \
    --distribution-config-with-tags \
    file://${WORKDIR}/oidc-cloudfront.json
```

- Wait until the Distribution has been created

- Get the CloudFront Distribution URL

```bash
CLOUDFRONT_URI=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Comment==\`${CLUSTER_NAME}\`].DomainName" \
    --output text)

echo ${CLOUDFRONT_URI}
```

Make sure you can see the URL.

### Generate the OIDC configuration and keys<a name="step-gen-oidc"></a>

- Generate the key pair used to create the service account tokens

```bash
./ccoctl aws create-key-pair \
    --output-dir ${DIR_CCO}
```

- Generate the OpenID Connect configuration

```bash
./ccoctl aws create-identity-provider \
    --name=${CLUSTER_NAME} \
    --region=${CLUSTER_REGION} \
    --public-key-file=${DIR_CCO}/serviceaccount-signer.public \
    --output-dir=${DIR_CCO}/ \
    --dry-run
```

- Update the S3 Bucket URL endpoint to the CloudFront Distribution endpoint:

A. Patch the issuer URL onto the OIDC configuration file `/.well-known/openid-configuration`

```bash
mkdir -p ${OIDC_BUCKET_CONTENT}/.well-known
cat ${DIR_CCO}/02-openid-configuration \
    | sed "s/https:\/\/${CLUSTER_NAME}[a-z.-].*\//https:\/\/${CLOUDFRONT_URI}\//" \
    | sed "s/https:\/\/${CLUSTER_NAME}[a-z.-].*/https:\/\/${CLOUDFRONT_URI}\",/" \
    > ${OIDC_BUCKET_CONTENT}/.well-known/openid-configuration
```

B. Copy the `keys.json`

```bash
cp -v ${DIR_CCO}/03-keys.json \
    ${OIDC_BUCKET_CONTENT}/keys.json
```

C. Patch the issuer URL onto `Authentication` custom resource in `cluster-authentication-02-config.yaml`

```bash
sed -i "s/https:\/\/[a-z.-].*/https:\/\/${CLOUDFRONT_URI}/" \
    ${DIR_CCO}/manifests/cluster-authentication-02-config.yaml
```

D. Update the IdP OIDC object configuration

```bash
sed -i "s/https:\/\/[a-z.-].*/https:\/\/${CLOUDFRONT_URI}\",/" \
    ${DIR_CCO}/04-iam-identity-provider.json
jq . ${DIR_CCO}/04-iam-identity-provider.json
```

- Upload the Bucket content

```bash
aws s3 sync ${OIDC_BUCKET_CONTENT}/ \
    s3://${OIDC_BUCKET_NAME}
```

- Make sure you can access the content through the public URL

> NOTE: CloudFront can take some time to deploy the Distribution. Please be sure the Distribution has been deployed and is available before running this step (`Status=Enabled`). You can access the [CloudFront Console](https://us-east-1.console.aws.amazon.com/cloudfront/) to check it.

```bash
curl https://${CLOUDFRONT_URI}/keys.json
curl https://${CLOUDFRONT_URI}/.well-known/openid-configuration
```

### Create the OpenID Connector identity provider<a name="step-create-oidc"></a>

- Create the IdP OIDC

```bash
aws iam create-open-id-connect-provider \
    --cli-input-json file://${DIR_CCO}/04-iam-identity-provider.json \
    > ${DIR_CCO}/04-iam-identity-provider-object.json 
```

- Get the OpenID Connect ARN

```bash
OIDC_ARN=$(jq -r .OpenIDConnectProviderArn \
    ${DIR_CCO}/04-iam-identity-provider-object.json)

echo ${OIDC_ARN}
```

### Create the IAM Roles<a name="step-create-iam-roles"></a>

Now let’s extract the `CredentialRequests` which contain the definition of IAM Roles permissions, besides the service account information which will allowed to assume the Role.

- Extract `CredentialRequests` from the release image

```bash
./oc adm release extract \
    --credentials-requests \
    --cloud=aws \
    --to=${DIR_CCO}/credrequests \
    ${RELEASE_IMAGE}
```

- Create IAM Roles

```bash
./ccoctl aws create-iam-roles \
    --name=${CLUSTER_NAME} \
    --region=${CLUSTER_REGION}\
    --credentials-requests-dir=${DIR_CCO}/credrequests \
    --identity-provider-arn=${OIDC_ARN} \
    --output-dir ${DIR_CCO}
```

- Copy the manifests to the installer directory

```bash
cp -rvf ${DIR_CCO}/manifests/* ${DIR_INSTALLER}/manifests
cp -rvf ${DIR_CCO}/tls ${DIR_INSTALLER}/
```

### Create the Cluster<a name="step-create-cluster"></a>

- Create a cluster

```bash
./openshift-install create cluster \
    --dir ${DIR_INSTALLER} \
    --log-level debug
```

Done! o/

## Post-install review<a name="post-review"></a>

### _Installer overview_<a name="post-review-installer"></a>

- Install logs
```log
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.my-sts.devcluster.openshift.com

DEBUG Time elapsed per stage:                      
DEBUG            cluster: 6m26s                    
DEBUG          bootstrap: 50s                      
DEBUG Bootstrap Complete: 9m43s                    
DEBUG                API: 2m1s                     
DEBUG  Bootstrap Destroy: 55s                      
DEBUG  Cluster Operators: 9m40s                    
INFO Time elapsed: 27m58s  
```

- Check the service account issuer URL on the `Authentication` resource

```bash
$ oc get authentication cluster -o json \
    | jq .spec.serviceAccountIssuer
"https://d15diimhmpdwiy.cloudfront.net"
```

- Check if all Cluster Operators are available

```bash
# COs Available
$ oc get co  -o json \
    | jq -r ".items[].status.conditions[] | select(.type==\"Available\").status" \
    | sort |uniq -c
32 True

# COs Degraded
$ oc get co -o json \
    | jq -r ".items[].status.conditions[] | select(.type==\"Degraded\").status" \
    | sort |uniq -c
32 False
```

### _Component tests_<a name="post-review-component"></a>

Let’s test the credentials provided to the Machine-API Controller.

- Check operator state

```log
$ oc get co machine-api
NAME          VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
machine-api   4.10.16   True        False         False      17m     
```

- Check the credentials presented to the component

```bash
$ oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' \
    | base64 -d
[default]
role_arn = arn:aws:iam::${ACCOUNT_ID}:role/oidc-def-openshift-machine-api-aws-cloud-credentials
web_identity_token_file = /var/run/secrets/openshift/serviceaccount/token
```

- Get the `ProjectedServiceAccountToken`

<!--
https://guifreelife.com/blog/2022/03/10/Debugging-AWS-STS-Authentication-for-OpenShift-Operators/
-->

```bash
# Get Token path from AWS credentials mounted to pod
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

# Extract tokens from pod
TOKEN=$(oc exec -n openshift-machine-api ${CAPI_POD} \
    -c machine-controller -- cat ${TOKEN_PATH})
```

- Inspect the token - Key ID

```bash
$ echo $TOKEN | awk -F. '{ print $1 }' | base64 -d 2>/dev/null | jq .alg
"RS256"
```

- Inspect the token - Issuer URI

```bash
$ echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null | jq .iss
"https://d15diimhmpdwiy.cloudfront.net"
```

### Test the token with `AssumeRoleWithWebIdentity`<a name="post-review-test-token"></a>

- Extract the IAM Role ARN from the Secret

```bash
IAM_ROLE=$(oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' |\
    base64 -d |\
    grep ^role_arn |\
    awk '{print$3}')
```

- Assume the IAM Role with the previously extracted token

```bash
aws sts assume-role-with-web-identity \
    --role-arn "${IAM_ROLE}" \
    --role-session-name "my-session" \
    --web-identity-token "${TOKEN}"
```

The temporary credentials should be returned, otherwise, the controller may have issues accessing the AWS services.

## Solution Review<a name="solution-review"></a>

Using CloudFront to use as an endpoint URL for OIDC was one option explored in this article, I can see many other possibilities like Lambda, on-prem web server, and so on. The most important is: that the IAM OIDC requires a public endpoint to serve the public keys and configuration.

In my opinion, CloudFront Distribution seems to have many benefits, such as low operation, low cost, no code to maintain, secure, as well as fully managed.

Let's create a matrix comparing a few available options:

| # | URL exposure solution | Est.Cost(USD)/mo | Private S3 | Serverless | Codeless | Low-Ops | Note | 
| -- | --                    | -- | -- | -- | -- | -- | -- |
| 1 | S3                    | 0.11 | No | Yes | Yes | No | Private bucket |
| 2 | CloudFront + S3 | free-tier** + 0.11** | Yes | Yes | Yes | Yes | Best option evaluated |
| 3 | Lambda Endpoint+S3 | free-tier + 0.11 | Yes | Yes | No | No | Additional code management required, and function management as well |
| 4 | ApiGW+Lambda+S3 | (free-tier*2) + 0.11 | Yes | Yes | No | No | Additional code management required, and function management as well |
| 5 | ALB+Lambda+S3 | 17,73 + free-tier + 0.11 | Yes | Yes | No | No | Additional code management required, and function management as well |

> AWS Pricing Calculator [available here](https://calculator.aws/#/estimate?id=bd03775a971f855d119c40f8ff89f224d090e1be).

*Estimated cost calculation (based on CloudFront Distribution metrics):
- ~4 requests per minute (Avg) => ~172800/mo
- ~1500KiB per minute (Avg) => ~64.8GiB/mo

**The CloudFront option will be free when enabling the `cache` on the requests to the `origin`, since all the S3 content is static. Otherwise the cost will be higher than[1]: S3 direct/public URL.

***Free tier details:
```
# S3 Free-tier:
S3 Free-tier: 20,000 GET Requests; 2,000 PUT, COPY, POST, or LIST Requests; and 100 GB of Data Transfer Out each month.

# CloudFront Free-tier:
1 TB of data transfer out, 10,000,000 HTTP and HTTPS Requests, plus 2,000,000 CloudFront Function invocations each month.
```

## Conclusion<a name="conclusion"></a>

As you can see, I didn’t find any restriction to using CloudFront as a public endpoint for IAM OIDC when setting the S3 bucket for private access only, and keeping it compliant with the [S3 best practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html).

I would also like to mention that there is no difference/impact in terms of cluster security, as the cluster does not access the OIDC URL. So, that change is more for the AWS account security compliance.

I can also see some advantages when writing this article, like expanding the solution when you're operating many accounts with many clusters thus simplifying the life of DevSecOps teams:
- Centralize the management of the OIDC files into one single entry point;
- Create your own DNS domain for the OIDC identifier;
- Flexibility to create a 'multi-tenant' solution storing many JWKS from the different clusters in the same bucket; or it could be in different buckets using the same entry point (CloudFront) routing to different origins (S3 Buckets).

Furthermore, it would be nice to have:
- AWS to implement the OIDC private access to the thumbprints instead of a public HTTPS*, this way it would be possible to set a couple of S3 bucket policies, allowing only OIDC ARN principal;
- `ccoctl` utility to create the steps using CloudFront by default;
- `openshift-installer` to embed the `ccoctl` steps/automation when using manual-STS;
- `openshift-installer` to deploy the default IPI cluster with STS by default.

> *there's a blocker from OIDC spec[1] in this suggestion, but AWS could improve the security in this access since the only OIDC client, in this case, is the STS service (access between AWS services).

> [1] _"The returned Issuer location MUST be a URI RFC 3986 [RFC3986] with a scheme component that MUST be HTTPS, a host component, and optionally, port and path components and no query or fragment components."_ [https://openid.net/specs/openid-connect-discovery-1_0.html#IssuerDiscovery]

Suggestions for the next topics:
- Create one multi-tenant bucket with custom DNS on CloudFront to serve JWKS files from multiple clusters
- Evaluate the following options to serve public URLs to IAM OIDC, like:
  - Lambda function serving JWKS files directly or reading from S3 bucket restricted to the ARN function, using one option below as the URL entry point*:
    - a) [dedicated HTTPS endpoint](https://docs.aws.amazon.com/lambda/latest/dg/lambda-urls.html);
    - b) [API Gateway proxying](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html) to the function;
    - c) [ALB as Lamdda's target group type](https://docs.aws.amazon.com/lambda/latest/dg/services-alb.html);
  - hosting directly from a web server

## References<a name="references"></a>

- [OpenID Connect specifications](https://openid.net/connect/)
- [RFC3986](https://openid.net/specs/openid-connect-discovery-1_0.html#IssuerDiscovery)
- [OpenShift doc: Installing an OpenShift Container Platform cluster configured for manual mode with STS](https://docs.openshift.com/container-platform/4.10/authentication/managing_cloud_provider_credentials/cco-mode-sts.html#cco-mode-sts)
- [AWS Blog: Fine-grained IAM roles for Red Hat OpenShift Service on AWS (ROSA) workloads with STS](https://aws.amazon.com/blogs/containers/fine-grained-iam-roles-for-red-hat-openshift-service-on-aws-rosa-workloads-with-sts/)
- [AWS doc: Restricting access to Amazon S3 content by using an origin access identity (OAI)](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [AWS Doc: S3 best practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [EKS Workshop: IAM Roles for Service Account](https://www.eksworkshop.com/beginner/110_irsa/)
- [AWS STS API: AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)

<!--METADATA_START-->

__meta_info__:

> Status: Open for review

> Preview on [Dev.to](https://dev.to/mtulio/protect-the-s3-bucket-used-by-oidc-when-installing-openshift-with-aws-in-manual-sts-mode-irsa-2d7j-temp-slug-5985517?preview=ab8edd52ff229c24f2e63deba4c326bdfba74e3cd8609016573ed06c3b36de9a751b6a1799bbdb52047f0a0916dad1f3373f8c8740b8815062bf6766)

> [PR to Collab](https://github.com/mtulio/mtulio.labs/pull/8) (feel free to review)

> [PR Preview](https://mtuliolabs-git-article-ocp-aws-idp-oidc-mtulio.vercel.app/articles/ocp-idp-aws-oidc-s3-pvt-cfn/)

> Estimated time to publish: 10 June

> Series Name: OpenShift Security in AWS

> Series Post: #1 OIDC Deep Dive;

> Series post id: #2

<!--METADATA_END-->
