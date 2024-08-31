## Deploy proxy server

!!! warning "Experimental steps"
    The steps described on this page are experimental!

!!! info "CloudFormation templates"
    The CloudFormation templates mentioned on this page are available in the path:
    [mtulio.labs/labs/labs/ocp-install-iac/aws-cloudformation-templates](https://github.com/mtulio/mtulio.labs/tree/master/labs/ocp-install-iac/aws-cloudformation-templates)


Steps to create TLS configuration for Squid

Based on:
https://github.com/openshift/release/blob/master/ci-operator/step-registry/upi/conf/aws/proxy/upi-conf-aws-proxy-commands.sh

## Steps

- Generate:

```sh
function config_proxy() {
#
# Part 1) Gen certs
#
echo "Generating proxy certs..."

WORKDIR_PROXY="${WORKDIR}/proxy-${1:-00}"
mkdir -p $WORKDIR_PROXY

ROOTCA=${WORKDIR_PROXY}/CA
INTERMEDIATE=${ROOTCA}/INTERMEDIATE

bash -x ${SOURCE_DIR}/proxy/gen-certificates.sh "$ROOTCA" "$INTERMEDIATE"

#
# Part 2) Gen Ignitions
#

# load in certs here
echo "Loading certs..."
PROXY_CERT="$(base64 -w0 ${INTERMEDIATE}/certs/intermediate.cert.pem)"
PROXY_KEY="$(base64 -w0 ${INTERMEDIATE}/private/intermediate.key.pem)"
PROXY_KEY_PASSWORD="$(cat ${ROOTCA}/intpassfile)"

CA_CHAIN="$(base64 -w0 ${INTERMEDIATE}/certs/ca-chain.cert.pem)"

echo "Generating proxy user/pass..."
# create random uname and pw
# pushd ${WORKDIR_PROXY}
PROXY_USER_NAME="proxy"
# popd
#PROXY_PASSWORD="$(uuidgen | sha256sum | cut -b -32)"
PROXY_PASSWORD="proxy"

HTPASSWD_CONTENTS="${PROXY_USER_NAME}:$(openssl passwd -apr1 ${PROXY_PASSWORD})"
HTPASSWD_CONTENTS="$(echo -e ${HTPASSWD_CONTENTS} | base64 -w0)"

KEY_PASSWORD="$(base64 -w0 << EOF
#!/bin/sh
echo ${PROXY_KEY_PASSWORD}
EOF
)"

echo "Creating squid conf..."
# define squid config
SQUID_CONFIG="$(base64 -w0 << EOF
http_port 3128
sslpassword_program /squid/passwd.sh
https_port 3130 cert=/squid/tls.crt key=/squid/tls.key cafile=/squid/ca-chain.pem
cache deny all
access_log stdio:/tmp/squid-access.log all
debug_options ALL,1
shutdown_lifetime 0
auth_param basic program /usr/lib64/squid/basic_ncsa_auth /squid/passwords
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
pid_filename /tmp/proxy-setup
EOF
)"

export PROXY_IMAGE=quay.io/mrbraga/squid:6.6
# PROXY_IMAGE=registry.ci.openshift.org/origin/4.5:egress-http-proxy

echo "Creating proxy.sh..."
# define proxy.sh
PROXY_SH="$(base64 -w0 << EOF
#!/bin/bash
function print_logs() {
while [[ ! -f /tmp/squid-access.log ]]; do
sleep 5
done
tail -f /tmp/squid-access.log
}
print_logs &
squid -N -f /squid/squid.conf
EOF
)"

echo "Creating proxy-config.bu..."
cat <<EOF > ${WORKDIR_PROXY}/proxy-config.bu
variant: fcos
version: 1.0.0
passwd:
  users:
    - name: core
      ssh_authorized_keys:
        - "$(<${SSH_PUB_KEY_FILE})"
storage:
  files:
    - path: /etc/squid/passwords
      user:
        name: root
      contents:
        source: "data:text/plain;base64,${HTPASSWD_CONTENTS}"
      mode: 420
    - path: /etc/squid/tls.crt
      user:
        name: root
      contents:
        source: "data:text/plain;base64,${PROXY_CERT}"
      mode: 420
    - path: /etc/squid/tls.key
      user:
        name: root
      contents:
        source: "data:text/plain;base64,${PROXY_KEY}"
      mode: 420
    - path: /etc/squid/ca-chain.pem
      user:
        name: root
      contents:
        source: "data:text/plain;base64,${CA_CHAIN}"
      mode: 420
    - path: /etc/squid/squid.conf
      user:
        name: root
      contents:
        source: "data:text/plain;base64,${SQUID_CONFIG}"
      mode: 420
    # - path: /etc/squid.sh
    #   user:
    #     name: root
    #   contents:
    #     source: "data:text/plain;base64,${SQUID_SH}"
    #   mode: 420
    - path: /etc/squid/proxy.sh
      user:
        name: root
      contents:
        source: "data:text/plain;base64,${PROXY_SH}"
      mode: 420
    - path: /etc/squid/passwd.sh
      user:
        name: root
      contents:
        source: "data:text/plain;base64,${KEY_PASSWORD}"
      mode: 493
    #- path: /etc/aws-cfn-callback-success.sh
    #  user:
    #    name: root
    #  mode: 0755
    #  contents:
    #    inline: |
    #      #!/usr/bin/env bash
    #      CFN_CALLBACK=\$(aws ssm get-parameter --name "ocp-proxy-cb-cfn-url")
    #      curl -d '{"Status":"SUCCESS","UniqueId" : "SingleCount1","Data" :"Provisioning #finished","Reason":"empty"}'

systemd:
  units:
    - name: squid.service
      enabled: true
      contents: |
        [Unit]
        Description=Proxy Server
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=forking
        KillMode=none
        Restart=on-failure
        RemainAfterExit=yes
        ExecStartPre=podman pull ${PROXY_IMAGE}
        ExecStart=podman run -d --name squid --entrypoint='["bash", "/squid/proxy.sh"]' --expose=3128 --expose=3130 --net host --volume /etc/squid:/squid:Z ${PROXY_IMAGE}
        ExecStop=podman stop -t 10 squid
        ExecStopPost=podman rm squid

        [Install]
        WantedBy=multi-user.target

    - name: cfn-callback.service
      contents: |
        [Unit]
        Description=Send provision callback confirmation to CloudFormation.
        Wants=network-online.target
        After=squid.service

        [Service]
        Type=oneshot
        ExecStart=/bin/bash /etc/aws-cfn-callback-success.sh
        RemainAfterExit=yes

        [Install]
        WantedBy=multi-user.target
      enabled: true
      
    # - dropins:
    #     - contents: |
    #         [Service]
    #         ExecStart=/usr/lib/systemd/systemd-journal-gatewayd --key=/opt/openshift/tls/journal-gatewayd.key --cert=/opt/openshift/tls/journal-gatewayd.crt --trust=/opt/openshift/tls/root-ca.crt
    #       name: certs.conf
    #   name: systemd-journal-gatewayd.service
    # - enabled: true
    #   name: systemd-journal-gatewayd.socket
EOF

echo "Generating ignition file..."
butane ${WORKDIR_PROXY}/proxy-config.bu --output ${WORKDIR_PROXY}/proxy.ign

# Need to fetch from s3 as resulted ignitoin is greater than 4k
#export PROXY_USER_DATA=$(base64 -w0 <(<${WORKDIR_PROXY}/proxy-config.json))

echo "Getting ignition URL..."
export PROXY_IGN_S3="s3://${BUCKET_NAME}/proxy.ign"
export PROXY_IGN_URL=$(aws s3 presign ${PROXY_IGN_S3} --expires-in 3600)

echo "Uploading ignition to S3..."
aws s3 cp ${WORKDIR_PROXY}/proxy.ign $PROXY_IGN_S3

echo "Creating ignition file for user-data..."
cat <<EOF > ${WORKDIR_PROXY}/proxy-userData.bu
variant: fcos
version: 1.0.0
ignition:
  config:
    replace:
      source: "${PROXY_IGN_URL}"
EOF

butane ${WORKDIR_PROXY}/proxy-userData.bu --output ${WORKDIR_PROXY}/proxy-userData.ign

echo "Saving to PROXY_USER_DATA env var"
export PROXY_USER_DATA=$(base64 -w0 <(<${WORKDIR_PROXY}/proxy-userData.ign))

# Export Proxy Serivce URL to be used by clients
export PROXY_DNS_RECORD="lab-proxy.devcluster.openshift.com"

export PROXY_SERVICE_ENDPOINT="$PROXY_DNS_RECORD"
export PROXY_SERVICE_URL="http://${PROXY_USER_NAME}:${PROXY_PASSWORD}@${PROXY_SERVICE_ENDPOINT}:3128"
export PROXY_SERVICE_URL_TLS="https://${PROXY_USER_NAME}:${PROXY_PASSWORD}@${PROXY_SERVICE_ENDPOINT}:3130"
export PROXY_SERVICE_NO_PROXY="169.254.169.254,.vpce.amazonaws.com"

echo "Discovering Hosted Zone from DNS $DNS_BASE_DOMAIN and setting to PROXY_DNS_HOSTED_ZONE_ID..."
export PROXY_DNS_HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name $DNS_BASE_DOMAIN | jq -r ".HostedZones[] | select(.Name==\"$DNS_BASE_DOMAIN.\").Id" | awk -F'/' '{print$3}')

}
```
