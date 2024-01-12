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

export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
export JUMP_SSM_IMAGE=quay.io/mrbraga/aws-ssm-agent:latest
export JUMP_NAME="${PREFIX_VARIANT}-jump"
export JUMP_AMI_ID=$(jq -r .architectures.x86_64.images.aws.regions[\"${AWS_REGION}\"].image < /tmp/fcos.json)

# https://developers.redhat.com/blog/2020/03/12/how-to-customize-fedora-coreos-for-dedicated-workloads-with-ostree#the_rpm_ostree_tool
# https://docs.fedoraproject.org/en-US/fedora-coreos/running-containers/
# https://docs.fedoraproject.org/en-US/fedora-coreos/proxy/

cat <<EOF > ~/tmp/jump-config.bu
variant: fcos
version: 1.0.0
passwd:
  users:
    - name: core
      ssh_authorized_keys:
        - "$(<${SSH_PUB_KEY_FILE})"

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
          no_proxy="${PROXY_SERVICE_NO_PROXY}"
          NO_PROXY="${PROXY_SERVICE_NO_PROXY}"

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


butane ~/tmp/jump-config.bu --output ~/tmp/jump-config.json


export JUMP_USER_DATA=$(base64 -w0 <(<~/tmp/jump-config.json))
```