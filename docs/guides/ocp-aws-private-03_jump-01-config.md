## Deploy jump node

!!! warning "Experimental steps"
    The steps described on this page are experimental!

The jump node will be responsible to forward traffic to the resources deployed in the private subnets using AWS SSM tunnels without requiring the node be accessed through the internet.

Jump node requires:

- AWS SSM agent installed
- AWS IAM Policy attached to the EC2 instance profile

### Prerequisites

- Proxy configuration (PROXY_SERVICE_URL environment)
- [butane](https://coreos.github.io/butane/specs/)

### Create jump server configuration (ignition)

- Generate user data (ignitions) for proxy node server (squid):

```sh
curl -L -o /tmp/fcos.json https://builds.coreos.fedoraproject.org/streams/stable.json

export JUMP_SSM_IMAGE=quay.io/mrbraga/aws-ssm-agent:latest
export JUMP_NAME="${PREFIX_VARIANT}-jump"
export JUMP_AMI_ID=$(jq -r .architectures.x86_64.images.aws.regions[\"${AWS_REGION}\"].image < /tmp/fcos.json)

# https://developers.redhat.com/blog/2020/03/12/how-to-customize-fedora-coreos-for-dedicated-workloads-with-ostree#the_rpm_ostree_tool
# https://docs.fedoraproject.org/en-US/fedora-coreos/running-containers/
# https://docs.fedoraproject.org/en-US/fedora-coreos/proxy/

cat <<EOF > jump-config.bu
variant: fcos
version: 1.0.0
passwd:
  users:
    - name: core
      ssh_authorized_keys:
        - ssh-rsa AAAAB3Nza...

storage:
  files:
    - path: /etc/proxy.env
      mode: 0644
      contents:
        inline: |
          https_proxy="${PROXY_SERVICE_URL}"
          all_proxy="${PROXY_SERVICE_URL}"
          http_proxy="${PROXY_SERVICE_URL}"
          HTTP_PROXY="${PROXY_SERVICE_URL}"
          HTTPS_PROXY="${PROXY_SERVICE_URL}"
          no_proxy="*.vpce.amazonaws.com,127.0.0.1,169.254.*,localhost"

systemd:
  units:
    - name: aws-ssm-agent.service
      enabled: true
      contents: |
        [Unit]
        Description=AWS SSM Agent
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=forking
        KillMode=none
        Restart=on-failure
        RemainAfterExit=yes
        EnvironmentFile=/etc/proxy.env
        ExecStartPre=podman pull ${JUMP_SSM_IMAGE}
        ExecStart=podman run -d --name aws-ssm-agent ${JUMP_SSM_IMAGE}
        ExecStop=podman stop -t 10 aws-ssm-agent
        ExecStopPost=podman rm aws-ssm-agent

        [Install]
        WantedBy=multi-user.target

    # Proxy
    - name: rpm-ostreed.service
      dropins:
        - name: 99-proxy.conf
          contents: |
            [Service]
            EnvironmentFile=/etc/proxy.env
    - name: zincati.service
      dropins:
        - name: 99-proxy.conf
          contents: |
            [Service]
            EnvironmentFile=/etc/proxy.env
    - name: rpm-ostree-countme.service
      dropins:
        - name: 99-proxy.conf
          contents: |
            [Service]
            EnvironmentFile=/etc/proxy.env
EOF



fcct -input example-fcc-systemd.yaml -output example-ignition-systemd.json






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
envsubst < ${WORKDIR}/proxy-template/proxy.ign.template > /tmp/proxy.ign
test -f /tmp/proxy.ign || echo "Failed to create /tmp/proxy.ign"

# publish ignition to shared bucket
export PROXY_URI="s3://${BUCKET_NAME}/proxy.ign"
export PROXY_URL="https://${BUCKET_NAME}.s3.amazonaws.com/proxy.ign"

aws s3 cp /tmp/proxy.ign $PROXY_URI

# Generate Proxy Instance user data
export PROXY_USER_DATA=$(envsubst < ${WORKDIR}/proxy-template/userData.ign.template | base64 -w0)
```