# oc plugin to install OpenShift cluster in the edge with AWS Local Zones

This post describes how to use the kubectl/oc plugin to install an OpenShift
cluster in existing VPC with Local Zone subnet - the network resources will be also created.

The following resources will be created:

- CloudFormation stack for VPC (VPC, subnets, Nat and Internet Gateways, route tables, etc)
- CloudFormation stack for Subnet located on the Local Zone (subnet and route table association)
- OpenShift cluster

The `aws-zone` plugin is the automated way described in detail on the article ["Install OpenShift cluster in the edge with AWS Local Zones"](./ocp-aws-local-zones-day-0.md).

[![asciicast](https://asciinema.org/a/514257.svg)](https://asciinema.org/a/514257)

**Table Of Contents**:

- [Install/enable plugin](#install)
- [Basic Usage/Helper](#usage)
- [Create cluster](#create)
- [Destroy cluster](#destroy)
- [References](#references)

## Install/enable plugin <a name="install"></a>

To extend the kubectl/oc commands you just need to save the binary/script on the format `kubectl-plugin_name` in any place set in your `$PATH`, so the plugin can be called running `kubectl plugin-name <options>`. As openshift CLI `oc` extends the `kubectl` binary, we can also create the file `oc-plugin_name` and use it calling `oc plugin-name <options>`

To read more about kubectl plugins, read this [documentation](https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/).

Said that, let's install the plugin into the `${HOME}/bin`:

```bash
curl -s https://raw.githubusercontent.com/mtulio/mtulio.labs/article-ocp-aws-lz-plugin/labs/oc-plugins/oc-aws_zone \
  -o ${HOME}/bin/oc-aws_zone
```

Set it executable:

```bash
chmod u+x ${HOME}/bin/oc-aws_zone
```

Test it (helper):

```bash
oc aws-zone
```

## Basic Usage/Helper <a name="usage"></a>

Explore what you need on the help

```bash
$ oc aws-zone
Usage: /home/bin/oc-aws_zone command

Available commands:
    "preflight"         : Run Preflight test to check if you are missing required dependencies.
    "install-clients"   : Install OpenShift clients oc and openshift-install
    "create-stack-vpc"  : Create a CloudFormation stack to setup VPC
    "check-stack-vpc"   : Check current CloudFormation VPC stack
    "delete-stack-vpc"  : Remove the CloudFormation VPC stack
    "create-stack-zone" : Create a CloudFormation stack to setup the subnet on edge Zone
    "check-stack-zone"  : Check current CloudFormation Zone stack
    "delete-stack-zone" : Remove the CloudFormation Zone stack
    "install-config"    : Create the install-config.yaml
    "install-manifests" : Create the manifests based on the install-config.yaml
    "create-cluster"    : Create the OCP cluster
    "destroy-cluster"   : Destroy the OCP cluster
    "check-cluster"     : Check the existing OCP cluster
    "create-all"        : Create the VPC, Subnet on edge zone, then the OCP cluster in existing VPC approach
```


## Create Cluster <a name="create"></a>

```bash
CLUSTER_NAME=lzdemo \
    VERSION=4.11.0 \
    CLUSTER_REGION=us-east-1 \
    ZONE_GROUP_NAME=us-east-1-nyc-1a \
    VPC_CIDR='10.0.0.0/16' \
    ZONE_CIDR='10.0.128.0/20' \
    BASE_DOMAIN='devcluster.openshift.com' \
    INSTANCE_TYPE=c5d.2xlarge \
    PULL_SECRET_FILE=${HOME}/.openshift/pull-secret-latest.json \
    SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub \
    oc aws-zone create-all
```

## Destroy Cluster <a name="destroy"></a>

```bash
CLUSTER_NAME=lzdemo \
    CLUSTER_REGION=us-east-1 \
    ZONE_GROUP_NAME=us-east-1-nyc-1a \
    oc aws-zone destroy-cluster
```
