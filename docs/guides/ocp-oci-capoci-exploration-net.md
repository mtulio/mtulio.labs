# CAPI OCI labs

> ATTENTION: This guide is not completed. This is able to create network infrastructure using defaults of CAPOCI, but it requires more research to check if it is possible to custimize network artifacts to use standards used in OCP_OCI "integration" which uses only a single public and private subnets with NSGs to enhance the security, currently best practice. Nodes also not created as it requires more investigation how to custmize LB and bootstrap.

This is experimental steps to install CAPOCI (cluster-api provider OCI / CAPI OCI)
component to an OpenShift Cluster installed anywhere (AWS) with feature gate
TechPreviewNoUpgrade enabled to use CAPI operator.

Refereces:

- [Install CAPOCI](https://oracle.github.io/cluster-api-provider-oci/prerequisites.html)


## Prerequisites

- [Enable ClusterAPI feature gate on OCP](https://docs.openshift.com/container-platform/4.17/nodes/clusters/nodes-cluster-enabling-features.html#nodes-cluster-enabling-features-cli_nodes-cluster-enabling)

```
spec:
  featureSet: TechPreviewNoUpgrade
```

- [Install CertManager](https://docs.openshift.com/container-platform/4.17/security/cert_manager_operator/cert-manager-operator-install.html)

```sh
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-cert-manager-operator
  namespace: cert-manager-operator
spec:
  targetNamespaces:
  - "cert-manager-operator"
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-cert-manager-operator
  namespace: cert-manager-operator
spec:
  channel: stable-v1
  name: openshift-cert-manager-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
  startingCSV: cert-manager-operator.v1.13.0
EOF

# Wait to be installed
oc get csv -n cert-manager-operator -w

# Check the controllers
oc get pods -n cert-manager
```

## Install CAPOCI controllers on OpenShift

- Check if ClusterAPI controller is installed:

```
# resources
oc get all -n openshift-cluster-api

# CRDs

```

- [Install CAPIOCI CRDs](https://oracle.github.io/cluster-api-provider-oci/gs/install-cluster-api.html#capoci-components)

```sh
# Base URL https://github.com/oracle/cluster-api-provider-oci/releases/latest
CAPOCI_VERSION_URL=https://github.com/oracle/cluster-api-provider-oci/releases/download/v0.16.0

MANIFESTS=()
# CAPI OCI infra deployment: CRDs, Namespace, 
MANIFESTS+=("infrastructure-components.yaml")

# Declare required env vars to fix/replace on original manifests
export K8S_CP_LABEL="node-role.kubernetes.io\/control-plane"
export OCI_CREDENTIALS_FINGERPRINT_B64=$(grep ^fingerprint ~/.oci/config | awk -F'=' '{print$2}' | tr -d '\n' | base64 -w0)
export OCI_CREDENTIALS_KEY_B64=$(cat $(grep ^key_file ~/.oci/config | awk -F'=' '{print$2}') | base64 -w0)
export OCI_CREDENTIALS_PASSPHRASE_B64="\'\'"
export OCI_REGION_B64=$(grep ^region ~/.oci/config | awk -F'=' '{print$2}' | tr -d '\n' | base64 -w0)
export OCI_TENANCY_ID_B64=$(grep ^tenancy ~/.oci/config | awk -F'=' '{print$2}' | tr -d '\n' | base64 -w0)
export USE_INSTANCE_PRINCIPAL_B64=$(echo -n "false" | base64 -w0)
export OCI_USER_ID_B64=$(grep ^user ~/.oci/config | awk -F'=' '{print$2}' | tr -d '\n' | base64 -w0)

export EXP_MACHINE_POOL=true
export LOG_FORMAT=text
export INIT_OCI_CLIENTS_ON_STARTUP=true
export ENABLE_INSTANCE_METADATA_SERVICE_LOOKUP=false

# process resources
## envsubst is not working as expected
curl -sL ${CAPOCI_VERSION_URL}/infrastructure-components.yaml \
    | sed -e "s/\${K8S_CP_LABEL:=node-role.kubernetes.io\/control-plane}/${K8S_CP_LABEL}/g" \
    -e "s/\${OCI_CREDENTIALS_FINGERPRINT_B64:=\"\"}/${OCI_CREDENTIALS_FINGERPRINT_B64}/g" \
    -e "s/\${OCI_CREDENTIALS_KEY_B64:=\"\"}/${OCI_CREDENTIALS_KEY_B64}/g" \
    -e "s/\${OCI_CREDENTIALS_PASSPHRASE_B64:=\"\"}/${OCI_CREDENTIALS_PASSPHRASE_B64}/g" \
    -e "s/\${OCI_REGION_B64:=\"\"}/${OCI_REGION_B64}/g" \
    -e "s/\${OCI_TENANCY_ID_B64:=\"\"}/${OCI_TENANCY_ID_B64}/g" \
    -e "s/\${USE_INSTANCE_PRINCIPAL_B64:=\"ZmFsc2U=\"}/${USE_INSTANCE_PRINCIPAL_B64}/g" \
    -e "s/\${OCI_USER_ID_B64:=\"\"}/${OCI_USER_ID_B64}/g" \
    -e "s/\${EXP_MACHINE_POOL:=true}/${EXP_MACHINE_POOL}/g" \
    -e "s/\${LOG_FORMAT:=text}/${LOG_FORMAT}/g" \
    -e "s/\${INIT_OCI_CLIENTS_ON_STARTUP:=true}/${INIT_OCI_CLIENTS_ON_STARTUP}/g" \
    -e "s/\${ENABLE_INSTANCE_METADATA_SERVICE_LOOKUP:=false}/${ENABLE_INSTANCE_METADATA_SERVICE_LOOKUP}/g" \
    | oc apply -f -

# Force to remove enforced/unsupported securityContext
oc patch deployment.apps/capoci-controller-manager -n cluster-api-provider-oci-system \
  --type=json --patch '[
    {"op": "remove", "path": "/spec/template/spec/containers/0/securityContext"}]'
```

- Check resources:

```sh
oc get all -n cluster-api-provider-oci-system
```

- Observe the logs - CAPOCI should be started successfully

```sh
oc logs deployment.apps/capoci-controller-manager -n cluster-api-provider-oci-system -f

```

## Create workload cluster

Source: [CAPOCI create workload cluster](https://oracle.github.io/cluster-api-provider-oci/gs/create-workload-cluster.html)

- Prerequisites:

```sh
# FIXME/Don't do this (is there an better/supported solution?) =]
oc delete ValidatingWebhookConfiguration cluster-capi-operator
```

### Create infrastructure (VCN/network)

- Create OCI cluster infra (no machines/controlPlaneRef)

> based on template cluster-template.yaml

```sh
export CLUSTER_NAME=mrb-oci-00
export NAMESPACE=cluster-api-provider-oci-system
export OCI_COMPARTMENT_ID=$(oci iam compartment list  | jq -r '.data[] | select(.name=="ocp-eng-splat").["compartment-id"]')

cat << EOF | oc apply -f -
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  labels:
    cluster.x-k8s.io/cluster-name: "${CLUSTER_NAME}"
  name: "${CLUSTER_NAME}"
  namespace: "${NAMESPACE}"
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
        - ${POD_CIDR:="192.168.0.0/16"}
    serviceDomain: ${SERVICE_DOMAIN:="cluster.local"}
    services:
      cidrBlocks:
        - ${SERVICE_CIDR:="10.128.0.0/12"}
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: OCICluster
    name: "${CLUSTER_NAME}"
    namespace: "${NAMESPACE}"
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: OCICluster
metadata:
  labels:
    cluster.x-k8s.io/cluster-name: "${CLUSTER_NAME}"
  name: "${CLUSTER_NAME}"
  namespace: "${NAMESPACE}"
spec:
  compartmentId: "${OCI_COMPARTMENT_ID}"
EOF

# Check CAPI cluster
$ oc get cluster -A
NAMESPACE                         NAME         CLUSTERCLASS   PHASE          AGE   VERSION
cluster-api-provider-oci-system   mrb-oci-00                  Provisioning   28s   

# Check CAPOCI cluster
oc get ocicluster -A

# Checke the logs of infra provisioning

oc logs deployment.apps/capoci-controller-manager -n cluster-api-provider-oci-system -f
```

- Check the resources created:

```text
$ oc describe ocicluster mrb-oci-00 -n cluster-api-provider-oci-system | grep ^Events -A 100
Events:
  Type    Reason                      Age                    From                   Message
  ----    ------                      ----                   ----                   -------
  Normal  OwnerRefNotSet              7m39s                  ocicluster-controller  Cluster Controller has not yet set OwnerRef
  Normal  DRGReady                    6m38s (x2 over 7m37s)  ocicluster-controller  DRG is in ready state
  Normal  VCNReady                    6m37s (x2 over 7m36s)  ocicluster-controller  VCN is in ready state
  Normal  InternetGatewayReady        6m37s (x2 over 7m35s)  ocicluster-controller  InternetGateway is in ready state
  Normal  NATReady                    6m37s (x2 over 7m34s)  ocicluster-controller  NATGateway is in ready state
  Normal  ServiceGatewayReady         6m36s (x2 over 7m31s)  ocicluster-controller  ServiceGateway is in ready state
  Normal  NetworkSecurityReady        6m34s (x2 over 7m26s)  ocicluster-controller  NetworkSecurityGroup is in ready state
  Normal  RouteTableReady             6m33s (x2 over 7m24s)  ocicluster-controller  RouteTable is in ready state
  Normal  SubnetReady                 6m32s (x2 over 7m20s)  ocicluster-controller  Subnet is in ready state
  Normal  DRGVCNAttachmentEventReady  6m32s (x2 over 7m20s)  ocicluster-controller  DRGVCNAttachment is in ready state
  Normal  DRGRPCAttachmentEventReady  6m32s (x2 over 7m20s)  ocicluster-controller  DRGRPCAttachment is in ready state
  Normal  FailureDomainsReady         6m32s (x2 over 7m19s)  ocicluster-controller  FailureDomain is in ready state
  Normal  APIServerLoadBalancerReady  6m32s (x2 over 6m38s)  ocicluster-controller  ApiServerNetworkLoadbalancer is in ready state

```

### Create machines

> WIP/Experimental: the steps below will failed to bootstrap as it requires customization in how OCP is booted with RHCOS (ignitions/custom images, etc).

```sh
export CLUSTER_NAME=mrb-oci-00
export NAMESPACE=cluster-api-provider-oci-system
export NODE_MACHINE_COUNT=1
# Random ID rhcos-414.92.202310210434-0-openstack.x86_64.qcow2.gz

export OCI_IMAGE_ID="ocid1.image.oc1.iad.aaaaaaaapfdalbrg5ou7utgbbpvachwiqixdpz3udhj7mpvkvoq4gmyyus6a"

export KUBERNETES_VERSION=1.29.8

cat << EOF | oc apply -f -
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: OCIMachineTemplate
metadata:
  name: "${CLUSTER_NAME}-md-0"
  namespace: "${NAMESPACE}"
spec:
  template:
    spec:
      imageId: "${OCI_IMAGE_ID}"
      compartmentId: "${OCI_COMPARTMENT_ID}"
      shape: "${OCI_NODE_MACHINE_TYPE=VM.Standard.E4.Flex}"
      shapeConfig:
        ocpus: "${OCI_NODE_MACHINE_TYPE_OCPUS=4}"
      metadata:
        ssh_authorized_keys: "${OCI_SSH_KEY}"
      isPvEncryptionInTransitEnabled: ${OCI_NODE_PV_TRANSIT_ENCRYPTION=true}
---
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: "${CLUSTER_NAME}-md-0"
  namespace: "${NAMESPACE}"
spec:
  clusterName: "${CLUSTER_NAME}"
  replicas: ${NODE_MACHINE_COUNT}
  selector:
    matchLabels:
  template:
    spec:
      clusterName: "${CLUSTER_NAME}"
      version: "${KUBERNETES_VERSION}"
      bootstrap:
        configRef:
          name: "${CLUSTER_NAME}-md-0"
          apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
          kind: OCIMachineTemplate
      infrastructureRef:
        name: "${CLUSTER_NAME}-md-0"
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
        kind: OCIMachineTemplate
EOF
```
