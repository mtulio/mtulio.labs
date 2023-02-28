# Day-2 Guide to patch the ClusterNetwork MTU on running cluster with Local Zone workers

> The steps described in this guide were based on the [official documentation](https://docs.openshift.com/container-platform/4.12/networking/changing-cluster-network-mtu.html#nw-cluster-mtu-change_changing-cluster-network-mtu).

Steps to change the MTU of OVN in existing clusters installed with Local Zone workers.

Overview of the steps:
- Review the current configuration
- Patch the Cluster Network Operator to use the new MTU for OVN and the migration config
- Remove the migration, and set the default MTU
- Wait for the cluster operators to complete

## Pre-checks

Overall Checks:

- Expected all Cluster Operators ready (AVAILABLE=True, PROGRESSING && DEGRADED == False)
- Expected all MCPs ready (UPDATED=True, UPDATING=False, DEGRADED=False)
- Expected all nodes STATUS=Ready
- Expected the `.status.clusterNetworkMTU` with non targeted MTU value in `network.config/cluster`
- Expected no migrations `.status.migrations == nil`
- Expected the mtu applied on the interface `ovn-k8s-mp0` the same of `.status.clusterNetworkMTU`

```bash
oc get co
oc get mcp
oc get nodes
oc get network.config/cluster -o yaml
oc get Network.operator.openshift.io cluster -o yaml
oc get Network.operator.openshift.io cluster -o jsonpath='{.spec.defaultNetwork.ovnKubernetesConfig.mtu}{"\n"}'
oc get network.config/cluster -o jsonpath='{.status.clusterNetworkMTU}{"\n"}'

for NODE_NAME in $(oc get nodes  -o jsonpath='{.items[*].metadata.name}'); do
  echo -e "\n>> check interface $NODE_NAME";
  oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "ip ad show ovn-k8s-mp0 | grep mtu" 2>/dev/null;
done
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


Patch the OVN to use the new MTU value:

```bash
target_mtu=1200
oc patch Network.operator.openshift.io cluster --type=merge \
  --patch "{
    \"spec\":{
      \"migration\":{
        \"mtu\":{
          \"network\":{
            \"from\":$(oc get network.config.openshift.io/cluster --output=jsonpath={.status.clusterNetworkMTU}),
            \"to\":${target_mtu}
          },
          \"machine\":{\"to\":9001}
        }}}}"
```

Wait for:

- All the MachineConfigPools have been updated
- All nodes are Ready
- All ClusterOperators are ready (available, not progressing nor degraded)
- All nodes' overlay interface must have the new MTU

> NOTE: it could take several minutes

```bash
oc get network.config/cluster -o jsonpath='{.status.clusterNetworkMTU}{"\n"}'
oc get mcp
oc get nodes
oc get co
```

Finalize and apply the changes by removing the migration entry, setting the MTU into the default configuration:

```bash
target_mtu=1200
oc patch network.operator.openshift.io/cluster --type=merge \
  --patch "{
    \"spec\":{
      \"migration\":null,
      \"defaultNetwork\":{
        \"ovnKubernetesConfig\":{\"mtu\":${target_mtu}}
        }}}"
```

Wait for MCP rollout one more time.

## Review

Check if the nodes keep with the MTU set previously:

```bash
for NODE_NAME in $(oc get nodes  -o jsonpath='{.items[*].metadata.name}'); do
  echo -e "\n>> check interface $NODE_NAME";
  oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "ip ad show ovn-k8s-mp0 | grep mtu" 2>/dev/null;
done
```


### Testing pulling images from the internal registry

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
