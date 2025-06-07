---
date: 2024-08-21
authors: [mtulio]
description: >
  Deploy a Cost-Effective OpenShift/OKD Cluster on Azure
categories:
  - Kubernetes
  - OpenShift
  - OpenShift/installation
  - cloud/Azure
Tags:
  - Kubernetes
  - OpenShift
  - OpenShift/installation
  - cloud/Azure
---

# Deploy a Cost-Effective OpenShift/OKD Cluster on Azure

Are you looking to deploy a cheaper OpenShift/OKD cluster on Azure without sacrificing performance? Keep reading this post!

Starting with version 4.17, **OpenShift/OKD** has transitioned to using the Cluster API as its provisioning engine by installer. This change allows for greater flexibility in customizing control plane resources.

## Key Steps in the Deployment Process

This guide walks you through the following steps to optimize your Azure deployment:

  - **Patch the AzureMachine Manifests**:Inject an additional data disk to mount etcd, reduce the size of the OS disk, and upgrade the VM generation. These adjustments can decrease the disk size by half compared to current values.
  - **Add MachineConfig Manifests**: Additional manifests will be included to mount the etcd path to the data disk. This setup isolates the database from OS disk operations, improving overall performance.
  - **Utilize Premium Storage**: The guide recommends using the new **PremiumV2_LRS** storage account type, which offers performance characteristics similar to AWS's gp3. This configuration provides higher IOPS and throughput without the need for high capacity, ensuring efficient resource utilization.

To explore more about these steps and how to implement them, take a look at the guide titled Installing on Azure with etcd in Data Disks (CAPI).

If you have any questions or need further assistance, feel free to reach out!

[guide]: ./guides/ocp-install-profiles/ocp-azure-capz-datadisk-etcd.md
