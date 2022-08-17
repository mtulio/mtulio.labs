# OCP on AWS - Using Instance Disks for containers' ephemeral storage

This document describes how to use the EC2 Instance ephemeral disk mounted on the container ephemeral storage `/var/lib/containers` on Kubernetes/OpenShift.

Table of Contents:

- [Create the MachineConfig](#create-mconfig)
- [Create the MachineSet](#create-mset)
- [Create the MachineConfig](#create-mconfig)
- [Review the performance](#review)
- [Review the performance](#reference)

### Create the MachineConfig <a name="create-mconfig"></a>

The MachineConfig should create the systemd units to:

- create the filesystem on the new device
- mount the device on the path `/var/lib/containers`
- restore the SELinux context

Steps:

- Export the device path presented to your instance for the ephemeral device (in general `/dev/nvme1n1`):

```bash
export DEVICE_NAME=nvme1n1
```

- Create the MachineConfig manifest

```bash
cat <<EOF | envsubst | oc create -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 98-var-lib-containers
spec:
  config:
    ignition:
      version: 3.1.0
    systemd:
      units:
      - contents: |
          [Unit]
          Description=Make File System on /dev/${DEVICE_NAME}
          DefaultDependencies=no
          BindsTo=dev-${DEVICE_NAME}.device
          After=dev-${DEVICE_NAME}.device var.mount
          Before=systemd-fsck@dev-${DEVICE_NAME}.service

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=-/bin/bash -c "/bin/rm -rf /var/lib/containers/*"
          ExecStart=/usr/lib/systemd/systemd-makefs xfs /dev/${DEVICE_NAME}
          TimeoutSec=0

          [Install]
          WantedBy=var-lib-containers.mount
        enabled: true
        name: systemd-mkfs@dev-${DEVICE_NAME}.service
      - contents: |
          [Unit]
          Description=Mount /dev/${DEVICE_NAME} to /var/lib/containers
          Before=local-fs.target
          Requires=systemd-mkfs@dev-${DEVICE_NAME}.service
          After=systemd-mkfs@dev-${DEVICE_NAME}.service

          [Mount]
          What=/dev/${DEVICE_NAME}
          Where=/var/lib/containers
          Type=xfs
          Options=defaults,prjquota

          [Install]
          WantedBy=local-fs.target
        enabled: true
        name: var-lib-containers.mount
      - contents: |
          [Unit]
          Description=Restore recursive SELinux security contexts
          DefaultDependencies=no
          After=var-lib-containers.mount
          Before=crio.service

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=/sbin/restorecon -R /var/lib/containers/
          TimeoutSec=0

          [Install]
          WantedBy=multi-user.target graphical.target
        enabled: true
        name: restorecon-var-lib-containers.service
EOF

```

### Create the MachineSet <a name="create-mset"></a>

The second step is to create the MachineSet to launch the instance with ephemeral disks available. You should choose one from AWS offering. In general instances with ephemeral disks finishes the type part with the letter "`d`", for example, the instance of the Compute-optimized family (`C`) in the 6th-generation of Intel processors (`i`) with ephemeral storage, will be the type `C6id`.

In my case I will use the instance type and size `c6id.xlarge` which provides ephemeral storage of `237 GB NVMe SSD`.

```bash
export INSTANCE_TYPE=m6id.xlarge
```

Get the CLUSTER_ID:

```bash
export CLUSTER_ID="$(oc get infrastructure cluster \
    -o jsonpath='{.status.infrastructureName}')"
```

Create the MachineSet:
```bash
cat <<EOF | envsubst | oc create -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
  name: ${CLUSTER_ID}-worker-ephemeral
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-worker-ephemeral
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-worker-ephemeral
    spec:
      metadata:
        labels:
          disk_type: "ephemeral"
      providerSpec:
        value:
          ami:
            id: ami-0722eb0819717090f
          apiVersion: machine.openshift.io/v1beta1
          blockDevices:
          - ebs:
              encrypted: true
              iops: 0
              kmsKey:
                arn: ""
              volumeSize: 120
              volumeType: gp3
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: ${CLUSTER_ID}-worker-profile
          instanceType: ${INSTANCE_TYPE}
          kind: AWSMachineProviderConfig
          placement:
            availabilityZone: us-east-1a
            region: us-east-1
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - ${CLUSTER_ID}-worker-sg
          subnet:
            filters:
            - name: tag:Name
              values:
              - ${CLUSTER_ID}-private-us-east-1a
          tags:
          - name: kubernetes.io/cluster/${CLUSTER_ID}
            value: owned
          userDataSecret:
            name: worker-user-data
EOF
```

Wait for the node to be created (it could take up to 3 minutes to node be Ready)

```bash
oc get node -l disk_type=ephemeral -w
```

Make sure the device has been mounted correctly to the mount path `/var/lib/containers`

```bash
oc debug node/$(oc get nodes -l disk_type=ephemeral -o jsonpath='{.items[0].metadata.name}') -- chroot /host /bin/bash -c "df -h /var/lib/containers"
```

## Review the performance <a name="review"></a>

We will use the quick [FIO](https://fio.readthedocs.io/en/latest/fio_doc.html) test using the tool that is commonly used to evaluate the disk for etcd.

> Used on OpenShift for etcd](https://access.redhat.com/articles/6271341) quick tests

```bash
export label_disk=ephemeral
export node_name=$(oc get nodes -l disk_type=${label_disk} -o jsonpath='{.items[0].metadata.name}')
```

Run quick FIO test (used for etcd):

- Running on an ephemeral device

```bash
export disk_type=ephemeral
export base_path="/var/lib/containers/_benchmark_fio"

oc debug node/${node_name} -- chroot /host /bin/bash -c \
    "mkdir -p ${base_path}; podman run --volume ${base_path}:/var/lib/etcd:Z quay.io/openshift-scale/etcd-perf" > ./results-${disk_type}-fio_etcd.txt
```

- Running on the root volume (EBS):

```bash
export disk_type=ebs
export base_path="/var/lib/misc/_benchmark_fio"

oc debug node/${node_name} -- chroot /host /bin/bash -c \
    "mkdir -p ${base_path}; podman run --volume ${base_path}:/var/lib/etcd:Z quay.io/openshift-scale/etcd-perf" > ./results-${disk_type}-fio_etcd.txt
```

- Check the results

```
$ tail -n 3 results-*-fio*.txt
==> results-ebs-fio_etcd.txt <==
--------------------------------------------------------------------------------------------------------------------------------------------------------
99th percentile of fsync is 4046848 ns
99th percentile of the fsync is within the recommended threshold - 10 ms, the disk can be used to host etcd

==> results-ephemeral-fio_etcd.txt <==
--------------------------------------------------------------------------------------------------------------------------------------------------------
99th percentile of fsync is 203776 ns
99th percentile of the fsync is within the recommended threshold - 10 ms, the disk can be used to host etcd
```

You can see the incredible results of ephemeral disks (`0.203ms`) with almost 20x faster comparing the default EBS (`4.04ms`) disk volumes.

> You should repeat the test more times and check the results to normalize the results, as that disk is shared with workloads (containers) that could be using the disk at the same time.

## Overview

This is a quick evaluation of the usage of instances with ephemeral storage:
There are a few points to consider when moving to use instances with local storage, some kind of workloads has more pattern than others. Example of workloads:

- Ephemeral storage for containers, where applications can use it intensively without caring about impacting or sharing resources with OS-disks
- Applications that need to handle data or buffers disks, or need to read/write data from disks frequently

pros:

- super fast local storage, instead of remote storage (EBS)
- It's "free": you will not pay for extra EBS to achieve more performance, but the instance is a bit more expensive (i.e m6i.xlarge to m6id.xlarge increases ~24% of instance price)

cons:

- the data is lost after the machine is stopped/started
- the size is limited, you can't choose/increase the size, it depends on the instance size
- the cost is ~24% higher than the instance without ephemeral disks


Examples of a requirement to replace m6i.xlarge with m6id.xlarge:

- the data stored on the EBS is not persistent, and you can consider losing it anytime
- the EBS allocated is used only to increase the performance, needing more than 3k IOPS or higher throughput, with lower capacity utilization (less than the ephemeral size 230GiB)
- the difference in instance price is $66.138, an equivalent of 661 GiB of gp2 or 826GiB of gp3. If the utilization of EBS is on the limit of the storage performance (throughput and/or IOPS) or the size was increased just to achieve more performance considering the total costs of VM (instance + storage).


## References <a name="review"></a>

- [KCS: Mounting separate disk for OpenShift 4 container storage](https://access.redhat.com/solutions/4952011)
- [AWS User Guide: Instance Type](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html)
