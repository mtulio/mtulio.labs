# Benachmark EC2 and EBS when building installer

> This document is in progress and provide the steps to run, the results is not part of this document.

Steps to setup the environment to use different instance types, ephemeral and not
to check the installer performance builds.

## Setup the Machine config to mount ephemeral disks

```bash
export DEVICE_NAME=nvme1n1

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

Wait the config rollout (MCP)

## Setup the node/machineset

Create the function to create the MachineSet for specific EC2. The
Node is tainted to prevent other workloads to run on it while running
the tests.

```bash
export AMI_ID=$(oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=worker -o json | jq -r .items[0].spec.providerSpec.value.ami.id)
export CLUSTER_ID="$(oc get infrastructure cluster \
    -o jsonpath='{.status.infrastructureName}')"

function create_machineset() {
    export instance_type=$1
    export disk_type=$2
cat <<EOF | envsubst | oc create -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
  name: ${CLUSTER_ID}-worker-${disk_type}
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-worker-${disk_type}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-worker-${disk_type}
    spec:
      metadata:
        labels:
          disk-type: ${disk_type}
          build-node: ''
      taints:
        - key: disk-type
          value: ${disk_type}
          effect: NoSchedule
      providerSpec:
        value:
          ami:
            id: ${AMI_ID}
          apiVersion: machine.openshift.io/v1beta1
          blockDevices:
          - ebs:
              encrypted: true
              iops: 0
              kmsKey:
                arn: ""
              volumeSize: 300
              volumeType: gp3
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: ${CLUSTER_ID}-worker-profile
          instanceType: ${instance_type}
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

}
```

## Test profiles

### Profile nodes c6i.4x

Launch the nodes with 16 cores

```bash
# compute optimized
create_machineset "c6id.4xlarge" "ephemeral"
create_machineset "c6i.4xlarge" "ebs"

# general pourpose
create_machineset "m6id.4xlarge" "ephemeral"
create_machineset "m6i.4xlarge" "ebs"

```




## Run builds

Create the build runner:

```bash
# install deps && clone installer repo && build && remove
function run_build() {

    local disk_type=$1

    if [[ -z $disk_type ]]; then echo "invalid disk_type. Expected: [ephemeral | ebs]"; exit 1; fi
    NODE=$(oc get node -l disk-type=$disk_type -o jsonpath='{.items[0].metadata.name}')
    RUN_ID="build_$(date +%Y%m%d%H%M%S)-$(uuidgen)-$disk_type"
    WKDIR=/host/var/lib/containers/storage/overlay/installer-$RUN_ID
    log_file=${RUN_ID}-${NODE}.log

    date > ${log_file}
    echo -en "$(date) \n [$RUN_ID] [$NODE]\n" | tee -a ${log_file}
    oc debug node/$NODE --image=quay.io/fedora/fedora:latest -- /bin/bash -c "
dnf install -y git golang zip util-linux >/dev/null && \
lsblk && \
df -h /host/var/lib/containers && \
git clone https://github.com/openshift/installer.git $WKDIR && \
cd $WKDIR && \
go env GOCACHE && \
export GOCACHE=$WKDIR/.cache && \
go env GOCACHE && \
time bash -x hack/build.sh && \
./bin/openshift-install version && \
cd / && rm -rf $WKDIR" | tee -a ${log_file}
    date | tee -a ${log_file}
}
```

- Run the build for each disk type

```bash
export JOBS_COUNT=4
# run on EBS nodes
for x in $(seq 1 $JOBS_COUNT); do sleep 5; run_build ebs & done

# run on ephemeral nodes
for x in $(seq 1 $JOBS_COUNT); do sleep 5; run_build ephemeral & done
```

## TODOs

- Limit number of cores to be used by Go

```bash
export JOBS_COUNT=6
export CPUCOUNT=$(grep -c ^processor /proc/cpuinfo)
export GOMAXPROCS=$(( ( $CPUCOUNT - 2) / $JOBS_COUNT ))
echo GOMAXPROCS=$GOMAXPROCS
```

- Run in a batch Job

```bash

function run_job() {
    local disk_type
    local parallelism
    disk_type=$1
    parallelism=$2
    cat <<EOF | envsubst | oc create -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: build-installer
spec:
  parallelism: $parallelism
  template:
    metadata:
      name: build-installer
    spec:
      nodeSelector:
        disk-type: $disk_type
      containers:
      - name: build
        image: quay.io/fedora/fedora:latest
        command: ["bash"]
        args:
        - -c
        - dnf install -y git golang zip util-linux >/dev/null && git clone https://github.com/openshift/installer.git && cd installer && time bash -x hack/build.sh && /bin/openshift-install version
        securityContext:
          allowPrivilegeEscalation: false
          runAsUser: 0
      restartPolicy: Never
EOF
}

run_job ephemeral 4
```