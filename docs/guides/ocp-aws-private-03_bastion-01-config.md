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

- Generate user data (ignitions) for proxy node server (squid):

```sh
curl -L -o /tmp/fcos.json https://builds.coreos.fedoraproject.org/streams/stable.json

export REGION=us-east-1
export SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub
export BASTION_SSM_IMAGE=quay.io/mrbraga/aws-ssm-agent:latest
export BASTION_NAME="${PREFIX_VARIANT}-bastion"
export BASTION_AMI_ID=$(jq -r .architectures.x86_64.images.aws.regions[\"${AWS_REGION}\"].image < /tmp/fcos.json)

export BASTION_SERVICE_NO_PROXY="$PROXY_SERVICE_NO_PROXY,ec2messages.$REGION.amazonaws.com,ssm.$REGION.amazonaws.com"

export BASTION_AWS_ENDPOINT_SSM=https://$(aws ec2 describe-vpc-endpoints \
  --filters Name=vpc-id,Values=$VPC_ID \
  | jq -r '.VpcEndpoints[] | select(.ServiceName | endswith("ssm")).DnsEntries[0].DnsName')
export BASTION_AWS_ENDPOINT_SSMMESSAGES=https://$(aws ec2 describe-vpc-endpoints \
  --filters Name=vpc-id,Values=$VPC_ID \
  | jq -r '.VpcEndpoints[] | select(.ServiceName | endswith("ssmmessages")).DnsEntries[0].DnsName')
export BASTION_AWS_ENDPOINT_EC2MESSAGES=https://$(aws ec2 describe-vpc-endpoints \
  --filters Name=vpc-id,Values=$VPC_ID \
  | jq -r '.VpcEndpoints[] | select(.ServiceName | endswith("ec2messages")).DnsEntries[0].DnsName')
# https://developers.redhat.com/blog/2020/03/12/how-to-customize-fedora-coreos-for-dedicated-workloads-with-ostree#the_rpm_ostree_tool
# https://docs.fedoraproject.org/en-US/fedora-coreos/running-containers/
# https://docs.fedoraproject.org/en-US/fedora-coreos/proxy/

cat <<EOF > ~/tmp/bastion-config.bu
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
    - path: /etc/aws.env
      mode: 0644
      contents:
        inline: |
          AWS_ENDPOINT_URL_SSM=${BASTION_AWS_ENDPOINT_SSM}
          AWS_ENDPOINT_URL_EC2MESSAGES=${BASTION_AWS_ENDPOINT_EC2MESSAGES}
          AWS_ENDPOINT_URL_SSMMESSAGES=${BASTION_AWS_ENDPOINT_SSMMESSAGES}

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
        EnvironmentFile=/etc/aws.env
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


butane ~/tmp/bastion-config.bu --output ~/tmp/bastion-config.json


export BASTION_USER_DATA=$(base64 -w0 <(<~/tmp/bastion-config.json))
```

### References

- AWS CLI standard environment variables for `AWS_ENDPOINT_URL_<SERVICE>`: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html
- AWS Service endpoints table: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-endpoints.html#endpoints-service-specific-table

