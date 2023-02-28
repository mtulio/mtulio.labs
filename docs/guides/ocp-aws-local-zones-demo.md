# Demo: OpenShift in the edge with AWS Local Zones

This is the reference for a demo of deploying an OpenShift cluster on the edge of AWS Cloud with Local Zones. Summary of the [Epic SPLAT-365](https://issues.redhat.com/browse/SPLAT-635).

Table Of Contents:

- [Epic Overview](#epic-overview)
- [Part 1: AWS Local Zones overview ](#part-1)
- [Part 2: Day-2 - Extend OpenShift compute nodes to Local Zones](#part-2)
- [Part 3: Day-0 - Install OpenShift cluster in existing VPC with Local Zones](#part-3)
- [Part 4: Day-0 demo - Installing OpenShift](#part-4)
    - [Demo script](#demo-script)
- [Next Steps](#next-steps)
- [References](#references)

## Epic overview and goals <a name="epic-overview"></a>

- Understand how we can use Local Zones in OCP
- Understand the benefits
- Provide the steps
- Create on the Product documentation how to install the OCP cluster in existing VPC with Local Zone subnets
- Eventually public a blog in the Hybrid Cloud with the results

## Part 1: AWS Local Zones overview <a name="part-1"></a>

- [Product landing page](https://aws.amazon.com/about-aws/global-infrastructure/localzones/)
- Limitations
    - Resources are Limited and more expensive
    - Current limitation
        - EBS type should be gp2
        - Instance Type
        - NLB is not supported
        - Nat Gateway is not supported
- [Example Architecture](https://github.com/mtulio/mtulio.labs/blob/article-ocp-aws-lz/docs/articles/ocp-aws-local-zones-day-2.md#reference-architecture)
- Local Zones are designed specially to compute nodes
    - Using existing VPC only
    - Current options to install OCP:
        - Day-2
        - Day-0

## Part 2: Day-2 - Extend OpenShift compute nodes to Local Zones <a name="part-2"></a>

- Summary of tasks:
    - [SPLAT-526: Day-2 research](https://issues.redhat.com/browse/SPLAT-526)
    - [SPLAT-558: ALB Operator using in Day-2](https://issues.redhat.com/browse/SPLAT-558)

- Steps to use compute nodes in Local Zones ([Day-2](https://github.com/mtulio/mtulio.labs/blob/article-ocp-aws-lz/docs/articles/ocp-aws-local-zones-day-2.md)):
    - Opt in the [Availability Zone Group](https://us-east-1.console.aws.amazon.com/ec2/v2/home?region=us-east-1#Settings:tab=zones)
    - Create the subnet
    - Associate the Route Table
    - Choose the correct gateway (IGW or NatGW*)
    - Create the MachineSet for nodes in the Local Zone
        - Creating the `edge` label
        - Set the node as unscheduled
    - Create the machine
- Benchmark results review

## Part 3: Day-0 - Install OpenShift cluster in existing VPC with Local Zones <a name="part-3"></a>

- Summary of tasks:
    - [SPLAT-557: Day-0 research](https://issues.redhat.com/browse/SPLAT-557)

- Steps to install a cluster in the existing network with compute nodes in Local Zones ([Day-0](https://github.com/mtulio/mtulio.labs/blob/article-ocp-aws-lz/docs/articles/ocp-aws-local-zones-day-0.md))
    - Create VPC and resources
    - Create the Local Zone subnet
        - tag as unmanaged
    - Create the install-config.yaml specifying the subnets to install a cluster
    - [Create the MachineSet manifest on installer install dir](https://docs.openshift.com/container-platform/4.11/installing/installing_aws/installing-aws-vpc.html#installation-aws-config-yaml_installing-aws-vpc)
        - Creating the `edge` label
        - Set the node as unscheduled
    - Create a cluster

## Part 4: Day-0 demo - Installing OpenShift <a name="part-4"></a>

- Day-0 installation
    - `oc aws-zone` plugin used automates the install steps
    - [play demo](https://asciinema.org/a/517836)
- AWS Console:
    - Zone Groups configurations
    - VPC and network resources
    - Local Zone subnet
        - Subnet tag unmanaged
        - public route table
    - Compute resources

### Demo script: quick install using plugin <a name="demo-plugin"></a>

[![asciicast](https://asciinema.org/a/517836.svg)](https://asciinema.org/a/517836)

```bash
# install the plugin
curl -s https://raw.githubusercontent.com/mtulio/mtulio.labs/article-ocp-aws-lz-plugin/labs/oc-plugins/oc-aws_zone -o ${HOME}/bin/oc-aws_zone

chmod u+x ${HOME}/bin/oc-aws_zone

# read the help
oc aws-zone

# create a cluster
CLUSTER_NAME=lzdemo \
        VERSION=4.11.2 \
        CLUSTER_REGION=us-east-1 \
        ZONE_GROUP_NAME=us-east-1-nyc-1a \
        VPC_CIDR='10.0.0.0/16' \
        ZONE_CIDR='10.0.128.0/20' \
        BASE_DOMAIN='devcluster.openshift.com' \
        INSTANCE_TYPE=c5d.2xlarge \
        PULL_SECRET_FILE=${HOME}/.openshift/pull-secret-latest.json \
        SSH_PUB_KEY_FILE=${HOME}/.ssh/id_rsa.pub \
        oc aws-zone create-all

export KUBECONFIG=${PWD}/auth/kubeconfig

# review the installation
oc get clusteroperators

# check the machine
oc get machines -n openshift-machine-api

# checke the edge node
oc get nodes -l node-role.kubernetes.io/edge=''

# destroy the cluster
oc aws-zone destroy-all
```

## Next steps <a name="next-steps"></a>

- Public the steps of Installing a cluster in existing VPC with Local Zone subnets in the Product Documentation
- Installer supports it natively:
    - [Create MachineSets for the "edge" nodes](https://issues.redhat.com/browse/SPLAT-636)
    - [Create the network resources](https://issues.redhat.com/browse/SPLAT-657)
- Current issues:
    - Ingress subnet discovery
        - [Bug on KCM](https://issues.redhat.com/browse/OCPBUGSM-46513)


## References <a name="references"></a>

- [Install OpenShift in the cloud edge with AWS Local Zones](https://dev.to/mtulio/install-openshift-in-the-cloud-edge-with-aws-local-zones-3nh0)
- [OpenShift: Installing a cluster on AWS into an existing VPC
](https://docs.openshift.com/container-platform/4.11/installing/installing_aws/installing-aws-vpc.html)
- [AWS Local Zones](https://aws.amazon.com/about-aws/global-infrastructure/localzones/)
- [Extend kubectl with plugins](https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/)
