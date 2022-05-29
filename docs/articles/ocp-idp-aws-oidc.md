# Deep Dive into AWS OIDC identity provider when installing OpenShift with IAM STS (“manual-STS”) support

> Status: WIP

> Preview on [Dev.to](https://dev.to/mtulio/enhance-the-security-options-when-installing-openshift-with-iam-sts-manual-sts-on-aws-5048-temp-slug-3197013?preview=c9e9beb6b5be97e7b8f79527107c7a54847f6a62fab5d2735727e5875f1db843dfb3bfaf4907c49c6628b9014b72f40fc655ff604a033ba604e253ff)

> [PR to Collab](https://github.com/mtulio/mtulio.labs/pull/8) (feel free to review)

> [PR Preview](https://mtuliolabs-git-article-ocp-aws-idp-oidc-mtulio.vercel.app/articles/ocp-idp-aws-oidc/?h=oidc)

> Estimated time to publish: 10 June

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
```
(InvalidIdentityToken) when calling the AssumeRoleWithWebIdentity operation: Couldn't retrieve verification key from your identity provider
```

Q: Can I restrict the OIDC's bucket policy to restrict access publically?

Q: How can I make sure the service account's token is working to access AWS resources?

## Conclusion

## References
