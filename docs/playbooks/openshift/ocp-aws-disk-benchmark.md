# OCP on AWS - Using Instance Disks for ephemeral storage

This document describe the steps used to evaluate the performance of different disks on EC2 Instances in AWS. The disk types includes ephemeral (local disks) and block storages gp2, gp3, io1 and io2.

The tool used will be the FIO, and the intention is to stress the disk, using the baseline burst IO balance of gp2 to define the total time to run the tests. For example, if the EBS gp2 of 200GiB takes 20 minutes to consume all the burst balance for the stress tests, we will repeat the same time, increasing 5 minutes, for other disks which hasn't that limitation.

Table Of Contents:

- Create the environment
    - Create the MachineConfig
    - Create the MachineSet with Instance Type with ephemeral storage
    - Create the MachineSet with extra EBS with type gp2
    - Create the MachineSet with extra EBS with type gp3
    - Create the MachineSet with extra EBS with type io1
    - Create the MachineSet with extra EBS with type io2
- Run the Benchmark
- Analyse the results
- Review

## Create the environment <a name="create-env"></a>

### Create MachineConfig <a name="create-env-mc"></a>

Steps to create the MachineConfig to mount the extra device.

> TODO

### Create MachineSet for ephemeral disk Instance <a name="create-env-mset-ephemeral"></a>

> TODO

```bash
export INSTANCE_TYPE="m6id.xlarge"
create_machineset
```

### Create MachineSet for gp2 disk Instance <a name="create-env-mset-gp2"></a>

> TODO

```bash
export INSTANCE_TYPE="m6i.xlarge"
export EXTRA_BLOCK_DEVICES="
      - deviceName: /dev/xvdb
        ebs:
          volumeType: gp2
          volumeSize: 230
"
create_machineset
```

### Create MachineSet <a name="create-env-mset-gp3"></a>

> TODO

```bash
export INSTANCE_TYPE="m6i.xlarge"
export EXTRA_BLOCK_DEVICES="
      - deviceName: /dev/xvdb
        ebs:
          volumeType: gp3
          volumeSize: 230
"
create_machineset
```

### Create MachineSet <a name="create-env-mset-io1"></a>

> TODO

```bash
export INSTANCE_TYPE="m6i.xlarge"
export EXTRA_BLOCK_DEVICES="
      - deviceName: /dev/xvdb
        ebs:
          volumeType: io1
          volumeSize: 230
          iops: 3000
"
create_machineset
```

### Create MachineSet <a name="create-env-mset-io2"></a>

> TODO

```bash
export INSTANCE_TYPE="m6i.xlarge"
export EXTRA_BLOCK_DEVICES="
      - deviceName: /dev/xvdb
        ebs:
          volumeType: io2
          volumeSize: 230
          iops: 3000
"
create_machineset
```

## Run the benchmark <a name="run-benchmark"></a>

> TODO

## Analyse the Results <a name="results"></a>

> TODO

## Review <a name="review"></a>

> TODO

### Results

### Costs

## References <a name="references"></a>

> TODO



___

### Create the MachineConfig

The MachineConfig should create the systemd units to:

- create the filesystem on the new device
- mount the device on the path `/var/lib/containers`
- restore the SELinux context

Steps:

- Export the device path presented to your instance for ephemeral device (in general `/dev/nvme1n1`):

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

### Create the MachineSet

The second steps is to create the MachineSet to launch the instance with ephemeral disks available. You should choose one from AWS offering. In general instances with ephemeral disks finishes the type part with the letter "`d`", for example the instance of the Compute optimized family (`C`) in the 6th-generation of Intel processors (`i`) with ephemeral storage, will be the type `C6id`.

In my case I will use the instance type and size `c6id.xlarge` which provides a ephemeral storage of `237 GB NVMe SSD`.

```bash
export INSTANCE_TYPE=c6id.xlarge
```

Get the CLUSTER_ID:

```bash
export CLUSTER_ID="$(oc get infrastructure cluster \
    -o jsonpath='{.status.infrastructureName}')"
```

Create the MachineSet:
```bash
create_machineset() {
  # Required environment variables:
  ## DISK_TYPE         : Used to create the node label and name suffix of MachineSet
  ## CLUSTER_ID        : Can get from infrastructure object
  ## INSTANCE_TYPE     : InstanceType
  # Optional environment variables:
  ## EXTRA_EBS_DEVICE  : New EBS definition to be created  (default: '')
  ## AWS_REGION        : AWS Region (default: us-east-1)
  ## AWS_ZONE          : Availability Zone part of AWS_REGION  (default: us-east-1a)
  cat <<EOF | envsubst | oc create -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
  name: ${CLUSTER_ID}-worker-${DISK_TYPE}
  namespace: openshift-machine-api
spec:
  replicas: 0
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-worker-${DISK_TYPE}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-worker-${DISK_TYPE}
    spec:
      metadata:
        labels:
          disk_type: "${DISK_TYPE}"
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
${EXTRA_BLOCK_DEVICES:-}
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: ${CLUSTER_ID}-worker-profile
          instanceType: ${INSTANCE_TYPE}
          kind: AWSMachineProviderConfig
          placement:
            availabilityZone: ${AWS_ZONE:-us-east-1a}
            region:  ${AWS_REGION:-us-east-1}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - ${CLUSTER_ID}-worker-sg
          subnet:
            filters:
            - name: tag:Name
              values:
              - ${CLUSTER_ID}-private-${AWS_ZONE:-us-east-1a}
          tags:
          - name: kubernetes.io/cluster/${CLUSTER_ID}
            value: owned
          userDataSecret:
            name: worker-user-data
EOF
}
```

Wait for the node be created

```bash
oc get node -l disk_type=ephemeral -w
```

Make sure the device has been mounted correctly to the mount path `/var/lib/containers`

```bash
oc debug node/$(oc get nodes -l disk_type=${disk_type} -o jsonpath='{.items[0].metadata.name}') -- chroot /host /bin/bash -c "df -h /var/lib/containers"
```

## Review


### Running fio-etcd

We will use the quick FIO test using the tool that is commonly used to evaluate the disk for etcd.

> Used on OpenShift for etcd](https://access.redhat.com/articles/6271341) quick tests

```bash
export label_disk=ephemeral
export node_name=$(oc get nodes -l disk_type=${label_disk} -o jsonpath='{.items[0].metadata.name}')
export base_path="/var/lib/containers/_benchmark_fio"
```

Run quick FIO test (used for etcd):

- Running on ephemeral device

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

### Running stress test with FIO

Run stress FIO test:

> FIO parameters recommened on [AWS Doc](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/benchmark_procedures.html) for General Pourpose disks (GP)

```bash
oc debug node/${node_name} -- chroot /host /bin/bash -c \
    "echo \"[0] <=> \$(hostname) <=> \$(date) <=> \$(uptime) \"; \
    lsblk; \
    mkdir -p ${base_path}; \
    for offset in {1..2} ; do \
        echo \"Running [\$offset]\"; \
        podman run --rm \
            -v ${base_path}:/benchmark:Z \
            ljishen/fio \
                --ioengine=psync \
                --rw=randwrite \
                --direct=1 \
                --bs=16k \
                --size=1G \
                --numjobs=5 \
                --time_based \
                --runtime=60 \
                --group_reporting \
                --norandommap \
                --directory=/benchmark \
                --name=data_${disk_type}_\${offset} \
                --output-format=json \
                --output=/benchmark/result_\$(hostname)-${disk_type}-\${offset}.json ;\
        sleep 10; \
        rm -f ${base_path}/data_${disk_type}_* ||true ; \
        echo \"[\$offset] <=> \$(hostname) <=> \$(date) <=> \$(uptime) \"; \
    done; \
    tar cfz /tmp/benchmark-${disk_type}.tar.gz ${base_path}*/*.json" \
    2>/dev/null | tee -a ${log_stdout}

oc debug node/${node_name} -- chroot /host /bin/bash -c \
    "cat /tmp/benchmark-${disk_type}.tar.gz" \
    2>/dev/null > ./results-fio_stress-${disk_type}-${node_name}.tar.gz
```

## References

- [KCS: Mounting separate disk for OpenShift 4 container storage](https://access.redhat.com/solutions/4952011)
- [AWS User Guide: Instance Type](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html)
