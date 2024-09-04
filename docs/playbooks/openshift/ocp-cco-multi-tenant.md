

![OCP with multi-tenant OIDC - banner](./../../diagrams/images/ocp-oidc-multitenant-banner.diagram-1000x350.png)

# Create a multi-tenant solution for the OpenID Connect endpoint on OpenShift with STS authentication mode on AWS

> WIP document. More information at: https://github.com/mtulio/mtulio.labs/pull/19

This article describes a solution to create a multi-tenant solution to store the OpenID Connect (OIDC) endpoint (issuer URL) when using OpenShift with AWS Security Token Services (STS) as the authentication mode. It can be used as a multi-cluster and multi-cloud deployment to centralize the OIDC discovery documents and JSON Web Key Sets (JWKS).

The motivation to create this solution is to improve the management of the keys used by OIDC into a single place (S3 bucket) and URL, partitioning them into object paths.

Reasons you might consider using this solution:

- operating many OpenShift/OKD Clusters using STS as authenticate mode
- increase security controls over the OIDC discovery documents and JSON Web Key Set (public keys)
- decrease the operational tasks managing many S3 Buckets
- remove the lock-in of the provider
- increase the flexibility of migrating the backend storage for serving OIDC documents
- decrease the costs per request when serving static files
- decrease the downtime when migrating/replacing the issuer URL

Additionally, I will describe how to use a custom DNS domain name as an issuer URL, replacing the S3 Bucket or CloudFront Distribution DNS names.

If you are looking to explore more about OpenShift using STS as authentication mode, how the current architecture works, sequence flow, and interaction between applications and AWS STS services when assuming IAM Roles using the method `AssumeRoleWithWebIdentity`, take a look at the following articles:

-> [Deep Dive into AWS OIDC identity provider when installing OpenShift using manual authentication mode with STS](https://dev.to/mtulio/deep-dive-into-aws-oidc-identity-provider-when-installing-openshift-with-iam-sts-manual-sts-support-1bo7)

-> [Use private S3 Bucket when installing OpenShift in AWS with manual authentication mode with STS](https://dev.to/mtulio/install-openshift-in-aws-with-sts-manual-sts-using-private-s3-bucket-27le)

Finally, the proposal of partitioning the issuer path component is expected on the [OpenID Spec](https://openid.net/specs/openid-connect-discovery-1_0.html):

> Using path components enables supporting multiple issuers per host. This is required in some multi-tenant hosting configurations.

Cloud Resources created on this article:

- AWS ACM Certificate
- AWS CloudFront Distribution
- AWS DNS Records
- AWS S3 Bucket
- OpenShift cluster on AWS with STS as the authentication mode

Table of Contents

> (To be reviewed)

- [Overview](#overview)
- Prerequisites
    - Permissions
    - Clients
    - Export the variables used in the next steps
- Create the shared OpenID Connect issuer URL
    - Create the SSL certificate with ACM
    - Create the Origin Access Identity (OAI)
    - Create a private S3 Bucket
    - Create the CloudFront Distribution
    - Create the DNS for CloudFront Distribution
- Setup the cluster
    - Steps to create the cluster
    - Creating the cluster on AWS
        - Generate the OpenID Configuration configuration
        - Create the IAM OIDC IdP
        - Create the IAM Roles
        - Create the Cluster
            - Review the installation
            - Review the internal OIDC documents
            - Review and test the bounded-token
    - Create more clusters
- Solution Review
- oc plugin `sts-setup`
- References


## Overview

<!-- ![Solution Overview](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/wkqj4io5d6f8zmd5g100.png) -->

> TODO: description must be improved

- Overview of the components used by this solution

![Solution Overview](./../../diagrams/images/ocp-oidc-multitenant-overview.diagram.png)

- Overview of the flow when the component assumes role (STS API Call `AssumeRoleWithWebIdentity`):

> TODO: the margins of the auto-generated diagram must be reviewed, or the image cropped

![AWS AssumeRoleWithWebIdentity Flow](./../../diagrams/images/ocp-oidc-multitenant-flow-aws.diagram.png)

## Prerequisites

### Permissions

AWS Permissions:

- List and Create on CloudFront

> TODO

### Clients

- oc
- openshift-install
- ccoctl
- aws cli
- jq

> TODO: reference the tool's URL

### Export the variables used in the next steps

Adjust the values according to your environment:

```bash
# R53 Domain name (without dot as suffix)
export R53_DNS_BASE_DOMAIN="devcluster.openshift.com"

# Custom DNS Domain Name used to CloudFront
export OIDC_DOMAIN_NAME="oidc-demo.${R53_DNS_BASE_DOMAIN}"

# Tags assigned to the ACM (Certificate) resource
export ACM_TAGS="[{\"Key\":\"Name\",\"Value\":\"${OIDC_DOMAIN_NAME}\"},{\"Key\":\"openshift.io/cloud-credential-operator/${OIDC_DOMAIN_NAME}\",\"Value\":\"shared\"}]"

# Define the Bucket name
export OIDC_BUCKET_NAME="${OIDC_DOMAIN_NAME}"
export OIDC_BUKCET_REGION="us-east-1"
export OIDC_BUCKET_DNS="${OIDC_BUCKET_NAME}.s3.${OIDC_BUKCET_REGION}.amazonaws.com"
```

## Create the shared OpenID Connect issuer URL

### Create the SSL certificate with ACM

> (Ready for review)

- Create the Certificate on ACM

> Reference CLI: [aws acm request-certificate](https://docs.aws.amazon.com/cli/latest/reference/acm/request-certificate.html)

```bash
ACM_ARN=$(aws acm request-certificate \
    --domain-name "${OIDC_DOMAIN_NAME}" \
    --validation-method DNS \
    --idempotency-token "$(echo ${OIDC_DOMAIN_NAME} | sed 's/[-.]//g')" \
    --tags "${ACM_TAGS}" \
    | jq -r .CertificateArn)
```

- Create the RR to validate the Certificate

> Reference CLI: [aws acm describe-certificate](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/acm/describe-certificate.html)

```bash
ACM_VALIDATION_DNS_NAME=$(aws acm describe-certificate --certificate-arn "${ACM_ARN}" --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Name' --output text)
ACM_VALIDATION_DNS_VALUE=$(aws acm describe-certificate --certificate-arn "${ACM_ARN}" --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Value' --output text)
```

- Discover the HostedZone ID

> Reference CLI: [aws route53 list-hosted-zones](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/route53/list-hosted-zones.html)

> Reference CLI [client-side filtering](https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-filter.html#cli-usage-filter-client-side)

```bash
R53_HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
    --query "HostedZones[?Name==\`${R53_DNS_BASE_DOMAIN}.\`].Id" \
    --output text \
    | awk -F '/hostedzone/' '{print$2}')
```

- Create the records to validate the certificate

> Reference CLI: [aws route53 change-resource-record-sets](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/route53/change-resource-record-sets.html)

```bash
aws route53 change-resource-record-sets \
    --hosted-zone-id "${R53_HOSTED_ZONE_ID}" \
    --change-batch "{
  \"Comment\": \"ACM RR for ${OIDC_DOMAIN_NAME}\",
  \"Changes\": [
    {
      \"Action\": \"CREATE\",
      \"ResourceRecordSet\": {
        \"Name\": \"${ACM_VALIDATION_DNS_NAME}\",
        \"Type\": \"CNAME\",
        \"TTL\": 300,
        \"ResourceRecords\": [
          {
            \"Value\": \"${ACM_VALIDATION_DNS_VALUE}\"
          }
        ]
      }
    }
  ]
}"
```

- Wait for the Certificate be validated status transictioned from `PENDING_VALIDATION` to `SUCCESS`.

```bash
watch -n 5 "aws acm describe-certificate --certificate-arn \"${ACM_ARN}\" --query 'Certificate.DomainValidationOptions[0].ValidationStatus' --output text"
```

### Create the Origin Access Identity (OAI)

> (Ready for review)

Steps to create the Origin Access Identity (OAI) to be used to access the bucket through CloudFront Distribution:

Create the OAI and set the variable `OAI_CLOUDFRONT_ID`:

```bash
export OAI_CLOUDFRONT_ID=$(aws cloudfront create-cloud-front-origin-access-identity \
    --cloud-front-origin-access-identity-config \
    CallerReference="${OIDC_BUCKET_NAME}",Comment="OAI-${OIDC_BUCKET_NAME}" \
    | jq -r .CloudFrontOriginAccessIdentity.Id)
```

### Create a private S3 Bucket

> (Ready for review)

- Create the private Bucket

> Reference CLI: [aws s3api create-bucket](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/s3api/create-bucket.html)

> You must specify the following flag when creating in another region than `us-east-1`: `--create-bucket-configuration LocationConstraint="${OIDC_BUKCET_REGION}"`

```bash
aws s3api create-bucket \
    --bucket ${OIDC_BUCKET_NAME} \
    --region ${OIDC_BUKCET_REGION} \
    --acl private
```

- Create the respective tags on the Bucket (Recommended if you would like to use the ccoctl to delete resources)

> Reference CLI: [aws s3api put-bucket-tagging](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/s3api/put-bucket-tagging.html)

```bash
aws s3api put-bucket-tagging \
    --bucket ${OIDC_BUCKET_NAME} \
    --tagging "TagSet=[{Key=Name,Value=${OIDC_BUCKET_NAME}},{Key=openshift.io/cloud-credential-operator/${OIDC_DOMAIN_NAME},Value=shared}]"
```

- Apply the policy to the Bucket to block public access

> Reference CLI: [aws s3api put-bucket-policy](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/s3api/put-bucket-policy.html)

```bash
aws s3api put-bucket-policy \
    --bucket ${OIDC_BUCKET_NAME} \
    --policy "{\"Version\": \"2008-10-17\",
  \"Id\": \"PolicyForCloudFrontPrivateContent\",
  \"Statement\": [
    {
      \"Sid\": \"1\",
      \"Effect\": \"Allow\",
      \"Principal\": {
        \"AWS\": \"arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${OAI_CLOUDFRONT_ID}\"
      },
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${OIDC_BUCKET_NAME}/*\"
    }
  ]
}"
```

- Ensure the Bucket policy blocks public access

> Reference CLI: [aws s3api put-public-access-block](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/s3api/put-public-access-block.html)

```bash
aws s3api put-public-access-block \
    --bucket ${OIDC_BUCKET_NAME} \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

![Private S3 Bucket](https://user-images.githubusercontent.com/3216894/221041753-082d8aa5-dbb2-4e78-9355-ce200364b896.png)


### Create the CloudFront Distribution

> (Ready for review)

https://awscli.amazonaws.com/v2/documentation/api/latest/reference/cloudfront/index.html

- Create the CloudFront Distribution with S3 Bucket as the origin

> Reference CLI: [aws s3api put-public-access-block](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/s3api/put-public-access-block.html)

```bash
export OIDC_CLOUDFRONT_ARN=$(aws cloudfront create-distribution-with-tags \
    --distribution-config-with-tags "{\"DistributionConfig\": {
    \"CallerReference\": \"${OIDC_DOMAIN_NAME}\",
    \"Aliases\": {
      \"Quantity\": 1,
      \"Items\": [
        \"${OIDC_DOMAIN_NAME}\"
      ]
    },
    \"Origins\": {
      \"Quantity\": 1,
      \"Items\": [
        {
          \"Id\": \"${OIDC_BUCKET_DNS}\",
          \"DomainName\": \"${OIDC_BUCKET_DNS}\",
          \"OriginPath\": \"\",
          \"CustomHeaders\": {
            \"Quantity\": 0
          },
          \"S3OriginConfig\": {
            \"OriginAccessIdentity\": \"origin-access-identity/cloudfront/${OAI_CLOUDFRONT_ID}\"
          },
          \"ConnectionAttempts\": 3,
          \"ConnectionTimeout\": 10,
          \"OriginShield\": {
            \"Enabled\": false
          }
        }
      ]
    },
    \"DefaultCacheBehavior\": {
      \"TargetOriginId\": \"${OIDC_BUCKET_DNS}\",
      \"TrustedSigners\": {
        \"Enabled\": false,
        \"Quantity\": 0
      },
      \"TrustedKeyGroups\": {
        \"Enabled\": false,
        \"Quantity\": 0
      },
      \"ViewerProtocolPolicy\": \"https-only\",
      \"AllowedMethods\": {
        \"Quantity\": 2,
        \"Items\": [
          \"HEAD\",
          \"GET\"
        ],
        \"CachedMethods\": {
          \"Quantity\": 2,
          \"Items\": [
            \"HEAD\",
            \"GET\"
          ]
        }
      },
      \"SmoothStreaming\": false,
      \"Compress\": false,
      \"LambdaFunctionAssociations\": {
        \"Quantity\": 0
      },
      \"FunctionAssociations\": {
        \"Quantity\": 0
      },
      \"FieldLevelEncryptionId\": \"\",
      \"CachePolicyId\": \"b2884449-e4de-46a7-ac36-70bc7f1ddd6d\"
    },
    \"CacheBehaviors\": {
      \"Quantity\": 0
    },
    \"CustomErrorResponses\": {
      \"Quantity\": 0
    },
    \"Comment\": \"${OIDC_DOMAIN_NAME}\",
    \"Logging\": {
      \"Enabled\": false,
      \"IncludeCookies\": false,
      \"Bucket\": \"\",
      \"Prefix\": \"\"
    },
    \"PriceClass\": \"PriceClass_All\",
    \"Enabled\": true,
    \"ViewerCertificate\": {
        \"CloudFrontDefaultCertificate\": false,
        \"ACMCertificateArn\": \"${ACM_ARN}\",
        \"MinimumProtocolVersion\": \"TLSv1\",
        \"SSLSupportMethod\": \"sni-only\"
    }
  },
  \"Tags\": {
    \"Items\": [
      {
        \"Key\": \"Name\",
        \"Value\": \"${OIDC_DOMAIN_NAME}\"
      }
    ]
  }
}"  | jq -r .Distribution.ARN)
```

- The variable `OIDC_CLOUDFRONT_ARN` must have been set with the correct Distribution ARN:

```bash
echo ${OIDC_CLOUDFRONT_ARN}
```

- Wait for the CloudFront Distribution be `Deployed`:

> Reference CLI: [`aws cloudfront list-distributions`](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/cloudfront/list-distributions.html)

```bash
aws cloudfront list-distributions \
    --query "DistributionList.Items[?ARN==\`${OIDC_CLOUDFRONT_ARN}\`].Status"
```

Example output:

```json
[
    "Deployed"
]
```

Save the CloudFront Distribution DNS:

```bash
export OIDC_CLOUDFRONT_DNS=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?ARN==\`${OIDC_CLOUDFRONT_ARN}\`].DomainName" \
    --output text)
```

### Create the DNS for CloudFront Distribution

> (Ready for review)

- Create the DNS Record for the OIDC (`OIDC_DOMAIN_NAME`) pointing to the CloudFront Distribution (`OIDC_CLOUDFRONT_DNS`)

> Reference CLI: [aws route53 change-resource-record-sets](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/route53/change-resource-record-sets.html)

> NOTE: The Route53 Alias Record will be created pointing to CloudFront Distribution IPv4 Address.

```bash
aws route53 change-resource-record-sets \
    --hosted-zone-id "${R53_HOSTED_ZONE_ID}" \
    --change-batch "{
  \"Comment\": \"OIDC entrypoint ${OIDC_DOMAIN_NAME}\",
  \"Changes\": [
    {
      \"Action\": \"CREATE\",
      \"ResourceRecordSet\": {
        \"Name\": \"${OIDC_DOMAIN_NAME}\",
        \"Type\": \"A\",
        \"AliasTarget\": {
            \"HostedZoneId\":\"Z2FDTNDATAQYW2\",
            \"DNSName\": \"${OIDC_CLOUDFRONT_DNS}\",
            \"EvaluateTargetHealth\": false
        }
      }
    }
  ]
}"
```

- Check if you can resolve the OIDC DNS Name to the CloudFront Distribution addresses

```bash
dig ${OIDC_DOMAIN_NAME}
```

- Populate the Bucket and check if you can reach the S3 Bucket objects through AWS CloudFront Distribution

> Feel free to remove the object `s3://${OIDC_BUCKET_NAME}/ping` after the test

```bash
echo "OK" > ./ping && aws s3 cp ./ping s3://${OIDC_BUCKET_NAME}/ping
curl https://${OIDC_DOMAIN_NAME}/ping
```

## Setup the cluster

> WIP

### Steps to create the cluster

For didactic reasons, we are assuming the following statements:

- the two clusters installed in this article will have the OCP version (4.12.2)
- consequently, the CredentialsRequests will be extracted at once
- **the unique identifier used to append to OIDC URL, and uploaded on the bucket path, will be the infraID generated by Installer**. You can use other UUID as you want

Steps to run one time:

- extract the OpenShift Clients (oc, installer, and ccoctl)
- extract the CredentialRequests

```bash
export REGION=${CLUSTER_REGION:-'us-east-1'}
export VERSION=${CLUSTER_VERSION:-4.12.2}

export PULL_SECRET_FILE=${HOME}/.openshift/pull-secret-latest.json
export SSH_PUB_KEY_FILE="${HOME}/.ssh/id_rsa.pub"

oc adm release extract \
    --tools quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64 \
    -a ${PULL_SECRET_FILE}

tar xvfz openshift-client-linux-${VERSION}.tar.gz
tar xvfz openshift-install-linux-${VERSION}.tar.gz

RELEASE_IMAGE=$(./openshift-install version | awk '/release image/ {print $3}')
CCO_IMAGE=$(./oc adm release info --image-for='cloud-credential-operator' $RELEASE_IMAGE)
./oc image extract $CCO_IMAGE --file="/usr/bin/ccoctl" -a ${PULL_SECRET_FILE}
chmod 775 ccoctl
```

Steps to run for each cluster:

- create install-config
- create manifests
- extract InfraID
- create key pair
- generate OIDC config
- create the OIDC URL
- patch the OIDC config
- upload to bucket the OIDC configuration (discovery documents and public keys)
- test it
- create the IAM OIDC IdP
- export the ARN
- create the IAM Roles
- add the manifests to the installer
- create the cluster

### Creating the cluster on AWS

> WIP

- Export the variables to create the cluster (adjust according to your environment)

```bash
export CLUSTER_NAME="cluster2"

# can keep unchanged
export INSTALL_DIR="${PWD}/installer-${CLUSTER_NAME}"
export OUTPUT_DIR_CCO="${INSTALL_DIR}/ccoctl-assets/"
export CLUSTER_OIDC_CONTENT="${OUTPUT_DIR_CCO}/custom-oidc-content"
```

- Create the install-config.yaml (adjust according to your needs)

```bash
mkdir -p ${INSTALL_DIR}
cat <<EOF | envsubst > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${R53_DNS_BASE_DOMAIN}
credentialsMode: Manual
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${REGION}
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
```

- Create the manifests

```bash
./openshift-install create manifests --dir $INSTALL_DIR
```

- Extract the `InfraID`, created by the installer

> The OIDC domain will be created from the InfraID: `https://${OIDC_DOMAIN_NAME}/${CLUSTER_INFRAID}`

```bash
# Get the infraID
export CLUSTER_INFRAID=$(awk '/infrastructureName: / {print $2}' ${INSTALL_DIR}/manifests/cluster-infrastructure-02-config.yml)
```

#### Generate the OpenID Configuration configuration

- Generate the signing key par:

```bash
echo "> CCO - Creating key-par"
mkdir -p ${OUTPUT_DIR_CCO}
./ccoctl aws create-key-pair \
    --output-dir ${OUTPUT_DIR_CCO}
```

- Generate the OIDC identity provider configuration:

```bash
echo "> CCO - Creating IdP"
./ccoctl aws create-identity-provider \
    --name=${CLUSTER_NAME} \
    --region=${REGION} \
    --public-key-file=${OUTPUT_DIR_CCO}/serviceaccount-signer.public \
    --output-dir=${OUTPUT_DIR_CCO}/ \
    --dry-run
```

- Extract the OIDC DNS Name generated by `ccoctl`:

```bash
export GEN_ISSUER=$(jq -r .issuer ${OUTPUT_DIR_CCO}/02-openid-configuration | awk -F 'https://' '{print$2}')
```

- Create the new OIDC configuration according to the customized DNS Domain for OIDC:

> The new Bucket content will be saved on: `${CLUSTER_OIDC_CONTENT}/.well-known`

```bash
mkdir -p ${CLUSTER_OIDC_CONTENT}/.well-known

cat ${OUTPUT_DIR_CCO}/02-openid-configuration \
    | sed "s/${GEN_ISSUER}/${OIDC_DOMAIN_NAME}\/${CLUSTER_INFRAID}/" \
    > ${CLUSTER_OIDC_CONTENT}/.well-known/openid-configuration

cp -v ${OUTPUT_DIR_CCO}/03-keys.json ${CLUSTER_OIDC_CONTENT}/keys.json

sed -i "s/${GEN_ISSUER}/${OIDC_DOMAIN_NAME}\/${CLUSTER_INFRAID}/" \
    ${OUTPUT_DIR_CCO}/04-iam-identity-provider.json
```

- Upload the patched files to S3:

```bash
aws s3 sync ${CLUSTER_OIDC_CONTENT}/ s3://${OIDC_BUCKET_NAME}/${CLUSTER_INFRAID}
```

- Test accessing it from the unified OIDC URL:

```bash
# Retrieve by public endpoint
curl https://${OIDC_DOMAIN_NAME}/${CLUSTER_INFRAID}/keys.json
curl https://${OIDC_DOMAIN_NAME}/${CLUSTER_INFRAID}/.well-known/openid-configuration
```

#### Create the IAM OIDC IdP

- Get the Thumbprint from the OIDC URL:

```bash
# Set the thumbprint
openssl s_client -servername $OIDC_DOMAIN_NAME \
    -showcerts -connect ${OIDC_DOMAIN_NAME}:443 </dev/null \
    | openssl x509 -outform pem > ${OUTPUT_DIR_CCO}/certificate.crt

export SRV_THUMBPRINT=$(openssl x509 -in ${OUTPUT_DIR_CCO}/certificate.crt -fingerprint -sha1 -noout | awk -F'=' '{print$2}' | tr -d ':')

jq -r ".ThumbprintList=[\"${SRV_THUMBPRINT}\"]" \
    ${OUTPUT_DIR_CCO}/04-iam-identity-provider.json \
    > ${OUTPUT_DIR_CCO}/04-iam-identity-provider-new.json
```

- Create the AWS Identity Provider OpenID Connect:

```bash
# Create IdP
aws iam create-open-id-connect-provider \
    --cli-input-json file://${OUTPUT_DIR_CCO}/04-iam-identity-provider-new.json \
    | tee ${OUTPUT_DIR_CCO}/04-iam-identity-provider-object.json

export OIDC_ARN=$(jq -r .OpenIDConnectProviderArn ${OUTPUT_DIR_CCO}/04-iam-identity-provider-object.json)

echo ${OIDC_ARN}
```

> TODO: insert the image with the OIDC (AWS Console)

![AWS OpenID Connect identity provider](https://user-images.githubusercontent.com/3216894/221041750-24a7be6a-ba24-4fe3-9d89-6b6465a5cba6.png)

#### Create the IAM Roles

- Extract the CredentialsRequests for the target release:

```bash
echo "> CCO - Extracting CredentialsRequests from release payload"
RELEASE_IMAGE=$(./openshift-install version | awk '/release image/ {print $3}')
./oc adm release extract --credentials-requests \
    --cloud=aws \
    --to=${OUTPUT_DIR_CCO}/credrequests \
    ${RELEASE_IMAGE}
```

- Process the CredentialsRequests, creating the IAM Role with the new IdP URL:

```bash
./ccoctl aws create-iam-roles \
    --name=${CLUSTER_NAME} \
    --region=${REGION}\
    --credentials-requests-dir=${OUTPUT_DIR_CCO}/credrequests \
    --identity-provider-arn=${OIDC_ARN} \
    --output-dir ${OUTPUT_DIR_CCO}
```

> TODO Add the image (AWS Console) with IAM Roles Created

![IAM Roles created by ccoctl](https://user-images.githubusercontent.com/3216894/221041747-588c2aeb-b025-4cc7-b5e1-31dffa042f6f.png)


> TODO Add the image (AWS Console) with IAM Role' Trusted Policy referencing to the OIDC IdP

![IAM Role Trusted Policy for Machine API Controllers](https://user-images.githubusercontent.com/3216894/221041745-0ef754cf-dda5-4c4c-9860-3076ee48465c.png)


#### Create the Cluster

- Copy the Manifests created by processing `CredentialsRequests`

```bash
echo "> CCO - Copying manifests to Install directory"
cp -rvf ${OUTPUT_DIR_CCO}/manifests/* ${INSTALL_DIR}/manifests/
cp -rvf ${OUTPUT_DIR_CCO}/tls ${INSTALL_DIR}/
```

- Patch the issuer URL on the `Authentication` object in `cluster-authentication-02-config.yaml`

```bash
sed -i "s/${GEN_ISSUER}/${OIDC_DOMAIN_NAME}\/${CLUSTER_INFRAID}/" \
    ${INSTALL_DIR}/manifests/cluster-authentication-02-config.yaml
```

- Create the Cluster:

```bash
./openshift-install create cluster --dir ${INSTALL_DIR}
```

#### Review the installation

- Wait for the installer complete

```
DEBUG Time elapsed per stage:                      
DEBUG            cluster: 4m44s                    
DEBUG          bootstrap: 44s                      
DEBUG Bootstrap Complete: 13m47s                   
DEBUG                API: 1m30s                    
DEBUG  Bootstrap Destroy: 1m0s                     
DEBUG  Cluster Operators: 10m1s                    
INFO Time elapsed: 30m54s
```

- Review the authentication object:

```
$ oc get authentication cluster -o jsonpath={'.spec.serviceAccountIssuer'}
https://oidc-demo.devcluster.openshift.com/cluster2-97sr6
```

#### Review the internal OIDC documents

As described on the ["Service account issuer discovery"](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#service-account-issuer-discovery):

> The Kubernetes API server publishes the related JSON Web Key Set (JWKS), also via HTTP, at /openid/v1/jwks.

> **Note**: The responses served at `/.well-known/openid-configuration` and `/openid/v1/jwks` are designed to be OIDC compatible, but not strictly OIDC compliant. Those documents contain only the parameters necessary to perform validation of Kubernetes service account tokens.

You can query the published OpenID Provider Configuration document in OpenShift using the following commands:

- Extract the service account token

```bash
SERVICEACCOUNT=/var/run/secrets/kubernetes.io/serviceaccount
CACERT=${SERVICEACCOUNT}/ca.crt
APISERVER=$(oc get infrastructures cluster -o jsonpath={'.status.apiServerInternalURI'})

# Use the ClusterAPI pods to test. Discovery the pod name:
CAPI_POD=$(oc get pods -n openshift-machine-api \
    -l api=clusterapi \
    -o jsonpath='{.items[*].metadata.name}')

# Extract the ServiceAccoun token
TOKEN_SA=$(oc exec -n openshift-machine-api ${CAPI_POD}     -c machine-controller -- cat ${SERVICEACCOUNT}/token)
```
- Query the OIDC documents published by the Kuberbetes API server:

```bash
# Get the JWKS published by KAS
oc exec -n openshift-machine-api ${CAPI_POD} -c machine-controller -- \
    curl --cacert ${CACERT} \
    --header "Authorization: Bearer ${TOKEN_SA}" \
    -X GET -s ${APISERVER}/openid/v1/jwks |jq .

# Get the OIDC Discovery document published by KAS
oc exec -n openshift-machine-api ${CAPI_POD} -c machine-controller -- \
    curl --cacert ${CACERT} \
    --header "Authorization: Bearer ${TOKEN_SA}" \
    -X GET -s ${APISERVER}/.well-known/openid-configuration |jq .
```

**IMPORTANT**: the `jwks_uri` may differ from the value published on the issuer URL, as it is used **internally** to perform validation of Kubernetes service account tokens.

That is the main point when designing this solution: the Kubernetes API Server exposes the internally OIDC documents, replacing the needed address to be accessible internally, avoiding going to the internet (OIDC public issuer URL).

Summarizing, there is two versions of OIDC documents:

- 1) OIDC issuer URL, stored on S3 Bucket, exposed by CloudFront Distribution
- 2) Kubernetes API server URL, stored internally, exposed by Kubernetes API Server

#### Review and test the bounded-token

Let's review the bounded tokens presented to the MAPI controllers:

- Test the bound token:

```bash
## test existing token
# Get Token path from AWS credentials mounted to pod
TOKEN_PATH=$(oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' |\
    base64 -d |\
    grep "^web_identity_token_file" |\
    awk '{print$3}')

# Get Controler's pod
CAPI_POD=$(oc get pods -n openshift-machine-api \
    -l api=clusterapi \
    -o jsonpath='{.items[*].metadata.name}')

# Extract tokens from the pod
TOKEN=$(oc exec -n openshift-machine-api ${CAPI_POD} \
    -c machine-controller -- cat ${TOKEN_PATH})

echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null | jq .iss
```

Expected results for the issuer on JWK Token:

```
"https://oidc-demo.devcluster.openshift.com/cluster2-97sr6"
```

- Test assuming the Role using the bound token:

```bash
IAM_ROLE=$(oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' |\
    base64 -d |\
    grep "^role_arn" |\
    awk '{print$3}')

echo $IAM_ROLE

aws sts assume-role-with-web-identity \
    --role-arn "${IAM_ROLE}" \
    --role-session-name "my-session" \
    --web-identity-token "${TOKEN}"
```

Expected results: `aws sts assume-role-with-web-identity [...]`:

```json
{
  "Credentials": "[redacted]",
  "SubjectFromWebIdentityToken": "system:serviceaccount:openshift-machine-api:machine-api-controllers",
  "AssumedRoleUser": {
    "AssumedRoleId": "[redacted]:my-session",
    "Arn": "arn:aws:sts::[redacted]:assumed-role/cluster2-openshift-machine-api-aws-cloud-credentials/my-session"
  },
  "Provider": "arn:aws:iam::[redacted]:oidc-provider/oidc-demo.devcluster.openshift.com/cluster2-97sr6",
  "Audience": "openshift"
}
```

### Create more clusters

> TODO: create the plugin with all snippets described here

> TODO: one paragram describing what's next. More AWS Clusters? HyperShift? GCP?

> TODO: example (or describe the idea) of creating a cluster in GCP with STS using storage in AWS. Why? AFAIK GCP does not provide a simple way to close the storage and provide a clean URL as we do with CloudFront in AWS

## Solution Review

> TODO

## oc plugin `sts-setup`

> TODO: create an oc plugin covering the steps described in this article

## References

- [Kubernetes: Service account issuer discovery](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#service-account-issuer-discovery)

- [Kubernetes Enhancement Proposal: OIDC Discovery](https://github.com/kubernetes/enhancements/tree/master/keps/sig-auth/1393-oidc-discovery)

- [OpenID Connect Discovery Spec](https://openid.net/specs/openid-connect-discovery-1_0.html)
