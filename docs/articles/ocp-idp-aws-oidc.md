<!--METADATA_START-->

# Deep Dive into AWS OIDC identity provider when installing OpenShift with IAM STS (“manual-STS”) support

__meta_info__:

> Status: WIP

> Preview on [Dev.to](https://dev.to/mtulio/enhance-the-security-options-when-installing-openshift-with-iam-sts-manual-sts-on-aws-5048-temp-slug-3197013?preview=c9e9beb6b5be97e7b8f79527107c7a54847f6a62fab5d2735727e5875f1db843dfb3bfaf4907c49c6628b9014b72f40fc655ff604a033ba604e253ff)

> [PR to Collab](https://github.com/mtulio/mtulio.labs/pull/8) (feel free to review)

> [PR Preview](https://mtuliolabs-git-article-ocp-aws-idp-oidc-mtulio.vercel.app/articles/ocp-idp-aws-oidc/)

> Estimated time to publish: 10 June

> Series Name: OpenShift Security in AWS

> Series Post: #1 OIDC Deep Dive;

> Series post id: #2

<!--METADATA_END-->

Hey! o/

I will share some options to install store OpenShift in AWS using IAM STS / manual-STS mode.

## Recap

Getting credentials assuming an IAM role is the best way to provide credentials to access AWS resources as it uses short-lived tokens, easy to expire, and fine-tuned the access through trusted relationship statements.

When the application which wants to consume AWS services is the other AWS service (EC2, ECS, Lambda, etc) or an application running in any AWS service, usually it uses temporary credentials provided by the authentication service (EC2 is the metadata services / IMDS) to assume the role and get the temporary credentials from STS.

When the service is external from AWS (example mobile App), or it uses shared resources (like Kubernetes/OpenShift cluster running in EC2) it needs an extra layer of authentication to avoid any application being able to assume the role allowed by the service (example EC2 instance profile).

For that reason, there is the managed service IAM OIDC (which implements OpenID Connect spec) to allow from external services federating access to AWS services through STS when assuming the AWS IAM Role.

The Kubernetes API Server (KAS) signs the service account tokens (JWT). The service uses that token to authenticate on STS API calling t, calling the method WithWebIdentity` informing the IAM Role name desired to be assumed. The STS service access the **OIDC to validate it by accessing the JWKS (JSON Web Key Sets) files stored on the public URL**, once the token is validated, the IAM Role will be assumed, returning the short-lived credentials to the caller. The service can authenticate on the target service endpoint API (S3, EC2, etc).

In OpenShift every cluster service that needs to interact with AWS has one different token signed by KAS and IAM Role. Example of services:

- Machine API to create EC2
- Image Registry to create S3 Buckets
- CSI to create EBS block storage

Said that, let’s recap the steps to install OpenShift on AWS with STS support (manual-STS):

1. Create installer config
1. Set the `credentialsMode` to `Manual`
1. Create installer manifests
1. Generate the OIDC keys
1. Create the bucket to store JWKS
1. Upload the OIDC config and keys to Bucket
1. Create the OIDC
1. Save the bucket URL to `Authentication` manifest
1. Extract the credentials requests from release image
1. Process `CredentialRequests` creating the IAM roles
1. Copy the secret manifests and authentication resources to installer manifests directory
1. Install a cluster

The flow is something like this:

![aws-iam-oidc-flow](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/t6j45d92bmgauvy9zket.png)

## Problem statement

The endpoint which stores the JWKS keys should be public, as the OIDC will access the endpoint available on the JWT token when it is sent by STS API call `AssumeRoleWithWebIdentity`. You can take a look the request arriving to the bucket when:
- Enable the S3 bucket access log
- Filter the events to access the Bucket on the CloudTrail

The main motivation to write this article is to share the current flow to help to understand the soltion when any of the components described here is not working as expected, then share further ideas to workaround to expose the public S3 Bucket to the internet when using IAM OpenID Connectior to provide authentication to OpenShift clusters.

Said that, let me share some options to install a cluster using different approaches that should not impact in the IAM OIDC managed service requirements.

## Installing a cluster with manual-STS

> Steps described on [Official documentation](https://docs.openshift.com/container-platform/4.10/authentication/managing_cloud_provider_credentials/cco-mode-sts.html#cco-mode-sts)

Requirements:

- Export the following environment variables

```bash
export CLUSTER_NAME="my-cluster"
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
./ccoctl aws create-key-pair \
  --output-dir ${OUTPUT_DIR_CCO}
```

- Create the OIDC

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

- Generate the install config

```bash
mkdir -p ${INSTALL_DIR}
cat <<EOF > ${INSTALL_DIR}/install-config.yaml
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
./openshift-install create manifests --dir $INSTALL_DIR
```

- Copy manifests to install-dir

```bash
cp -rvf ${OUTPUT_DIR_CCO}/manifests/* \
  ${INSTALL_DIR}/manifests
cp -rvf ${OUTPUT_DIR_CCO}/tls \
  ${INSTALL_DIR}/
```

- Create a cluster

```bash
./openshift-install create cluster \
  --dir $INSTALL_DIR
```

## Post-install review

### _Installer overview_

### _Inspect the token_

### _troubleshoot_

> TODO:
- steps to read/test the token and assume role

## FAQ

Q: Why my cluster operators is Degraded and installation does not finish?

Q: Why my private cluster is not installing due authentication errors?

Q: Why I am seeing a lot of errors `InvalidIdentityToken` on the logs?

```log
(InvalidIdentityToken) when calling the AssumeRoleWithWebIdentity operation: Couldn't retrieve verification key from your identity provider
```

Q: Can I restrict the OIDC's bucket policy to restrict access publically?

Q: How can I make sure the service account's token is working to access AWS resources?

## Conclusion

> TODO:

## References

> TODO:
