# OCP on AWS - Using Instance Disks for containers' ephemeral storage

!!! warning "Unfinished document"
    This document is still in progress and requires adjustments and source code modifications not
    fully documented in the steps.


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

- Export the device path presented to your instance for the ephemeral device (in general `/dev/sdb1`):

```bash
export DEVICE_NAME=sdb1
```

- Create the MachineConfig manifest

```bash
INSTALL_DIR=$HOME/.ansible/okd-installer/clusters/azure-a414rc2e
mkdir $INSTALL_DIR

BIN_INSTALL=$HOME/.ansible/okd-installer/bin/openshift-install-linux-4.14.0-rc.2

cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: azure-a414rc2e
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: splat.azure.devcluster.openshift.com
platform:
  azure: {
    "baseDomainResourceGroupName": "os4-common",
    "cloudName": "AzurePublicCloud",
    "outboundType": "Loadbalancer",
    "region": "eastus"
}
EOF

$BIN_INSTALL create manifests --dir $INSTALL_DIR


MANIFEST_PATH=$INSTALL_DIR/openshift/98-var-lib-containers-master.yaml
export DEVICE_NAME=sdb1
cat <<EOF | envsubst > $MANIFEST_PATH
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
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
          ExecStart=/usr/sbin/mkfs.xfs -f /dev/${DEVICE_NAME}
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

$BIN_INSTALL create cluster --dir $INSTALL_DIR

```


### Schenario 2 (smaller/tmp storage to /var/lib/containers)

```bash
export DEVICE_NAME=sdb1
CLUSTER_NAME=azure-a414rc2es
INSTALL_DIR=$HOME/.ansible/okd-installer/clusters/$CLUSTER_NAME
mkdir $INSTALL_DIR

BIN_INSTALL=$HOME/.ansible/okd-installer/bin/openshift-install-linux-4.14.0-rc.2

#> TODO create support to osDIsk PremiumV2_LRS

cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
controlPlane:
  platform:
    azure:
      osDisk:
        diskSizeGB: 128
        diskType: Premium_LRS
      type: Standard_D4ds_v5
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: splat.azure.devcluster.openshift.com
platform:
  azure: {
    "baseDomainResourceGroupName": "os4-common",
    "cloudName": "AzurePublicCloud",
    "outboundType": "Loadbalancer",
    "region": "eastus"
}
EOF

$BIN_INSTALL create manifests --dir $INSTALL_DIR


MANIFEST_PATH=$INSTALL_DIR/openshift/98-var-lib-containers-master.yaml
export DEVICE_NAME=sdb1
cat <<EOF | envsubst > $MANIFEST_PATH
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
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
          ExecStart=/usr/sbin/mkfs.xfs -f /dev/${DEVICE_NAME}
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

$BIN_INSTALL create cluster --dir $INSTALL_DIR

sleep 120;
worker=$(oc get nodes -l node-role.kubernetes.io/worker='' -o jsonpath='{.items[0].metadata.name}')
oc label node $worker node-role.kubernetes.io/tests=""
oc adm taint node $worker node-role.kubernetes.io/tests="":NoSchedule


sleep 300 && ~/opct/bin/opct-v0.5.0-alpha.1 run -w && ~/opct/bin/opct-v0.5.0-alpha.1 retrieve
```

### Schenario 2 (smaller/tmp storage to /var/lib/etcd)



```bash
CLUSTER_NAME=azure-a414rc2etcd2
INSTALL_DIR=$HOME/.ansible/okd-installer/clusters/$CLUSTER_NAME
mkdir $INSTALL_DIR

BIN_INSTALL=$HOME/.ansible/okd-installer/bin/openshift-install-linux-4.14.0-rc.2

#> TODO create support to osDIsk PremiumV2_LRS

cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
controlPlane:
  platform:
    azure:
      osDisk:
        diskSizeGB: 128
        diskType: Premium_LRS
      type: Standard_D4ds_v5
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: splat.azure.devcluster.openshift.com
platform:
  azure: {
    "baseDomainResourceGroupName": "os4-common",
    "cloudName": "AzurePublicCloud",
    "outboundType": "Loadbalancer",
    "region": "eastus"
}
EOF

$BIN_INSTALL create manifests --dir $INSTALL_DIR


MANIFEST_PATH=$INSTALL_DIR/openshift/98-var-lib-containers-master.yaml
export DEVICE_PATH=/dev/disk/azure/resource-part1
export DEVICE_NAME=dev-disk-azure-resource
#export MOUNT_POINT_VARLIB=etcd
export MOUNT_POINT_NAME=var-lib-etcd
export MOUNT_POINT_PATH=/var/lib/etcd
export MACHINE_CONFIG_ROLE=master
cat <<EOF | envsubst > $MANIFEST_PATH
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: ${MACHINE_CONFIG_ROLE}
  name: 98-mount-${MOUNT_POINT_NAME}
spec:
  config:
    ignition:
      version: 3.1.0
    systemd:
      units:
      - contents: |
          [Unit]
          Description=Make File System on ${DEVICE_PATH}
          DefaultDependencies=no
          BindsTo=${DEVICE_NAME}.device
          After=${DEVICE_NAME}.device var.mount
          Before=systemd-fsck@${DEVICE_NAME}.service

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=-/bin/bash -c "/bin/rm -rf ${MOUNT_POINT_PATH:-/tmp/none}/*"
          ExecStart=/usr/sbin/mkfs.xfs -f ${DEVICE_PATH}
          TimeoutSec=0

          [Install]
          WantedBy=${MOUNT_POINT_NAME}.mount
        enabled: true
        name: systemd-mkfs@${DEVICE_NAME}.service
      - contents: |
          [Unit]
          Description=Mount ${DEVICE_PATH} to ${MOUNT_POINT_PATH}
          Before=local-fs.target
          Requires=systemd-mkfs@${DEVICE_NAME}.service
          After=systemd-mkfs@${DEVICE_NAME}.service

          [Mount]
          What=${DEVICE_PATH}
          Where=${MOUNT_POINT_PATH}
          Type=xfs
          Options=defaults,prjquota

          [Install]
          WantedBy=local-fs.target
        enabled: true
        name: ${MOUNT_POINT_NAME}.mount
      - contents: |
          [Unit]
          Description=Restore recursive SELinux security contexts
          DefaultDependencies=no
          After=${MOUNT_POINT_NAME}.mount
          Before=crio.service

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=/sbin/restorecon -R ${MOUNT_POINT_PATH}
          TimeoutSec=0

          [Install]
          WantedBy=multi-user.target graphical.target
        enabled: true
        name: restorecon-${MOUNT_POINT_NAME}.service
EOF

$BIN_INSTALL create cluster --dir $INSTALL_DIR

# ansible-runner
export KUBECONFIG=$INSTALL_DIR/auth/kubeconfig
ansible-playbook opct-runner/opct-run-tool-preflight.yaml -e cluster_name=$CLUSTER_NAME

# remove emptyDir
oc patch configs.imageregistry.operator.openshift.io cluster --type delete --patch '{"spec":{"storage":{"emptyDir":{}}}}'


sleep 300;
# worker=$(oc get nodes -l node-role.kubernetes.io/worker='' -o jsonpath='{.items[0].metadata.name}')
# oc label node $worker node-role.kubernetes.io/tests=""
# oc adm taint node $worker node-role.kubernetes.io/tests="":NoSchedule


~/opct/bin/opct-v0.5.0-alpha.1 run -w && ~/opct/bin/opct-v0.5.0-alpha.1 retrieve
```

Result:

- faster than ever etcd
- resilient to disk failures


### Scenario 3: add data disk to etcd

It requires change in installer to support a install-config like this:

```bash

#> TODO create support to osDIsk PremiumV2_LRS

# required changes

CLUSTER_NAME=azetcd11
INSTALL_DIR=/tmp/azure-${CLUSTER_NAME}
mkdir $INSTALL_DIR
cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
controlPlane:
  platform:
    azure:
      osDisk:
        diskSizeGB: 128
        diskType: Premium_LRS
      type: Standard_D4ds_v5
      dataDisks:
      - nameSuffix: etcd
        diskSizeGB: 16
        managedDisk:
          storageAccountType: PremiumV2_LRS
        lun: 0
        CachingType: None
  mountDevices:
  - name: ephemeral
    devicePath: /dev/disk/azure/resource-part1
    mountPath: /var/lib/containers
  - name: etcd
    devicePath: /dev/disk/azure/scsi1/lun0
    mountPath: /var/lib/etcd
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: splat.azure.devcluster.openshift.com
platform:
  azure: {
    "baseDomainResourceGroupName": "os4-common",
    "cloudName": "AzurePublicCloud",
    "outboundType": "Loadbalancer",
    "region": "eastus"
}
EOF

export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.14.0-rc.2-x86_64"

./bin/openshift-install create manifests --dir $INSTALL_DIR

./bin/openshift-install create cluster --dir $INSTALL_DIR
```

- Sample MachineConfig

```bash

export DEVICE_PATH=/dev/disk/azure/scsi1/lun0
export DEVICE_NAME=dev-disk-azure-scsi1-lun0
#export MOUNT_POINT_VARLIB=etcd
export MOUNT_POINT_NAME=var-lib-etcd
export MOUNT_POINT_PATH=/var/lib/etcd
export MACHINE_CONFIG_ROLE=master
MANIFEST_PATH=$INSTALL_DIR/openshift/98-${DEVICE_NAME}-master.yaml
# LUN
cat <<EOF | envsubst > $MANIFEST_PATH
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: ${MACHINE_CONFIG_ROLE}
  name: 98-mount-${MOUNT_POINT_NAME}
spec:
  config:
    ignition:
      version: 3.1.0
    systemd:
      units:
      - contents: |
          [Unit]
          Description=Make File System on ${DEVICE_PATH}
          DefaultDependencies=no
          BindsTo=${DEVICE_NAME}.device
          After=${DEVICE_NAME}.device var.mount
          Before=systemd-fsck@${DEVICE_NAME}.service

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=-/bin/bash -c "/bin/rm -rf ${MOUNT_POINT_PATH:-/tmp/none}/*"
          ExecStart=/usr/sbin/mkfs.xfs -f ${DEVICE_PATH}
          TimeoutSec=0

          [Install]
          WantedBy=${MOUNT_POINT_NAME}.mount
        enabled: true
        name: systemd-mkfs@${DEVICE_NAME}.service
      - contents: |
          [Unit]
          Description=Mount ${DEVICE_PATH} to ${MOUNT_POINT_PATH}
          Before=local-fs.target
          Requires=systemd-mkfs@${DEVICE_NAME}.service
          After=systemd-mkfs@${DEVICE_NAME}.service

          [Mount]
          What=${DEVICE_PATH}
          Where=${MOUNT_POINT_PATH}
          Type=xfs
          Options=defaults,prjquota

          [Install]
          WantedBy=local-fs.target
        enabled: true
        name: ${MOUNT_POINT_NAME}.mount
      - contents: |
          [Unit]
          Description=Restore recursive SELinux security contexts
          DefaultDependencies=no
          After=${MOUNT_POINT_NAME}.mount
          Before=crio.service

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=/sbin/restorecon -R ${MOUNT_POINT_PATH}
          TimeoutSec=0

          [Install]
          WantedBy=multi-user.target graphical.target
        enabled: true
        name: restorecon-${MOUNT_POINT_NAME}.service
EOF
```


References:

- https://etcd.io/docs/v3.3/op-guide/hardware/
- https://zendesk.engineering/etcd-getting-30-more-write-s-318bcdbf7774
- https://github.com/kubernetes-sigs/cluster-api-provider-azure/issues/448

- https://www.redhat.com/en/blog/working-container-storage-library-and-tools-red-hat-enterprise-linux
>  you should set up storage in any manner that best fits your needs using standard Linux commands, but we recommend that you mount a large device on /var/lib/containers.


| Role | Name | Price(useast) | vCPUs | CPU Architecture | Memory | Proccessor | OS disk size | Temp Disk | Max Disks | Sup Premium | Combined IOPS | Uncached IOPS | TP Write | TP Read |
| - | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Prod(cur) | [Standard_D8s_v3](https://azureprice.net/vm/Standard_D8s_v3) | 280.32 | 8 | x64 | 32 GiB | Intel(R) Xeon(R) CPU E5-2673 v3 @ 2.40GHz | 1023 GiB | 64GiB | 16 | yes | 16k | 12.8k | 128 MiB/s | 128 MiB/s |
| Prod(new) | [Standard_D4s_v5](https://azureprice.net/vm/Standard_D4s_v5) | 140.16 | 4 | x64 | 16 GiB | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz | 1023 GiB | N/A | 8 | yes | 38.5k | 6.4k | 250MiB/s | 250MiB/s |


## Use Cases / Samples Install-config

### Use Case: Default IPI (Prod)

```bash

CLUSTER_NAME=az-a412rc2etcd-ded02
INSTANCE_TYPE=Standard_D4s_v5
INSTALL_DIR=/tmp/azure-${CLUSTER_NAME}
mkdir $INSTALL_DIR
cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
controlPlane:
  platform:
    azure:
      type: "${INSTANCE_TYPE}"
      osDisk:
        diskSizeGB: 120
        diskType: PremiumV2_LRS
      dataDisks:
      - nameSuffix: etcd
        diskSizeGB: 16
        managedDisk:
          storageAccountType: PremiumV2_LRS
        lun: 0
        CachingType: None
  mountDevices:
  - name: etcd
    devicePath: /dev/disk/azure/scsi1/lun0
    mountPath: /var/lib/etcd
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: splat.azure.devcluster.openshift.com
platform:
  azure: {
    "baseDomainResourceGroupName": "os4-common",
    "cloudName": "AzurePublicCloud",
    "outboundType": "Loadbalancer",
    "region": "eastus"
}
EOF

export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.14.0-rc.2-x86_64"

./bin/openshift-install create manifests --dir $INSTALL_DIR

./bin/openshift-install create cluster --dir $INSTALL_DIR
```


- Default:

```bash
CLUSTER_NAME=az-a412rc2etcd
INSTALL_DIR=/tmp/azure-${CLUSTER_NAME}
mkdir $INSTALL_DIR
cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: splat.azure.devcluster.openshift.com
platform:
  azure: {
    "baseDomainResourceGroupName": "os4-common",
    "cloudName": "AzurePublicCloud",
    "outboundType": "Loadbalancer",
    "region": "eastus"
}
EOF
./bin/openshift-install create manifests --dir $INSTALL_DIR
./bin/openshift-install create cluster --dir $INSTALL_DIR

```

### Flag OPENSHIFT_INSTALL_EXPERIMENTAL_ETCD_DEDICATED

- dedicated etcd:

```bash

export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.14.0-rc.2-x86_64"
export OPENSHIFT_INSTALL_EXPERIMENTAL_ETCD_DEDICATED=true

CLUSTER_NAME=az-a412rc2etcd-ded03
INSTALL_DIR=/tmp/azure-${CLUSTER_NAME}
mkdir $INSTALL_DIR
cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: splat.azure.devcluster.openshift.com
platform:
  azure:
    baseDomainResourceGroupName: os4-common
    cloudName: AzurePublicCloud
    outboundType: Loadbalancer
    region: eastus
EOF

./bin/openshift-install create manifests --dir $INSTALL_DIR

./bin/openshift-install create cluster --dir $INSTALL_DIR
```

- default:


```bash
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.14.0-rc.2-x86_64"
unset OPENSHIFT_INSTALL_EXPERIMENTAL_ETCD_DEDICATED

CLUSTER_NAME=az-a412rc2-03ipi
INSTALL_DIR=/tmp/azure-${CLUSTER_NAME}
mkdir $INSTALL_DIR
cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: splat.azure.devcluster.openshift.com
platform:
  azure:
    baseDomainResourceGroupName: os4-common
    cloudName: AzurePublicCloud
    outboundType: Loadbalancer
    region: eastus
EOF

./bin/openshift-install create manifests --dir $INSTALL_DIR

./bin/openshift-install create cluster --dir $INSTALL_DIR
```

### Use Case: Dev Cluster

- smaller instance type
- ephemeral to /var/lib/containers and smaller lun for etcd

```bash
CLUSTER_NAME=az-lun-eph-02
DOMAIN=splat.azure.devcluster.openshift.com
# may not work:
INSTANCE_TYPE=Standard_D4ds_v5
INSTALL_DIR=/tmp/azure-${CLUSTER_NAME}
mkdir $INSTALL_DIR
cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
baseDomain: $DOMAIN
controlPlane:
  platform:
    azure:
      osDisk:
        diskSizeGB: 64
        diskType: Premium_LRS
      type: Standard_D4ds_v5
      dataDisks:
      - nameSuffix: etcd
        diskSizeGB: 8
        managedDisk:
          storageAccountType: PremiumV2_LRS
        lun: 0
        CachingType: None
  mountDevices:
  - name: ephemeral
    devicePath: /dev/disk/azure/resource-part1
    mountPath: /var/lib/containers
  - name: etcd
    devicePath: /dev/disk/azure/scsi1/lun0
    mountPath: /var/lib/etcd
platform:
  azure:
    baseDomainResourceGroupName: os4-common
    cloudName: AzurePublicCloud
    outboundType: Loadbalancer
    region: eastus
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
EOF

export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.14.0-rc.2-x86_64"

./bin/openshift-install create manifests --dir $INSTALL_DIR

./bin/openshift-install create cluster --dir $INSTALL_DIR
```

## Condidential

```bash
CLUSTER_NAME=az-conf-01
DOMAIN=splat.azure.devcluster.openshift.com
INSTANCE_TYPE=Standard_DC8ads_v5
INSTALL_DIR=/tmp/azure-${CLUSTER_NAME}
mkdir $INSTALL_DIR
cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
baseDomain: $DOMAIN
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: 
    azure:
      type: $INSTANCE_TYPE
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    azure:
      type: $INSTANCE_TYPE
      dataDisks:
      - nameSuffix: etcd
        diskSizeGB: 16
        managedDisk:
          storageAccountType: PremiumV2_LRS
        lun: 0
        CachingType: None
  mountDevices:
  - name: etcd
    devicePath: /dev/disk/azure/scsi1/lun0
    mountPath: /var/lib/etcd
platform:
  azure:
    baseDomainResourceGroupName: os4-common
    cloudName: AzurePublicCloud
    outboundType: Loadbalancer
    region: eastus
    defaultMachinePlatform:
      settings:
        securityType: ConfidentialVM
        confidentialVM:
          uefiSettings:
            secureBoot: Enabled
            virtualizedTrustedPlatformModule: Enabled
      osDisk:
        diskSizeGB: 128
        securityProfile:
          securityEncryptionType: VMGuestStateOnly
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
EOF

export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.14.0-rc.2-x86_64"

./bin/openshift-install create manifests --dir $INSTALL_DIR

./bin/openshift-install create cluster --dir $INSTALL_DIR
```


### Use Case: Prod distributed disks


```bash

#> TODO create support to osDIsk PremiumV2_LRS

# required changes

CLUSTER_NAME=azetcd11
INSTALL_DIR=/tmp/azure-${CLUSTER_NAME}
mkdir $INSTALL_DIR
cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
controlPlane:
  platform:
    azure:
      osDisk:
        diskSizeGB: 64
        diskType: PremiumV2_LRS
      type: Standard_D4ds_v5
      dataDisks:
      - nameSuffix: etcd
        diskSizeGB: 32
        managedDisk:
          storageAccountType: PremiumV2_LRS
        lun: 0
        CachingType: None
      - nameSuffix: etcd
        diskSizeGB: 64
        managedDisk:
          storageAccountType: PremiumV2_LRS
        lun: 1
        CachingType: None
  mountDevices:
  - name: etcd
    devicePath: /dev/disk/azure/scsi1/lun0
    mountPath: /var/lib/etcd
  - name: ephemeral
    devicePath: /dev/disk/azure/scsi1/lun1
    mountPath: /var/lib/containers
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: splat.azure.devcluster.openshift.com
platform:
  azure: {
    "baseDomainResourceGroupName": "os4-common",
    "cloudName": "AzurePublicCloud",
    "outboundType": "Loadbalancer",
    "region": "eastus"
}
EOF

export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.14.0-rc.2-x86_64"

./bin/openshift-install create manifests --dir $INSTALL_DIR
./bin/openshift-install create cluster --dir $INSTALL_DIR
```

