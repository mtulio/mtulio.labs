<!--METADATA_START-->

# Create private S3 Bucket for OpenID Connect when installing OpenShift in AWS with "manual-STS"

__info__:

> Status: WIP

> Preview on [Dev.to](https://dev.to/mtulio/protect-the-s3-bucket-used-by-oidc-when-installing-openshift-with-aws-in-manual-sts-mode-irsa-2d7j-temp-slug-5985517?preview=ab8edd52ff229c24f2e63deba4c326bdfba74e3cd8609016573ed06c3b36de9a751b6a1799bbdb52047f0a0916dad1f3373f8c8740b8815062bf6766)

> [PR to Collab](https://github.com/mtulio/mtulio.labs/pull/8) (feel free to review)

> [PR Preview](https://mtuliolabs-git-article-ocp-aws-idp-oidc-mtulio.vercel.app/articles/ocp-idp-aws-oidc/?h=oidc)

> Estimated time to publish: 10 June

> Series Name: OpenShift Security in AWS

> Series Post: #1 OIDC Deep Dive;

> Series post id: #2

<!--METADATA_END-->

In this article I will share a hands-on steps to replace the default public endpoint used by IAM OpenID Connect (OIDC) from S3 public Bucket to CloudFront Distribution's URL, when installing a OpenShift cluster with STS support.

## Table Of Contents
  * [Summary](#summary)
    * [Quickly recap](#summary-recap)
    * [Goal](#summary-goal)
  * [Steps](#steps)
    * [Requirements](#step-requirements)
    * [Setup](#step-setup)
    * [Create Installer Manifests](#step-create-manifests)
    * [Create Origin Access Identity](#step-create-oai)
    * [Create Bucket](#step-create-bucket)
    * [Create CloudFront Distribution](#step-create-cloudfront-dist)
    * [Generate OIDC configuration and keys](#step-gen-oidc)
    * [Create the OpenID Connector identity provider](#step-create-oidc)
    * [Create IAM Roles](#step-create-iam-roles)
    * [Create the Cluster](#step-create-cluster)
  * [Post-install review and tests](#post-review)
    * [Installer overview](#post-review-installer)
    * [Component overview](#post-review-component)
    * [Test the token with `AssumeRoleWithWebIdentity`](#post-review-test-token)
  * [Conclusion](#conclusion)

## Summary<a name="summary"></a>

### _Quickly recap_<a name="summary-recap"></a>

The endpoint identifier, also named the OpenID Connector resource, should be public acessible as it's used by OIDC. It contains the signing keys for the `ProjectedServiceAccountToken` JSON web tokens so external systems, like IAM, can validate and accept the Kubernetes-issued OIDC tokens.

Currently, the default `ccoctl` deployment creates one public S3 Bucket by cluster with JWKS objects, exposing directly the Bucket's URL as OIDC discovery endpoint. In some AWS Accounts, public buckets or objects are unwanted or blocked, the main motivation to explore this topic and share options we have nowadays.

If you would like to know more about this topic, I highly advise to read:
- [Blog: Deep Dive into AWS OIDC identity provider when installing OpenShift with IAM STS (“manual-STS”) support](https://dev.to/mtulio/enhance-the-security-options-when-installing-openshift-with-iam-sts-manual-sts-on-aws-5048-temp-slug-3197013?preview=c9e9beb6b5be97e7b8f79527107c7a54847f6a62fab5d2735727e5875f1db843dfb3bfaf4907c49c6628b9014b72f40fc655ff604a033ba604e253ff)
- [AWS Doc: Restricting access to Amazon S3 content by using an origin access identity (OAI)](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)

### _Goal_<a name="summary-goal"></a>

We will walk through those steps to:
- create one CloudFront Distribution to be used as public endpoint for OIDC
- create one private S3 Bucket
- create one [origin access identity (OAI) to access the S3 from CloudFront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- replace the new CloduFront URL on JWKS files when setting up the [manual-STS](https://docs.openshift.com/container-platform/4.10/authentication/managing_cloud_provider_credentials/cco-mode-sts.html#cco-mode-sts) during the OpenShift installation
- create the OIDC identity provider using the CloudFront URL
- create the IAM Roles with Trusted Policy’s allowing Federated OIDC service ARN with proper service account restrictions
- create the OpenShift cluster with STS support with no public buckets

## Steps<a name="steps"></a>

### Requirements<a name="step-requirements"></a>

- OpenShift installer client (`openshift-installer`)
- OpenShift client (`oc`)
- `ccoctl` utility
- AWS credentials with permissions to install a cluster with maual-STS support
- aws-cli
- jq
- yq

### Setup<a name="step-setup"></a>

- Adjust and export the environment variables

```bash
export CLUSTER_NAME="mrb-sts"

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

### Create Install Manifests<a name="step-create-manifests"></a>

- Create installer manifests 

> The mandatory change: `credentialsMode: Manual`

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
    region: ${CLUSTER_REGION}
    defaultMachinePlatform:
      zones:
      - ${CLUSTER_REGION}a
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
./openshift-install create manifests --dir ${DIR_INSTALLER}
```

- Set the `CLUSTER_ID` environment variable

```bash
CLUSTER_ID="$(yq -r .status.infrastructureName ${DIR_INSTALLER}/manifests/cluster-infrastructure-02-config.yml)"
```

### Create Origin Access Identity<a name="step-create-oai"></a>

Steps to create the Origin Access Identity (OAI) to restrict access to content that you serve from Amazon S3 buckets.l:

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

### Create Bucket<a name="step-create-bucket"></a>

- Create the private Bucket

```bash
aws s3api create-bucket \
    --bucket ${OIDC_BUCKET_NAME} \
    --acl private
```

- Create the Bucket Policy document allowing OAI retrieve objects

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

- Apply the policy to Bucket and block public access

```bash
aws s3api put-bucket-policy \
    --bucket ${OIDC_BUCKET_NAME} \
    --policy file://${WORKDIR}/oidc-bucket-policy.json

aws s3api put-public-access-block \
    --bucket ${OIDC_BUCKET_NAME} \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

## Create CloudFront Distribution<a name="step-create-cloudfront-dist"></a>

- create distribution’s document

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

- Create the CloudFront distribution with Tags

```bash
aws cloudfront create-distribution-with-tags \
    --distribution-config-with-tags \
    file://${WORKDIR}/oidc-cloudfront.json
```

- Wait a few minutes until the distribution has been created.

- Get the CloudFront's Distribution URL

```bash
CLOUDFRONT_URI=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Comment==\`${CLUSTER_NAME}\`].DomainName" \
    --output text)

echo ${CLOUDFRONT_URI}
```

### Generate OIDC configuration and keys<a name="step-gen-oidc"></a>

- Generate the key pair used to create the service account tokens

```bash
./ccoctl aws create-key-pair \
    --output-dir ${DIR_CCO}
```

- Generate the OpenID configuration

```bash
./ccoctl aws create-identity-provider \
    --name=${CLUSTER_NAME} \
    --region=${CLUSTER_REGION} \
    --public-key-file=${DIR_CCO}/serviceaccount-signer.public \
    --output-dir=${DIR_CCO}/ \
    --dry-run
```

- Update the CloudFront URI's endpoint to CloudFront distribution's address:

A. Update the OpenID Config file `/.well-known/openid-configuration`

```bash
mkdir -p ${OIDC_BUCKET_CONTENT}/.well-known
cat ${DIR_CCO}/02-openid-configuration \
    | sed "s/https:\/\/${CLUSTER_NAME}[a-z.-].*\//https:\/\/${CLOUDFRONT_URI}\//" \
    | sed "s/https:\/\/${CLUSTER_NAME}[a-z.-].*/https:\/\/${CLOUDFRONT_URI}\",/" \
    > ${OIDC_BUCKET_CONTENT}/.well-known/openid-configuration
```

B. Copy `keys.json`

```bash
cp -v ${DIR_CCO}/03-keys.json \
    ${OIDC_BUCKET_CONTENT}/keys.json
```

C. Update `cluster-authentication-02-config.yaml`

```bash
sed -i "s/https:\/\/[a-z.-].*/https:\/\/${CLOUDFRONT_URI}/" \
    ${DIR_CCO}/manifests/cluster-authentication-02-config.yaml
```

5. Update the IdP OIDC configuration

```bash
sed -i "s/https:\/\/[a-z.-].*/https:\/\/${CLOUDFRONT_URI}\",/" \
    ${DIR_CCO}/04-iam-identity-provider.json
jq . ${DIR_CCO}/04-iam-identity-provider.json
```

- Upload the bucket content

```bash
aws s3 sync ${OIDC_BUCKET_CONTENT}/ \
    s3://${OIDC_BUCKET_NAME}
```

- Make sure you can access the content through public URL

```bash
curl https://${CLOUDFRONT_URI}/keys.json
curl https://${CLOUDFRONT_URI}/.well-known/openid-configuration
```

### Create the OpenID Connector identity provider<a name="step-create-oidc"></a>

- Create the IdP IAM OIDC

```bash
aws iam create-open-id-connect-provider \
    --cli-input-json file://${DIR_CCO}/04-iam-identity-provider.json \
    > ${DIR_CCO}/04-iam-identity-provider-object.json 
```

- Wait a few time until the create have been propagated: 

```bash
OIDC_ARN=$(jq -r .OpenIDConnectProviderArn \
    ${DIR_CCO}/04-iam-identity-provider-object.json)

echo ${OIDC_ARN}
```

### Create IAM Roles<a name="step-create-iam-roles"></a>

- Extract `CredentialRequests` from release image

```bash
./oc adm release extract \
    --credentials-requests \
    --cloud=aws \
    --to=${DIR_CCO}/credrequests \
    ${RELEASE_IMAGE}
```

- Create IAM Roles with proper Trusted Policy

```bash
./ccoctl aws create-iam-roles \
    --name=${CLUSTER_NAME} \
    --region=${CLUSTER_REGION}\
    --credentials-requests-dir=${DIR_CCO}/credrequests \
    --identity-provider-arn=${OIDC_ARN} \
    --output-dir ${DIR_CCO}
```

- Copy manifests to the installer directory

```bash
cp -rvf ${DIR_CCO}/manifests/* ${DIR_INSTALLER}/manifests
cp -rvf ${DIR_CCO}/tls ${DIR_INSTALLER}/
```

### Create the Cluster<a name="step-create-cluster"></a>

- Create a cluster

```bash
./openshift-install create cluster \
    --dir ${INSTALL_DIR} \
    --log-level debug
```

o/

## Post-install review<a name="post-review"></a>

### _Installer overview_<a name="post-review-installer"></a>

- Install logs
```log
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
$ oc get authentication cluster -o json \
    | jq .spec.serviceAccountIssuer
"https://d15diimhmpdwiy.cloudfront.net"
```

- Check if all ClusterOperators are available

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

The component credentials that will be tested is the Machine-API Controler.

- Deep dive into Machine API credentials

```log
$ oc get co machine-api
NAME          VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
machine-api   4.10.16   True        False         False      17m     
```

- Check Credential presented to Componenet

```bash
$ oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' \
    | base64 -d
[default]
role_arn = arn:aws:iam::${ACCOUNT_ID}:role/oidc-def-openshift-machine-api-aws-cloud-credentials
web_identity_token_file = /var/run/secrets/openshift/serviceaccount/token
```

- Get `ProjectedServiceAccountToken`

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

- Inspect JWK's Token - Key ID

```bash
$ echo $TOKEN | awk -F. '{ print $1 }' | base64 -d 2>/dev/null | jq .alg
"RS256"
```

- Inspect JWK's Token - Issuer URI

```bash
$ echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null | jq .iss
"https://d15diimhmpdwiy.cloudfront.net"
```

### Test the token with `AssumeRoleWithWebIdentity`<a name="post-review-test-token"></a>

- Extract the IAM Role ARN from secret

```bash
IAM_ROLE=$(oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' |\
    base64 -d |\
    grep ^role_arn |\
    awk '{print$3}')
```

- Assume the IAM Role with previous extracted token

```bash
aws sts assume-role-with-web-identity \
    --role-arn "${IAM_ROLE}" \
    --role-session-name "my-session" \
    --web-identity-token "${TOKEN}"
```


All set! Now you can see there's no public Bucket on the AWS account installed the cluste
ralongisde there's no change to


## Conclusion<a name="conclusion"></a>

As you can see, there's no restrictions to use CloudFront as a public endpoint for IAM OIDC, restricting the S3 bucket for public access, also avoid exposing directly the S3 URL, keeping compliant with the [S3 best practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html).

That change also there is no difference/impact in terms of clusters' security, as the cluster should not access that URL, so that change is more for Account's security compliant.

I also can see some advantages when writing this article like expanding the solution when you're operating many accounts with many clusters simplifying the life of DevSecOps teams:
- Centralize the management of the OIDC files into one single entrypoint;
- Create your own DNS domain for OIDC identifier;
- Flexible to create an 'multi-tenant' solution storing many JWKS from different cluster into the same bucket; or could be in different buckets but with the same entrypoint (CloudFront) routing to different origins.

Furthermore, itt would be nice to have:
- AWS could allow the OIDC private requests (s3://) to access the thumbprints, instead of a public HTTPS*, so it would be possible to set a couple of S3 bucket policies allowing OIDC service, for example, allowing only OIDC's ARN principal;
- `ccoctl` utility create the steps using CloudFront by default;
- `openshift-installer` embeed the `ccoctl` steps/automation when using manual-STS;
- `openshift-installer`deploy the default IPI cluster with STS by default;

> *there's a blocker from OIDC spec[1] in this suggestion, but AWS could improve the security in this access as the unique client of OIDC in this case should be the STS service

> [1] "The returned Issuer location MUST be a URI RFC 3986 [RFC3986] with a scheme component that MUST be https, a host component, and optionally, port and path components and no query or fragment components." [https://openid.net/specs/openid-connect-discovery-1_0.html#IssuerDiscovery]


Suggestions for the next topics:
- Create one multi-tenant bucket with custom DNS on the CloudFront to serve JWKS files from multiple clusters
- Evaluate the other options to serve public URLs to IAM OIDC, like:
  - Lambda function serving JWKS files directly or reading from S3 bucket restricted to function's ARN, using one option below as URL entrypoint*:
  - a) [dedicated HTTPS endpoint](https://docs.aws.amazon.com/lambda/latest/dg/lambda-urls.html);
  - b) [API Gateway proxying](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html) to the function;
  - c) [ALB as Lamdda's target group](https://docs.aws.amazon.com/lambda/latest/dg/services-alb.html);type
  - directly from hosted web server

## References

- [OpenID Connect specifications](https://openid.net/connect/)
- [RFC3986](https://openid.net/specs/openid-connect-discovery-1_0.html#IssuerDiscovery)
- [OpenShift doc: Installing an OpenShift Container Platform cluster configured for manual mode with STS](https://docs.openshift.com/container-platform/4.10/authentication/managing_cloud_provider_credentials/cco-mode-sts.html#cco-mode-sts)
- [AWS Blog: Fine-grained IAM roles for Red Hat OpenShift Service on AWS (ROSA) workloads with STS](https://aws.amazon.com/blogs/containers/fine-grained-iam-roles-for-red-hat-openshift-service-on-aws-rosa-workloads-with-sts/)
- [AWS doc: Restricting access to Amazon S3 content by using an origin access identity (OAI)](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [AWS Doc: S3 best practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [EKS Workshop: IAM Roles for Service Account](https://www.eksworkshop.com/beginner/110_irsa/)
- [AWS STS API: AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
