# OCP on AWS - Using Instance Disks for containers' ephemeral storage

!!! warning "Research/Unfinished document"
    This document is a research document which is not completed.

This document incorporate researches with:
- OpenShift on Azure for CI clusters experiment mounting etcd in data disk
- CAP/Z deployment using installer FeatureGate on 4.17+
- CAPZ machine customization

### Create the Cluster on Azure with Control Plane Data Disks mounting etcd

- Use OpenShift installer version 4.17+.

```sh
$ openshift-install version
openshift-install 4.17.0-rc.0
```

- Create install-config:

```sh
# Load your environment where you declared PULL_SECRET_FILE, AZURE_DOMAIN, AZURE_BASE_RG...
source .env

CLUSTER_NAME=azddetcd-06
INSTALL_DIR=${PWD}/$CLUSTER_NAME
mkdir $CLUSTER_NAME

cat << EOF > ${INSTALL_DIR}/install-config.yaml 
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
featureSet: CustomNoUpgrade
featureGates:
- ClusterAPIInstall=true
publish: External
pullSecret: '$(cat $PULL_SECRET_FILE)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: $AZURE_DOMAIN
platform:
  azure:
    baseDomainResourceGroupName: $AZURE_BASE_RG
    cloudName: AzurePublicCloud
    outboundType: Loadbalancer
    region: eastus
EOF
./openshift-install create manifests --dir "${INSTALL_DIR}"
```

- Patch AzureCluster to enable failure domains 1-3

```sh
cat << EOF > ${INSTALL_DIR}/tmp_patch-02_azure-cluster.yaml
spec:
  failureDomains:
    "1":
      controlPlane: true
    "2":
      controlPlane: true
    "3":
      controlPlane: true
EOF
manifest=${INSTALL_DIR}/cluster-api/02_azure-cluster.yaml
echo "> Patching manifest $manifest"
yq4 ea --inplace '. as $item ireduce ({}; . * $item )' \
    ${manifest} ${INSTALL_DIR}/tmp_patch-02_azure-cluster.yaml
```

- Patch control plane to use data disks, decrease the instance/VM type, increase VM generation, and decrease 10x the OSDIsk size:
  > for setting the AZ ID to be able to create data disk LRS

```sh
# Patch each CAPZ AzureMachine object
for cpid in $(seq 0 2); do
  manifest=$(ls ${INSTALL_DIR}/cluster-api/machines/10_inframachine_*-master-$cpid.yaml)
  zone_id=$((cpid + 1))
  echo "Processing patch for control plane on zone ${zone_id}"
  cat << EOF > ${INSTALL_DIR}/tmp_patch-controlplane-$cpid.yaml
spec:
  failureDomain: "$zone_id"
  dataDisks:
    - nameSuffix: etcd
      diskSizeGB: 16
      lun: 0
      cachingType: None
      managedDisk:
        storageAccountType: PremiumV2_LRS
  osDisk:
    cachingType: ReadWrite
    diskSizeGB: 128
  vmSize: Standard_D4s_v5
EOF
  echo "> Patching manifest $manifest"
  yq4 ea --inplace '. as $item ireduce ({}; . * $item )' \
      $manifest ${INSTALL_DIR}/tmp_patch-controlplane-$cpid.yaml
done
```

- Create the MachineConfig manifest to mount etcd data disk:

```sh
MachineRole=master
MachineConfigName=master
DevicePath=/dev/disk/azure/scsi1/lun0
DeviceName=dev-disk-azure-scsi1-lun0
MountPointPath="/var/lib/etcd"
MountPointName="var-lib-etcd"
FileSystemType=xfs
ForceCreateFS=-f
SyncOldData=true
SyncTestDirExists="/var/lib/etcd/member"

cat <<EOF> ${INSTALL_DIR}/openshift/99_openshift-machineconfig_99-master-etcd-disk.yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: $MachineRole
  name: 99-master-etcd-disk
spec:
  config:
    ignition:
      version: 3.2.0
    systemd:
      units:
      - contents: |
          [Unit]
          Description=Make File System on $DevicePath
          DefaultDependencies=no
          BindsTo=$DeviceName.device
          After=$DeviceName.device var.mount
          Before=systemd-fsck@$DeviceName.service

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=-/bin/bash -c "/bin/rm -rf $MountPointPath/*"
          ExecStart=/usr/sbin/mkfs.$FileSystemType $ForceCreateFS $DevicePath
          TimeoutSec=0

          [Install]
          WantedBy=$MountPointName.mount
        enabled: true
        name: systemd-mkfs@$DeviceName.service
      - contents: |
          [Unit]
          Description=Mount $DevicePath to $MountPointPath
          Before=local-fs.target
          Requires=systemd-mkfs@$DeviceName.service
          After=systemd-mkfs@$DeviceName.service var.mount

          [Mount]
          What=$DevicePath
          Where=$MountPointPath
          Type=$FileSystemType
          Options=defaults,prjquota

          [Install]
          WantedBy=local-fs.target
        enabled: true
        name: $MountPointName.mount
# only when sync old data
      - contents: |
          [Unit]
          Description=Sync etcd data if new mount is empty
          DefaultDependencies=no
          After=$MountPointName.mount var.mount
          Before=crio.service

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecCondition=/usr/bin/test ! -d $SyncTestDirExists
          ExecStart=/usr/sbin/setenforce 0
          ExecStart=/bin/rsync -ar /sysroot/ostree/deploy/rhcos$MountPointPath/ $MountPointPath
          ExecStart=/usr/sbin/setenforce 1
          TimeoutSec=0

          [Install]
          WantedBy=multi-user.target graphical.target
        enabled: true
        name: sync-$MountPointName.service
      - contents: |
          [Unit]
          Description=Restore recursive SELinux security contexts
          DefaultDependencies=no
          After=$MountPointName.mount
          Before=crio.service

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=/sbin/restorecon -R $MountPointPath
          TimeoutSec=0

          [Install]
          WantedBy=multi-user.target graphical.target
        enabled: true
        name: restorecon-$MountPointName.service
EOF
```

- Create the cluster:

```sh
./openshift-install create cluster --dir $INSTALL_DIR --log-level=debug
```


Review cluster installation

- Install summary:

```sh
DEBUG Time elapsed per stage:                      
DEBUG        Infrastructure Pre-provisioning: 3s   
DEBUG    Network-infrastructure Provisioning: 4m14s 
DEBUG Post-network, pre-machine Provisioning: 19m25s 
DEBUG        Bootstrap Ignition Provisioning: 2s   
DEBUG                   Machine Provisioning: 11m45s 
DEBUG       Infrastructure Post-provisioning: 32s  
DEBUG                     Bootstrap Complete: 13m4s 
DEBUG                                    API: 4s   
DEBUG                      Bootstrap Destroy: 1m7s 
DEBUG            Cluster Operators Available: 12m23s 
DEBUG               Cluster Operators Stable: 48s  
INFO Time elapsed: 1h3m24s                   
```

- Version

```
$ openshift-install version
openshift-install 4.17.0-rc.0

$ oc get clusterversion
NAME      VERSION       AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.17.0-rc.0   True        False         4m16s   Cluster version is 4.17.0-rc.0

```

- Check if the etcd was mounted to a data disk for control plane nodes:

```sh
oc get clusterversion

for node in $(oc get nodes -l node-role.kubernetes.io/control-plane -o json | jq -r '.items[].metadata.name');
do
  echo "Checking node $node"
  oc debug node/$node --image=quay.io/fedora/fedora:latest -- chroot /host /bin/bash -c "echo -e \"\n>> \$HOSTNAME\"; df -h / /var/lib/etcd" 2>/dev/null
done
```

Expected result:
```text
NAME      VERSION       AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.17.0-rc.0   True        False         73m     Cluster version is 4.17.0-rc.0

Checking node azddetcd-06-rnxng-master-0

>> azddetcd-06-rnxng-master-0
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb4       128G   16G  113G  12% /
/dev/sda         16G  581M   16G   4% /var/lib/etcd
Checking node azddetcd-06-rnxng-master-1

>> azddetcd-06-rnxng-master-1
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda4       128G   21G  108G  16% /
/dev/sdb         16G  584M   16G   4% /var/lib/etcd
Checking node azddetcd-06-rnxng-master-2

>> azddetcd-06-rnxng-master-2
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda4       128G   23G  106G  18% /
/dev/sdb         16G  557M   16G   4% /var/lib/etcd
```

## Refereces

- https://docs.openshift.com/container-platform/4.16/installing/installing_azure/preparing-to-install-on-azure.html
- CAPZ support of DataDisks: https://github.com/kubernetes-sigs/cluster-api-provider-azure/blob/main/exp/api/v1beta1/azuremachinepool_types.go#L61C1-L64C1
