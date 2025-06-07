## Deploy bastion host

!!! warning "Experimental steps"
    The steps described on this page are experimental!

The bastion host will be responsible to forward traffic to the resources deployed in the private subnets using AWS SSM tunnels without requiring the node be accessed through the internet.

Bastion node requires:

- AWS SSM agent installed
- AWS IAM Policy attached to the EC2 instance profile

### Prerequisites

- Proxy configuration (PROXY_SERVICE_URL environment)
- [butane](https://coreos.github.io/butane/specs/)

### Create bastion host configuration (ignition)

- Config:

```sh
export REGION=us-east-1
export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
```

- Generate user data (ignitions) for proxy node server (squid):

```sh
function config_bastion() {
  echo "Getting FCOS..."
  BASTION_WORKDIR=${WORKDIR}/bastion
  mkdir -p $BASTION_WORKDIR
  curl -L -o ${BASTION_WORKDIR}/fcos.json https://builds.coreos.fedoraproject.org/streams/stable.json

echo "Exporting config..."
export BASTION_SSM_IMAGE=quay.io/mrbraga/aws-ssm-agent:latest
export BASTION_NAME="${PREFIX_VARIANT}-bastion"
export BASTION_AMI_ID=$(jq -r .architectures.x86_64.images.aws.regions[\"${AWS_REGION}\"].image < ${BASTION_WORKDIR}/fcos.json)

echo "Using bastion AMI ID [$BASTION_AMI_ID]"

echo "Generating bastion ignition config..."
cat <<EOF > ${BASTION_WORKDIR}/bastion-config.bu
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
          http_proxy=${PROXY_SERVICE_URL}
          HTTP_PROXY=${PROXY_SERVICE_URL}
          #https_proxy=${PROXY_SERVICE_URL_TLS}
          #HTTPS_PROXY=${PROXY_SERVICE_URL_TLS}
          https_proxy=${PROXY_SERVICE_URL}
          HTTPS_PROXY=${PROXY_SERVICE_URL}
          all_proxy=${PROXY_SERVICE_URL}
          no_proxy=${BASTION_SERVICE_NO_PROXY}
          NO_PROXY=${BASTION_SERVICE_NO_PROXY}
    # - path: /etc/aws.env
    #   mode: 0644
    #   contents:
    #     inline: |
    #       AWS_ENDPOINT_URL_SSM=${BASTION_AWS_ENDPOINT_SSM}
    #       AWS_ENDPOINT_URL_EC2MESSAGES=${BASTION_AWS_ENDPOINT_EC2MESSAGES}
    #       AWS_ENDPOINT_URL_SSMMESSAGES=${BASTION_AWS_ENDPOINT_SSMMESSAGES}

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
        #EnvironmentFile=/etc/aws.env
        ExecStartPre=podman pull ${BASTION_SSM_IMAGE}
        ExecStart=podman run -d --name aws-ssm-agent ${BASTION_SSM_IMAGE}
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


butane ${BASTION_WORKDIR}/bastion-config.bu --output ${BASTION_WORKDIR}/bastion-config.json

echo "Exporting user data to env BASTION_USER_DATA"
export BASTION_USER_DATA=$(base64 -w0 <(<${BASTION_WORKDIR}/bastion-config.json))

}
```

### References

- AWS CLI standard environment variables for `AWS_ENDPOINT_URL_<SERVICE>`: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html
- AWS Service endpoints table: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-endpoints.html#endpoints-service-specific-table

