## OKD/OCP Private | Build container image for AWS SSM Agent

This spec describes how to create a custom Container image to run the
AWS SSM Agent server,

[AWS SSM Agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html) is responsible to provide access to resources (EC2, Load Balancers)
in private subnets.

The SSM Agent will be used in the article series to forward traffic from the
client running outside AWS/VPC to inside VPC (non-internet routable) resources
in a VPC deployed OpenShift cluster.

To learn more about each solution, visit the specific pages:

- [About using AWS SSM Agent in private clusters](./ocp-aws-private-03_bastion-00-about.md)
- [Github: @aws/amazon-ssm-agent](https://github.com/aws/amazon-ssm-agent)
- [AWS Docs: Install SSM Agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html#sysman-install-ssm-agent)
- [AWS Docs: Install SSM Agent on RHEL](https://docs.aws.amazon.com/systems-manager/latest/userguide/agent-install-rhel-8-9.html)
- [AWS Docs: Install SSM Agent for a hybrid and multicloud environment (Linux)](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-install-managed-linux.html)
- [@mtulio/notes/cloud/aws-ssm.md](../notes/cloud/aws-ssm.md)

## Steps to build the container image for AWS SSM Agent

Steps to create container image for proxy server (squid):

- Export env vars:

```sh
export SERVICE_NAME=aws-ssm-agent
export CONTAINER_REPO_AWS_SSM=quay.io/mrbraga/$SERVICE_NAME
export CONTAINER_VERSION_AWS_SSM=3.2.2086.0
export AWS_SSM_IMAGE=${CONTAINER_REPO_AWS_SSM}:${CONTAINER_VERSION_AWS_SSM}
```

- Build container image:

```sh
cat << EOF > /tmp/$SERVICE_NAME.Containerfile
FROM quay.io/fedora/fedora-minimal:39
WORKDIR /home/core
RUN rpm -i https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/$CONTAINER_VERSION_AWS_SSM/linux_amd64/amazon-ssm-agent.rpm

CMD ["/usr/bin/amazon-ssm-agent"]
EOF

podman build -t $AWS_SSM_IMAGE -f /tmp/$SERVICE_NAME.Containerfile /tmp
podman tag $AWS_SSM_IMAGE $CONTAINER_REPO_AWS_SSM:latest

podman push $AWS_SSM_IMAGE
podman push $CONTAINER_REPO_AWS_SSM:latest

echo -e "***\nImages built: \n\t${AWS_SSM_IMAGE} \n\t$CONTAINER_REPO_AWS_SSM:latest"
```

## Steps to build the container image for AWS CLI

Steps to create container image for proxy server (squid):

- Export env vars:

```sh
export SERVICE_NAME=aws-cli
export CONTAINER_REPO_AWS_AWSCLI=quay.io/mrbraga/$SERVICE_NAME
export CONTAINER_VERSION_AWS_AWSCLI=2.15.11
export AWS_CLI_IMAGE=${CONTAINER_REPO_AWS_AWSCLI}:${CONTAINER_VERSION_AWS_AWSCLI}
```

- Build container image:

```sh
cat << EOF > /tmp/$SERVICE_NAME.Containerfile
FROM quay.io/fedora/fedora-minimal:39
WORKDIR /home/core
RUN microdnf install -y less awscli  \
    && microdnf clean all

CMD ["/usr/bin/aws"]
EOF

podman build -t $AWS_CLI_IMAGE -f /tmp/$SERVICE_NAME.Containerfile /tmp
podman tag $AWS_CLI_IMAGE $CONTAINER_REPO_AWS_AWSCLI:latest

podman push $AWS_CLI_IMAGE
podman push $CONTAINER_REPO_AWS_AWSCLI:latest

echo -e "***\nImages built: \n\t${AWS_CLI_IMAGE} \n\t$CONTAINER_REPO_AWS_AWSCLI:latest"
```