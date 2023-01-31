# Day-2 Guide to patch the ClusterNetwork MTU on running cluster with Local Zone workers

> The steps described in this guide were based on the [official documentation](https://docs.openshift.com/container-platform/4.12/networking/ovn_kubernetes_network_provider/rollback-to-openshift-sdn.html).

Steps to change the MTU of OVN in existing clusters installed with Local Zone workers.

Overview of the steps:
- Review the current configuration
- Pause the MachineConfigPools
- Patch the Cluster Network Operator to use the new MTU for OVN and the migration config
- Reboot the nodes
- Unpause the MCP
- Remove the migration
- Wait for the cluster operators to complete

## Pre-checks

Check the current MTU assigned to the OVN interface:

```bash
for NODE_NAME in $(oc get nodes  -o jsonpath='{.items[*].metadata.name}'); do
  echo -e "\n>> check interface $NODE_NAME";
  oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "ip ad show ovn-k8s-mp0 | grep mtu" 2>/dev/null;
done
```

Check the Network configuration:

```bash
oc get network.config/cluster -o yaml
```

Check the Network Operator configuration:

```bash
oc get Network.operator.openshift.io cluster -o yaml
```

When running with an invalid MTU to communicate with nodes in local zones, check if pulling images from the internal registry will fail (it's expected to fail with MTU higher than 1200):

> Replace the variables according to your environment (`KUBE_ADMIN_PASS`)

```bash
KUBE_ADMIN_PASS=$(cat auth/kubeadmin-password)
NODE_NAME=$(oc get nodes -l node-role.kubernetes.io/edge -o jsonpath={.items[0].metadata.name})
API_INT=$(oc get infrastructures cluster -o jsonpath={.status.apiServerInternalURI})

oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "\
oc login --insecure-skip-tls-verify -u kubeadmin -p ${KUBE_ADMIN_PASS} ${API_INT}; \
podman login -u kubeadmin -p \$(oc whoami -t) image-registry.openshift-image-registry.svc:5000; \
podman pull image-registry.openshift-image-registry.svc:5000/openshift/tests" 2>/dev/null;
```

## Change the MTU

Paused the existing MachineConfigPools:

```bash
oc patch MachineConfigPool master --type='merge' --patch \
  '{ "spec": { "paused": true } }'
  
oc patch MachineConfigPool worker --type='merge' --patch \
  '{ "spec":{ "paused" :true } }'
```

Patch the OVN to use the new MTU value:

```bash
oc patch Network.operator.openshift.io cluster --type=merge \
  --patch '{
    "spec":{
      "defaultNetwork":{
        "ovnKubernetesConfig":{
          "mtu": 1200
    }}}}'
```

Set the migration to using the new MTU in the cluster network (don't need to change the machine network, keep the same values - required field):

> **Note**: keet the machine MTU with the same value. It's required by migration.

```bash
oc patch Network.operator.openshift.io cluster --type='merge' \
  --patch '{
    "spec":{
      "migration":{
        "mtu":{
          "network":{"from":1200, "to":1200},
          "machine":{"from":8901, "to":8901}
        }}}}'
```

Rollout the multus:

```bash
oc -n openshift-multus rollout status daemonset/multus
```

Reboot the nodes:

> Adjust the "sleep" interval according to your time waiting for the new node to come up

```bash
#!/bin/bash

for NODE_NAME in $(oc get nodes  -o jsonpath='{.items[*].metadata.name}')
do
   echo ">> reboot node $NODE_NAME";
   oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "sudo shutdown -r -t 3";
   sleep 30;
done
```

Make sure all nodes have been rebooted:

```bash
for NODE_NAME in $(oc get nodes  -o jsonpath='{.items[*].metadata.name}'); do
  echo ">> get the uptime for node $NODE_NAME";
  oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "hostname; uptime" 2>/dev/null;
done
```

Unpause the MCPs:

```bash
oc patch MachineConfigPool master --type='merge' --patch \
  '{ "spec": { "paused": false } }'
  
oc patch MachineConfigPool worker --type='merge' --patch \
  '{ "spec": { "paused": false } }'
```

Check the node's machine config rollout/status:
 
```bash
oc describe node | egrep "hostname|machineconfig"

oc get machineconfig <config_name> -o yaml
```

Check the MTU value for the cluster network:

```bash
oc get network.config/cluster -o jsonpath='{.status.clusterNetworkMTU}{"\n"}'
```

Finalize and apply the changes by removing the migration entry:

```bash
$ oc patch Network.operator.openshift.io cluster --type='merge' \
  --patch '{ "spec": { "migration": null } }'
```

Wait for:

- All nodes have been updated by MCO rolls out wi the latest MCP
- Nodes are ready
- Operators are ready (available, not progressing nor degraded)

> NOTE: it could take several minutes

```bash
oc get pod -n openshift-machine-config-operator
oc get nodes
oc get co
```

Check if the nodes have been set this value on the overlay interface:

```bash
for NODE_NAME in $(oc get nodes  -o jsonpath='{.items[*].metadata.name}'); do
  echo -e "\n>> check interface $NODE_NAME";
  oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "ip ad show ovn-k8s-mp0 | grep mtu" 2>/dev/null;
done
```

The OVN interface must have the new MTU (`1200`), example output:

```
>> check interface ip-10-0-141-120.ec2.internal
5: ovn-k8s-mp0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1100 qdisc noqueue state UNKNOWN group default qlen 1000
(...)
```

## Testing pulling images from the internal registry

You must be able to pull images from the internal registry after the MTU change:

> Replace the variables according to your environment (`KUBE_ADMIN_PASS`)

```bash
KUBE_ADMIN_PASS=$(cat auth/kubeadmin-password)
NODE_NAME=$(oc get nodes -l node-role.kubernetes.io/edge -o jsonpath={.items[0].metadata.name})
API_INT=$(oc get infrastructures cluster -o jsonpath={.status.apiServerInternalURI})

oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "\
oc login --insecure-skip-tls-verify -u kubeadmin -p ${KUBE_ADMIN_PASS} ${API_INT}; \
podman login -u kubeadmin -p \$(oc whoami -t) image-registry.openshift-image-registry.svc:5000; \
podman pull image-registry.openshift-image-registry.svc:5000/openshift/tests" 2>/dev/null;
```
