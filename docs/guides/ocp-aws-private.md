---
date: 2024-01-18
authors: [mtulio]
readtime: 20
description: >
  Install private OpenShift cluster on AWS
categories:
  - OpenShift
  - Kubernetes
  - Installation
  - AWS
  - Security
  - Private
tags:
  - OpenShift
  - Kubernetes
  - Installation
  - AWS
  - Security
  - Private
---

# Hands on steps to install restricted OpenShift clusters on AWS | Solutions

This post makes references tutorials/solutions with handful steps to
install OpenShift clusters on restricted/private networks on AWS.

## Solutions 1 - Restricted with proxy

Options:

- Installing OCP on AWS with proxy
- Installing OCP on AWS with proxy and STS
- Installing OCP on AWS in disconnected clusters (no internet access)
- Installing OCP on AWS in disconnected clusters with STS


### Solution 1A) Hands on steps to install restricted OpenShift cluster in existing VPC on AWS

The steps described in this section shows step-by-step (copy/paste approach) how to deploy a private cluster on AWS without exposing any service to internet.

The approach is based in the product documentation ["Installing a cluster on AWS in a restricted network"][ocp-installing-aws-restricted].

This guide introduce [Nested CloudFormation Stacks][aws-cfn-nested] allowing to reduce coupling and increase cohesion when developing and infrastructure as a code (IaC) code with CloudFormation Templates.

This guide also introduce a **bastion host in private subnet** used to jump into
the private VPC using [AWS Systems Manager Session Manager][aws-session-manager], without needing create VPN, expose/ingress internet traffic to nodes, etc. Alternatively, you can forward the traffic from the internal API Load Balancer from the client (outside the VPC) using AWS SSM Session Port forwarding, allowing to quickly access the OpenShift clusters without leaving your "home". =]

Lastly but not least, this guide also shows how to deploy Highly Available and scalable Proxy service using Autoscaling Group to spread the nodes across zones, Network Load Balancer to distributed the traffic equally between nodes, and reduce costs by using Spot EC2 Instances (capacity managed and balanced natively using ASG/Fleet).

[ocp-installing-aws-restricted]: https://docs.openshift.com/container-platform/4.14/installing/installing_aws/installing-restricted-networks-aws-installer-provisioned.html#installation-custom-aws-vpc-requirements_installing-restricted-networks-aws-installer-provisioned
[aws-cfn-nested]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-nested-stacks.html
[aws-session-manager]: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html

Pros:

- Cheaper cluster:
    - No NAT Gateway charges
    - No public IPv4 address
    - No public Load Balancer for API
- Restricted web access with Proxy
- Private access to clusters using native AWS services (AWS SSM tunneling), reducing the needed of VPN or extra connectivity
- More controlled environment
- HA and scalable Proxy service
- (Optional) Shared HA proxy service using AWS PrivateLink [TODO]

Cons:

- increase manual steps to setup the entire environment (including proxy service) when comparing with regular IPI


Steps:

Solutions/Architectures/Deployments:

S1) Deploy OpenShift in single stack IPv4 VPC with dedicated proxy in public subnets

- [ocp-aws-private-01-pre.md](./ocp-aws-private-01-pre.md)
- [ocp-aws-private-02-deploy-vpc-ipv4.md](./ocp-aws-private-02-vpc-ipv4-pub-blackhole.md)
- [ocp-aws-private-03_01-proxy-config.md](./ocp-aws-private-03_01-proxy-config.md)
- [ocp-aws-private-03_02-proxy-deploy-dedicated.md](./ocp-aws-private-03_02-proxy-deploy-dedicated.md)
- [Deploy private OpenShift cluster with dedicated proxy in VPC](./ocp-aws-private-04-cluster-install-proxy-jump.md)




### Solution 1B) Hands on steps to install restricted OpenShift cluster in existing VPC on AWS with STS

> TODO

Requires a fix for ccoctl to use HTTP_PROXY


### 1C) Deploy OpenShift in single stack IPv4 VPC with shared proxy server IPv4

Step 1) Deploy shared proxy service

- Create Service VPC
- Deploy Proxy Server
- Deploy Custom VPC Service 

Step 2) Create VPC with private subnets

- Create VPC
- Create 

Step 2A) Deploy OpenShift cluster in private mode

- Deploy jump server using IPv6
- Deploy OpenShift using shared proxy service

Step 2B) Deploy OpenShift cluster in private mode

- Deploy jump server using private ipv4 and SSM access
- Deploy OpenShift using shared proxy service


### 1D) Deploy OpenShift in single stack IPv4 VPC with shared proxy server IPv6

Steps to deploy dual-stack VPC, with proxy runnnin in dual-stack VPC with IPv6
egress traffic to the internet, and OpenShift cluster running in single stack IPv4
on private subnets.

Read the [IPv6 deployment guide](./ocp-aws-private-ipv6-egress.md).

## Solutions 2 - Private clusters with shared services

### 2A) Shared Proxy services 

> TODO: steps to deploy service VPC sharing Proxy and Image registry through AWS VPC PrivateLink

### 2B) Deploy hub/spoke service using Transit Gateway

> TODO describe how to deploy hub/spoke topology using Transit Gateway to centralize egress OpenShift traffic in management VPC.

Option 1) Public clusters ingressing traffic in the VPC, egressing through Transit Gateway
Option 2) Private clusters using ingress and egress traffic through internal network

See [reference guide](../../guides/ocp-aws-transit-gateway.md)