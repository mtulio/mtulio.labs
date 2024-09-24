---
date: 2024-09-16
authors: [mtulio]
description: >
  Explore the Cloud Credentials required by OKD
categories:
  - Kubernetes
  - OpenShift
  - OpenShift/installation
  - OpenShift/identity
  - cloud/AWS
Tags:
  - Kubernetes
  - OpenShift
  - OpenShift/installation
  - OpenShift/identity
  - cloud/AWS
---

# Explore the cloud credentials required by OKD on AWS

Are you interested to fine grant cloud Credentials provided to
OKD components when deploying a cluster on AWS?

This guide will walk through how you can track the **required**
API calls to AWS services, compile it and compare with **requested**
by components.

At the end of this exploration will be able to fine grant the IAM permissions
granted for different components, such as IAM Role or IAM User used by
`openshift-installer` or cluster components.

Keep reading in ["OCP on AWS | Experiment | Explore Cloud permissions requested and required"][guide]

[guide]: ../guides/ocp-aws-perms-track-cloudtrail.md
