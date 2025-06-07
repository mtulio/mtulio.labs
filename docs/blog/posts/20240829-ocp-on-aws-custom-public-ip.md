---
date: 2024-08-28
authors: [mtulio]
description: >
  Deploy OpenShift/OKD on AWS using custom IPv4 address
categories:
  - Kubernetes
  - OpenShift
  - OpenShift/installation
  - cloud/AWS
Tags:
  - Kubernetes
  - OpenShift/installation
  - cloud/AWS
---

# Deploy OpenShift on AWS using custom IPv4 address

Exciting news for admins who wants more control of Public IP address in the Public Cloud! =]

Starting on 4.16, OpenShift/OKD has the capability to use custom Public IPv4 address (Elastic IP (EIP)) when deploying a cluster on AWS. This can help you in different ways:

- Allowing to trust in which address range the nodes will egress traffic from the VPC to Internet, allowing to refine the firewall rules in the target services, such as on-premisses, or services published in the internet with restricted access.
- Allowing to control which address the API server will be used
- Alloing to decrease the IPv4 charges applied to Elastic IP when using the CIDR IPv4 that you brought to your AWS Account

To begging with, take a look at the following guides:
- [Install OCP/OKD on AWS using Public IPv4 Pool][ocp-install-byo-public-ipv4]
- [Install OCP/OKD on AWS using existing Elastic IPs][ocp-install-byo-eip]

[ocp-install-byo-public-ipv4]: ./guides/ocp-install-profiles/ocp-install-aws-byo-eip
[ocp-install-byo-eip]: ./guides/ocp-install-profiles/ocp-install-aws-byo-public-ipv4-pool
