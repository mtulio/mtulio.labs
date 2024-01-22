# Notes | AWS SSM Agent

Random notes about using AWS SSM agent and remote session.

See more structured guide at:

- [Guides/ocp-aws-private-00-build-image-ssm.md](../../guides/ocp-aws-private-00-build-image-ssm.md)
- [Guides/ocp-aws-private-03_bastion-00-about.md](../../guides/ocp-aws-private-03_bastion-00-about.md)

___
___

<<< DRAFT >>>

# Build SSM image extension

## Setup VPC Endpoint for SSM

> https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html

> TODO check only needed endppints

```sh
com.amazonaws.us-east-1.ssmmessages	
com.amazonaws.us-east-1.ec2messages	
com.amazonaws.us-east-1.ssm	
```

## Installing AWS SSM Agent (server/jump node)

### Install manually on Linux



### Create a container image for SSM Agent

```sh
# https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html#sysman-install-ssm-agent
# https://docs.aws.amazon.com/systems-manager/latest/userguide/agent-install-rhel-8-9.html
# https://github.com/aws/amazon-ssm-agent
VERSION=3.2.2086.0
NAME=aws-ssm-agent
cat <<EOF> $NAME.Containerfile
FROM quay.io/fedora/fedora-minimal:39
WORKDIR /home/core
RUN rpm -i https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/$VERSION/linux_amd64/amazon-ssm-agent.rpm

CMD ["/usr/bin/amazon-ssm-agent"]
EOF

podman build -t quay.io/mrbraga/$NAME:$VERSION -f $NAME.Containerfile /tmp
podman push quay.io/mrbraga/$NAME:$VERSION

podman tag quay.io/mrbraga/$NAME:$VERSION quay.io/mrbraga/$NAME:latest
podman push quay.io/mrbraga/$NAME:latest
```

## Installing session manager plugin (client)

```sh
# https://docs.aws.amazon.com/systems-manager/latest/userguide/plugin-version-history.html
VERSION=1.2.553.0
cat <<EOF> aws-session-manager.Containerfile
FROM quay.io/fedora/fedora-minimal:39
WORKDIR /ssm
RUN rpm -i https://s3.amazonaws.com/session-manager-downloads/plugin/${VERSION}/linux_64bit/session-manager-plugin.rpm \
    && microdnf install -y awscli \
    && microdnf clean all
EOF

podman build -t quay.io/mrbraga/aws-session-manager-plugin:$VERSION -f aws-session-manager.Containerfile /tmp
podman push quay.io/mrbraga/aws-session-manager-plugin:$VERSION

podman tag quay.io/mrbraga/aws-session-manager-plugin:$VERSION quay.io/mrbraga/aws-session-manager-plugin:latest
podman push quay.io/mrbraga/aws-session-manager-plugin:latest
```

References:

- https://docs.aws.amazon.com/systems-manager/latest/userguide/install-plugin-linux.html


## Create ignition configuration

> TODO

> Temp steps to install in the bastion/jump host:

```sh
sudo podman create --name ssm quay.io/mrbraga/aws-session-manager-plugin:latest
sudo podman cp ssm:/usr/local/sessionmanagerplugin/bin/session-manager-plugin /usr/local/bin/
sudo podman cp ssm:/etc/systemd/system/session-manager-plugin.service /tmp/
cat <<EOF> /etc/systemd/system/session-manager-plugin.service
[Unit]
Description=session-manager-plugin
After=network-online.target

[Service]
Type=simple
#WorkingDirectory=/usr/local/sessionmanagerplugin/bin/
ExecStart=/usr/local/bin/session-manager-plugin
KillMode=process
Restart=on-failure
RestartSec=10min

[Install]
WantedBy=multi-user.target
EOF

sudo cat <<EOF> /etc/init/session-manager-plugin.conf
# Copyright 2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.

description     "Amazon SSM SessionManager Plugin"
author          "Amazon.com"

start on (runlevel [345] and started network)
stop on (runlevel [!345] or stopping network)

respawn

exec /usr/local/sessionmanagerplugin/bin/session-manager-plugin
EOF

systemctl enable --now session-manager-plugin.service
```

In the client, start the port forwarding:

```sh
INSTANCE_ID=$(aws ec2 describe-instances \
    --filter "Name=tag:Name,Values=CodeStack/NewsBlogInstance" \
    --query "Reservations[].Instances[?State.Name == 'running'].InstanceId[]" \
    --output text)
aws ssm start-session --target $INSTANCE_ID \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["80"],"localPortNumber":["9999"]}'

SSM_JUMP_INSTANCE_ID=$(aws ec2 describe-instances --filter Name=tag:Name,Values=lab-ci-22-proxy --query "Reservations[].Instances[].InstanceId" --output text)
aws ssm start-session \
    --target ${SSM_JUMP_INSTANCE_ID} \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters '{"portNumber":["6443"],"localPortNumber":["6443"],"host":["api.lab415.devcluster.openshift.com"]}'
```

- Replace the server target in the kubeconfig to localhost

- access the cluster with localhost

## Create a tunnel

> https://aws.amazon.com/blogs/aws/new-port-forwarding-using-aws-system-manager-sessions-manager/

- Associate managed policy to the instance role:
    - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

- Create the service endpoint

- Patch the kubeconfig to use the tunnel

```sh
scp $PROXY_SSH_OPTS core@$PROXY_SSH_ADDR:~/auth/kubeconfig ~/tmp/kubeconfig

cat <<EOF |yq3 merge - ~/tmp/kubeconfig > ~/tmp/kubeconfig-tunnel
clusters:
- cluster:
    server: https://localhost:6443
EOF

```

- Start the tunnel using podman (not working):

```sh

# install the session-manager locally, or run the container
podman run -v $HOME/.aws:/root/.aws:Z -p 6443:6443 -it quay.io/mrbraga/aws-session-manager-plugin:latest aws ssm start-session --debug     --target ${SSM_JUMP_INSTANCE_ID}     --document-name AWS-StartPortForwardingSessionToRemoteHost     --parameters '{"portNumber":["6443"],"localPortNumber":["6443"],"host":["api.lab415.devcluster.openshift.com"]}'

```

- Start the tunnel in the client (my notebook):

```sh
aws ssm start-session \
--target ${SSM_JUMP_INSTANCE_ID} \
--document-name AWS-StartPortForwardingSessionToRemoteHost \
--parameters '{"portNumber":["6443"],"localPortNumber":["6443"],"host":["api.lab415.devcluster.openshift.com"]}' &
```

- Access the kube apiserver:

```sh
oc --kubeconfig ~/tmp/kubeconfig-tunnel get nodes
```

## Using it

- Run the container in the target machine

- Check the instance registered in the System Manager console: https://us-east-1.console.aws.amazon.com/systems-manager/inventory?region=us-east-1
