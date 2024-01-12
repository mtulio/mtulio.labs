## Deploy proxy server

!!! warning "Experimental steps"
    The steps described on this page are experimental!

!!! info "CloudFormation templates"
    The CloudFormation templates mentioned on this page are available in the path:
    [mtulio.labs/labs/labs/ocp-install-iac/aws-cloudformation-templates](https://github.com/mtulio/mtulio.labs/tree/master/labs/ocp-install-iac/aws-cloudformation-templates)


### Create proxy server configuration (ignition)

- Generate user data (ignitions) for proxy node server (squid):

```sh
curl -L -o /tmp/fcos.json https://builds.coreos.fedoraproject.org/streams/stable.json

export PROXY_IMAGE=quay.io/mrbraga/squid:6.6
export PROXY_NAME="${PREFIX_VARIANT}-proxy"
export PROXY_AMI_ID=$(jq -r .architectures.x86_64.images.aws.regions[\"${AWS_REGION}\"].image < /tmp/fcos.json)

export SSH_PUB_KEY=$(<"${SSH_PUB_KEY_FILE}")
export PASSWORD="$(uuidgen | sha256sum | cut -b -32)"
export HTPASSWD_CONTENTS="${PROXY_NAME}:$(openssl passwd -apr1 ${PASSWORD})"
export HTPASSWD_CONTENTS="$(echo -e ${HTPASSWD_CONTENTS} | base64 -w0)"

# define squid config
export SQUID_CONFIG="$(base64 -w0 < ${WORKDIR}/proxy-template/squid.conf)"

# define squid.sh
export SQUID_SH="$(envsubst < ${WORKDIR}/proxy-template/squid.sh.template | base64 -w0)"

# define proxy.sh
export PROXY_SH="$(base64 -w0 < ${WORKDIR}/proxy-template/proxy.sh)"

# generate ignition file
envsubst < ${WORKDIR}/proxy-template/proxy.ign.template > ~/tmp/proxy.ign
test -f /tmp/proxy.ign || echo "Failed to create ~/tmp/proxy.ign"

# publish ignition to shared bucket
#export PROXY_URI="s3://${BUCKET_NAME}/proxy.ign"
#export PROXY_URL="https://${BUCKET_NAME}.s3.amazonaws.com/proxy.ign"

#aws s3 cp ~/tmp/proxy.ign $PROXY_URI

# Generate Proxy Instance user data
#export PROXY_USER_DATA=$(envsubst < ${WORKDIR}/proxy-template/userData.ign.template | base64 -w0)

export PROXY_USER_DATA=$(base64 -w0 <(<~/tmp/proxy.ign))
```