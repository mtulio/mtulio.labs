## Deploying High Scale OpenShift Cluster on AWS | etcd cluster offload from Control Plane | Machinery

<!---
State: WIP

Goals:

- Describe steps to create the MAPI objects: MachineConfig, MachineConfigPool and Machine

-->

### Create the etcd cluster machine objects

Steps:

- Create the MachineConfig for etcd Machines
  - Change kubelet to register with label `node-role.kubernetes.io/etcd`

- Create the MachineConfigPool matching the MachineConfig tag for `etcd` role

- Create the Machines
  - Choose the instance type appropriated for high load and throughput
  - Create a second disk for etcd
  - Create systemd unit files to mount etcd
  - Create two machines which will initially join to the existing cluster

#### MachineConfigPool for etcd cluster

> Note: the MCP could be created after MCs, but there's some events on MCO which did not found MCs. So I created this before all MCs

1. Create the MachineConfig manifest for SSH

```bash
oc get machineconfigpool master -o yaml > mcp-etcd.yaml
```

2. Edit the manifest and remove the attributes:

```yaml
metadata:
  creationTimestamp:
  generation:
  resourceVersion:
  uid:
spec:
  configuration:
status: *
```

3. On `mcp-etcd.yaml`, update to `etcd` role:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  labels:
    machineconfiguration.openshift.io/mco-built-in: ""
    operator.machineconfiguration.openshift.io/required-for-upgrade: ""
    pools.operator.machineconfiguration.openshift.io/etcd: ""
  name: etcd
spec:
  machineConfigSelector:
    matchLabels:
      machineconfiguration.openshift.io/role: etcd
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/etcd: ""
  paused: false

```

4. Create the MachineConfigPool:

```
$ oc create -f mcp-etcd.yaml

$ oc get mcp etcd
NAME   CONFIG                                           UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
etcd   rendered-etcd-c1baf9f5d09a1f8068a5171c7a907d35   True      False      False      0              0                   0                     0                      22s
```

<!-- 5. Make sure that the MachineConfig previously will be discovered and the rendered MachineConfig will be created

Check the MachineConfigPool configuration:
```
$ oc get mcp etcd  -o json |jq .spec.configuration
{
  "name": "rendered-etcd-0073a8d93ab97875b0b98e6dc9e82277",
  "source": [
    {
      "apiVersion": "machineconfiguration.openshift.io/v1",
      "kind": "MachineConfig",
      "name": "00-etcd"
    },
    {
      "apiVersion": "machineconfiguration.openshift.io/v1",
      "kind": "MachineConfig",
      "name": "01-etcd-container-runtime"
    },
    {
      "apiVersion": "machineconfiguration.openshift.io/v1",
      "kind": "MachineConfig",
      "name": "01-etcd-kubelet"
    },
    {
      "apiVersion": "machineconfiguration.openshift.io/v1",
      "kind": "MachineConfig",
      "name": "99-etcd-generated-registries"
    },
    {
      "apiVersion": "machineconfiguration.openshift.io/v1",
      "kind": "MachineConfig",
      "name": "99-etcd-ssh"
    }
  ]
}
```

Rendered MachineConfig for etcd:

```
$ oc get mc |grep ^rendered-etcd
rendered-etcd-0073a8d93ab97875b0b98e6dc9e82277     14a1ca2cb91ff7e0faf9146b21ba12cd6c652d22   3.2.0             4m53s
``` -->

#### MachineConfig base

1. Create the MachineConfig manifest for Kubelet

```bash
oc get machineconfig 00-master -o yaml > mc-00-etcd.yaml
```

2. Edit the manifest and remove the attributes:

```yaml
metadata:
  annotations:
  creationTimestamp:
  generation:
  resourceVersion:
  uid:
```

2. b: Remove the machine-config-daemon systemd units:

- machine-config-daemon-firstboot.service
- machine-config-daemon-pull.service
```diff
-       - contents: |
-          [Unit]
-          Description=Machine Config Daemon Firstboot
[...]
-        enabled: true
-        name: machine-config-daemon-firstboot.service
-
-      - contents: |
-          [Unit]
[...]
-        enabled: true
-        name: machine-config-daemon-pull.service
```

3. Update the attributes from `master` to `etcd`:

```yaml
metadata:
  labels:
    machineconfiguration.openshift.io/role: etcd
  name: 00-etcd
```

4. Create the MachineConfig:

```
$ oc create -f mc-00-etcd.yaml

$ oc get machineconfig 00-etcd
NAME      GENERATEDBYCONTROLLER   IGNITIONVERSION   AGE
00-etcd                           3.2.0             5s
```

#### MachineConfig for Contianer Runtime

1. Create the MachineConfig manifest for Kubelet

```bash
oc get machineconfig 01-master-container-runtime -o yaml > mc-01-etcd-container-runtime.yaml
```

2. Edit the manifest and remove the attributes:

```yaml
metadata:
  annotations:
  creationTimestamp:
  generation:
  resourceVersion:
  uid:
```

3. Update the attributes from `master` to `etcd`:

```yaml
metadata:
  labels:
    machineconfiguration.openshift.io/role: etcd
  name: 01-etcd-container-runtime
```

4. Create the MachineConfig:

```
$ oc create -f mc-01-etcd-container-runtime.yaml

$ oc get mc 01-etcd-container-runtime
NAME                        GENERATEDBYCONTROLLER   IGNITIONVERSION   AGE
01-etcd-container-runtime                           3.2.0             27s
```

#### MachineConfig for Kubelet

1. Create the MachineConfig manifest for Kubelet

```bash
oc get machineconfig 01-master-kubelet -o yaml > mc-01-etcd-kubelet.yaml
```

2. Edit the manifest and remove the attributes:

```yaml
metadata:
  annotations:
  creationTimestamp:
  generation:
  resourceVersion:
  uid:
```

3. On `mc-01-etcd-kubelet.yaml`, update to `etcd` role:

```yaml
metadata:
  labels:
    machineconfiguration.openshift.io/role: etcd
  name: 01-etcd-kubelet
```

4. On `mc-01-etcd-kubelet.yaml`, update `kubelet.service` unit:

From `spec.config.systemd.units[.name=="kubelet.service"].contents`, update the lines below to `node-role.kubernetes.io/etcd`:

`--node-labels`
```diff
- --node-labels=node-role.kubernetes.io/master,node.openshift.io/os_id=${ID} \
+ --node-labels=node-role.kubernetes.io/etcd,node.openshift.io/os_id=${ID} \
```

`--register-with-taints`
```diff
- --register-with-taints=node-role.kubernetes.io/master=:NoSchedule} \
+ --register-with-taints=node-role.kubernetes.io/etcd=:NoSchedule \
```

5. Create the MachineConfig:

```
$ oc create -f mc-01-etcd-kubelet.yaml

$ oc get machineconfig 01-etcd-kubelet
NAME              GENERATEDBYCONTROLLER   IGNITIONVERSION   AGE
01-etcd-kubelet                           3.2.0             14s
```

#### MachineConfig for Image registry

1. Create the MachineConfig manifest for ImageRegistry

```bash
oc get machineconfig 99-master-generated-registries -o yaml > mc-99-etcd-generated-registries.yaml
```

2. Edit the manifest and remove the attributes:

```yaml
metadata:
  annotations:
  creationTimestamp:
  generation:
  resourceVersion:
  uid:
```

3. On `mc-99-etcd-generated-registries.yaml`, update to `etcd` role:

```yaml
metadata:
  labels:
    machineconfiguration.openshift.io/role: etcd
  name: 99-etcd-generated-registries
```

4. Create the MachineConfig:

```
$ oc create -f mc-99-etcd-generated-registries.yaml

$ oc get machineconfig 99-etcd-generated-registries
NAME                           GENERATEDBYCONTROLLER   IGNITIONVERSION   AGE
99-etcd-generated-registries                           3.2.0             3s

```

#### MachineConfig for SSH

1. Create the MachineConfig manifest for SSH

```bash
oc get machineconfig 99-master-ssh -o yaml > mc-99-etcd-ssh.yaml
```

2. Edit the manifest and remove the attributes:

```yaml
metadata:
  annotations:
  creationTimestamp:
  generation:
  resourceVersion:
  uid:
```

3. On `mc-99-etcd-ssh.yaml`, update to `etcd` role:

```yaml
metadata:
  labels:
    machineconfiguration.openshift.io/role: etcd
  name: 99-etcd-ssh
```

4. Create the MachineConfig:

```
$ oc create -f mc-99-etcd-ssh.yaml

$ oc get mc 99-etcd-ssh
NAME          GENERATEDBYCONTROLLER   IGNITIONVERSION   AGE
99-etcd-ssh                           3.2.0             12s
```



#### Machine for etcd cluster

1. Create the machine manifest based on the current master

```
CLUSTER_ID="$(oc get infrastructure cluster -o jsonpath="{.status.infrastructureName}")"
oc get machine ${CLUSTER_ID}-master-0 -o yaml -n openshift-machine-api > machine-${CLUSTER_ID}-etcd-0.yaml
```

2. Edit the manifest and remove the attributes:

```yaml
metadata:
  creationTimestamp:
  generation:
  resourceVersion:
  uid:
spec:
  lifecycleHooks:
  metadata:
  providerID:
  spec.providerSpec.value:
    loadBalancers:
    metadata:
status: *
```

3. Update the following attributes renaming from `master` to `etcd` role:

Update:

- Labels
- User data
- Instance type

```yaml
metadata:
  labels:
    machine.openshift.io/cluster-api-machine-role: etcd
    machine.openshift.io/cluster-api-machine-type: etcd
    machine.openshift.io/instance-type: c5n.xlarge
  name: lab-x99n4-etcd-0
spec:
  providerSpec.value:
    userDataSecret: etcd-user-data
    instanceType: c5n.xlarge
    blockDevices:
      - ebs:
          encrypted: true
          iops: 0
          kmsKey:
            arn: ""
          volumeSize: 64
          volumeType: gp3
      - deviceName: /dev/xvdb
        ebs:
          encrypted: true
          iops: 0
          kmsKey:
            arn: ""
          volumeType: gp3
          volumeSize: 64

```

Notes: 

- The MachineConfigServer will serve the MachineConfigs rendered by MachineConfigPool defined inside `userDataSecret`
- The Security Groups and IAM roles can be adapted for a fine granted security - not cover in this article

4. Create the userDataSecret

Let's reuse again the master assets to create etcd user-data. To check the current master's user-data, run the following command:

```json
$ oc get secrets -n openshift-machine-api master-user-data -o json |jq -r .data.userData |base64 -d |jq .ignition.config.merge
[
  {
    "source": "https://api-int.lab.devcluster.openshift.com:22623/config/master"
  }
]
```

This is the endpoint of MachineConfigServer which should be poiting to `etcd` rendered MachineConfig, as a follow:
```
    "source": "https://api-int.lab.devcluster.openshift.com:22623/config/etcd"
```

Extract the master's userData secret:

```
oc get secrets -n openshift-machine-api master-user-data -o jsonpath="{.data}"  > etcd-userData-secret.json
```

Extract the userData payload:

```
jq -r .userData etcd-userData-secret.json |base64 -d > etcd-userData-raw.json
```

Change the MCS path to retrieve etcd MachineConfigPool:

```
jq -r '.ignition.config.merge[].source="https://api-int.lab.devcluster.openshift.com:22623/config/etcd"' etcd-userData-raw.json > etcd-userData-raw-with-etcd.json
```

Make sure the URL was updated:
```
$ jq -r .ignition.config.merge[].source etcd-userData-raw-with-etcd.json 
"https://api-int.lab.devcluster.openshift.com:22623/config/etcd"

```

Update the secret data
```bash
USER_DATA_ENC=$(cat etcd-userData-raw-with-etcd.json |base64 --wrap=0)
jq -r ".userData=\"${USER_DATA_ENC}\"" etcd-userData-secret.json > etcd-userData-secret-with-etcd.json
```

Make sure the data was updated:

```shell
$ jq -r .userData etcd-userData-secret-with-etcd.json |base64 -d |jq .ignition.config.merge
[
  {
    "source": "https://api-int.lab.devcluster.openshift.com:22623/config/etcd"
  }
]
```

Create the secret `etcd-user-data`

```bash
oc create secret generic etcd-user-data \
    --from-literal=userData=$(awk -v ORS= -v OFS= '{$1=$1}1' ./etcd-userData-raw-with-etcd.json) \
    --from-literal=disableTemplating=$(jq -r .disableTemplating etcd-userData-secret.json |base64 -d) \
    -n openshift-machine-api
```

Check if the endpoint is correct on the secret: 

```bash
oc get secrets -n openshift-machine-api etcd-user-data -o json |jq -r .data.userData |base64 -d |jq .ignition.config.merge
```

5. Create MachineConfig to mount the new block device on etcd path

Create the manifest:
```yaml
cat << EOF | oc create -n openshift-machine-api -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: etcd
  name: 00-etcd-disk
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      disks:
      - device: /dev/nvme1n1
        wipe_table: true
        partitions:
        - size_mib: 0
          label: etcd
      filesystems:
        - path: /var/lib/etcd
          device: /dev/disk/by-partlabel/etcd
          format: xfs
          wipe_filesystem: true
    systemd:
      units:
        - name: var-lib-etcd.mount
          enabled: true
          contents: |
            [Unit]
            Before=local-fs.target
            [Mount]
            Where=/var/lib/etcd
            What=/dev/disk/by-partlabel/etcd
            [Install]
            WantedBy=local-fs.target
EOF
```

Check it:

```
$ oc get mc 00-etcd-disk --show-labels
```

Create the Machine

```bash
oc create -f machine-${CLUSTER_ID}-etcd-0.yaml -n openshift-machine-api
```

Follow the Machine creation:

```
 $ oc get machines -l machine.openshift.io/cluster-api-machine-role=etcd -w -n openshift-machine-api
NAME               PHASE         TYPE         REGION      ZONE         AGE
lab-mh2g5-etcd-0   Provisioned   c5n.xlarge   us-east-1   us-east-1a   31s
lab-mh2g5-etcd-0   Running       c5n.xlarge   us-east-1   us-east-1a   3m32s
```

Check if the Node is Ready:

```bash
$ oc get node -l node-role.kubernetes.io/etcd= -w

NAME                          STATUS     ROLES   AGE   VERSION
ip-10-0-140-17.ec2.internal   NotReady   etcd    0s    v1.23.3+2e8bad7
ip-10-0-140-17.ec2.internal   Ready      etcd    20s   v1.23.3+2e8bad7
```

Create the second machine manifest:

```bash
sed 's/etcd-0/etcd-1/' machine-${CLUSTER_ID}-etcd-0.yaml > machine-${CLUSTER_ID}-etcd-1.yaml
```

Adjust the config:
- Zone ID

```bash
sed -i 's/us-east-1a/us-east-1b/g' machine-${CLUSTER_ID}-etcd-1.yaml
```

Create the machine:
```bash
oc create -f machine-${CLUSTER_ID}-etcd-1.yaml
```


ToDos pods should be removed:
- machine-config-daemon-755t9


[cluster-api-machine]: https://cluster-api.sigs.k8s.io/developer/architecture/controllers/machine.html
