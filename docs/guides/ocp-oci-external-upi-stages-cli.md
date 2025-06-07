# WIP | Installing OpenShift on Oracle Cloud (OCI) with Ansible (fully automated)

!!! danger "status"
    This document is not completed, and requires further review.

!!! note "Reference"
    This document is based in the PR [openshift/infrastructure-provider-onboarding-guide/pull/16](https://github.com/openshift/infrastructure-provider-onboarding-guide/pull/16).

# Use case of installing a cluster with external platform type in Oracle Cloud Infrastructure

This use case provides details of how to deploy an OpenShift cluster using external
platform type in Oracle Cloud Infrastructure (OCI), deploying providers' Cloud Controller
Manager (CCM).

The guide derives from ["Installing a cluster on any platform"](https://docs.openshift.com/container-platform/4.13/installing/installing_platform_agnostic/installing-platform-agnostic.html) documentation, adapted to the external platform type.
The steps provide low-level details to customize Oracle's components like CCM.

This guide is organized into three sections:

- Section 1: Create infrastructure resources (Network, DNS, and Load Balancer), mostly required before OCI CCM configuration.
- Section 2: Create OpenShift configurations with customized resources (OCI CCM)
- Section 3: Create the compute nodes and review the installation

If you are exploring how to customize the OpenShift platform external type with CCM, without
deploying the whole cluster creation in OCI, feel free to jump to `Section 2`.

Section 1 and 3 are mostly OCI-specific, and it is valuable for readers exploring
in detail the OCI manual deployment.

!!! tip "Automation options"
    The goal of this document is to provide details of the platform external type,
    without focusing on the infrastructure automation. The tool used to
    provision the resources described in this guide is the Oracle Cloud CLI.

    Alternatively, the automation can be achieved using official
    [Ansible](https://docs.oracle.com/en-us/iaas/tools/oci-ansible-collection/4.25.0/index.html)
    or [Terraform](https://registry.terraform.io/providers/oracle/oci/latest/docs)
    modules.

!!! danger "Unsupported Document"
    This guide is created only for Red Hat partners or providers aiming to extend
    external components in OpenShift, and should not be used as an official or
    supported OpenShift installation method.

    Please review the product documentation to get the supported path.


Table of Contents

- [Prerequisites](#prerequisites)
- [Section 1. Create Infrastructure resources](#section-1-create-infrastructure-resources)
    - [Identity](#identity)
    - [Network](#network)
    - [DNS](#dns)
    - [Load Balancer](#load-balancer)
- [Section 2. Preparing the installation](#section-2-preparing-the-installation)
    - [Create install-config.yaml](#create-the-installer-configuration)
    - [Create manifests](#create-manifests)
        - [Create manifests for CCM](#create-manifests-for-oci-cloud-controller-manager)
        - [Create custom manifests for Kubelet](#create-custom-manifests-for-kubelet)
    - [Create ignition files](#create-ignition-files)
- [Section 3. Create the cluster](#section-3-create-the-cluster)
    - [Cluster nodes](#cluster-nodes)
        - [Upload the RHCOS image](#upload-the-rhcos-image)
        - [Bootstrap](#bootstrap)
        - [Control Plane](#control-plane)
        - [Compute](#computeworkers)
    - [Review the installation](#review-the-installation)

## Prerequisites

### Clients

#### OpenShift clients

Download the OpenShift CLI and installer:

- [Navigate to the release controller](https://openshift-release.apps.ci.l2s4.p1.openshiftapps.com/#4-dev-preview) and choose the release image:

!!! tip "Credentials"
    The [Red Hat Cloud credential (Pull secret)](https://console.redhat.com/openshift/install/metal/agent-based)
    is required to pull from the repository `quay.io/openshift-release-dev/ocp-release`.

    Alternatively, you can provide the option `-a /path/to/pull-secret.json`.

    The examples in this document export the path of the pull secret to the environment variable `PULL_SECRET_FILE`.

!!! warning "Supported OpenShift versions"
    The Platform External is available in OpenShift 4.14+.

- Extract the tools (clients):
```sh
oc adm release extract -a $PULL_SECRET_FILE \
  --tools "quay.io/openshift-release-dev/ocp-release:4.14.0-rc.7-x86_64"
```

- Extract the tarball files:
```sh
tar xvfz openshift-client-*.tar.gz
tar xvfz openshift-install-*.tar.gz
```

Move the binaries `openshift-install` and `oc` to any directory exported in the `$PATH`.

#### OCI Command Line Interface

The OCI CLI is used in this guide to create infrastructure resources in the OCI.

- [Install the CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm#InstallingCLI__linux_and_unix):
```sh
python3.9 -m venv ./venv-oci && source ./venv-oci/bin/activate
pip install oci-cli
```

- [Setup the user](https://docs.oracle.com/en-us/iaas/tools/oci-ansible-collection/4.25.0/guides/authentication.html#api-key-authentication) (Using [Console](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm#two))


#### Utilities

- Download [jq](https://jqlang.github.io/jq/download/): used to filter the results returned by CLI

- Download [yq](https://github.com/mikefarah/yq/releases/tag/v4.34.1): used to patch the `yaml` manifests.
~~~bash
wget -O yq "https://github.com/mikefarah/yq/releases/download/v4.34.1/yq_linux_amd64"
chmod u+x yq
~~~

- Download [butane](https://github.com/coreos/butane): used to create MachineConfig files.
~~~bash
wget -O butane "https://github.com/coreos/butane/releases/download/v0.18.0/butane-x86_64-unknown-linux-gnu"
chmod u+x butane
~~~

### Setup the Provider Account

A user with administrator access was used to create the OpenShift cluster described
in this use case.

The cluster was created in a dedicated compartment in Oracle Cloud Infrastructure,
it allows the creation of custom policies for components like Cloud Controller Manager.

The following steps describe how to create an compartment from any nested level,
and create predefined tags used to apply policies to the compartment:

- Set the compartment id variables:
```sh
# A new compartment will be created as a child of this:
PARENT_COMPARTMENT_ID="<ocid1.compartment.oc1...>"

# Cluster Name
CLUSTER_NAME="ocp-oci-demo"

# DNS information
BASE_DOMAIN=example.com
DNS_COMPARTMENT_ID="<ocid1.compartment.oc1...>"
```

- Create cluster compartment - child of `${PARENT_COMPARTMENT_ID}`:
```sh
COMPARTMENT_NAME_OPENSHIFT="$CLUSTER_NAME"
COMPARTMENT_ID_OPENSHIFT=$(oci iam compartment create \
  --compartment-id "$PARENT_COMPARTMENT_ID" \
  --description "$COMPARTMENT_NAME_OPENSHIFT compartment" \
  --name "$COMPARTMENT_NAME_OPENSHIFT" \
  --wait-for-state ACTIVE \
  --query data.id --raw-output)
```

## Section 1. Create Infrastructure resources

### Identity

There are two methods to provide authentication to Cloud Controller Manager to access the Cloud API:

- User
- Instance Principals

The steps described in this document are using [Instance Principals](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/callingservicesfrominstances.htm).

Instance principals require extra steps to grant permissions to the Instances to access
the APIs. The steps below describe how to create the namespace tags, used in the
Dynamic Group rule filtering only the Control Plane nodes to take actions defined in the
compartment's Policy.

Steps:

- Create managed tags:
```sh
TAG_NAMESPACE_ID=$(oci iam tag-namespace create \
  --compartment-id "${COMPARTMENT_ID_OPENSHIFT}" \
  --description "Cluster Name" \
  --name "$CLUSTER_NAME" \
  --wait-for-state ACTIVE \
  --query data.id --raw-output)

oci iam tag create \
  --description "OpenShift Node Role" \
  --name "role" \
  --tag-namespace-id "$TAG_NAMESPACE_ID" \
  --validator '{"validatorType":"ENUM","values":["master","worker"]}'
```

- Create Dynamic Group with name `demo-${CLUSTER_NAME}-controlplane` with the following rule:
```sh
DYNAMIC_GROUP_NAME="${CLUSTER_NAME}-controlplane"
oci iam dynamic-group create \
  --name "${DYNAMIC_GROUP_NAME}" \
  --description "Control Plane nodes for ${CLUSTER_NAME}" \
  --matching-rule "Any {instance.compartment.id='$COMPARTMENT_ID_OPENSHIFT', tag.${CLUSTER_NAME}.role.value='master'}" \
  --wait-for-state ACTIVE
```

- Create a policy allowing the Dynamic Group `$DYNAMIC_GROUP_NAME`
  access resources in the cluster compartment (`$COMPARTMENT_NAME_OPENSHIFT`):
```sh
POLICY_NAME="${CLUSTER_NAME}-cloud-controller-manager"
oci iam policy create --name $POLICY_NAME \
    --compartment-id $COMPARTMENT_ID_OPENSHIFT \
    --description "Allow Cloud Controller Manager in OpenShift access Cloud Resources" \
    --statements "[
\"Allow dynamic-group $DYNAMIC_GROUP_NAME to manage volume-family in compartment $COMPARTMENT_NAME_OPENSHIFT\",
\"Allow dynamic-group $DYNAMIC_GROUP_NAME to manage instance-family in compartment $COMPARTMENT_NAME_OPENSHIFT\",
\"Allow dynamic-group $DYNAMIC_GROUP_NAME to manage security-lists in compartment $COMPARTMENT_NAME_OPENSHIFT\",
\"Allow dynamic-group $DYNAMIC_GROUP_NAME to use virtual-network-family in compartment $COMPARTMENT_NAME_OPENSHIFT\",
\"Allow dynamic-group $DYNAMIC_GROUP_NAME to manage load-balancers in compartment $COMPARTMENT_NAME_OPENSHIFT\"]"
```

!!! tip "Helper"
    OCI CLI documentation for [`oci iam policy create`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.29.1/oci_cli_docs/cmdref/iam/policy/create.html)

    OCI Console path: `Menu > Identity & Security > Policies >
    (Select the Compartment 'openshift') > Create Policy > Name=openshift-oci-cloud-controller-manager`

### Network

The OCI VCN (Virtual Cloud Network) must be created using the [Networking requirements for user-provisioned infrastructure](https://docs.openshift.com/container-platform/4.13/installing/installing_platform_agnostic/installing-platform-agnostic.html#installation-network-user-infra_installing-platform-agnostic).

!!! tip "Info"
    The resource name provided in this guide is not a standard but follows
    a similar naming convention created by the installer in the supported cloud
    providers. The names will also be used in future sections to discover resources.

Create the VCN and dependencies with the following configuration:

| Resource | Name | Attributes | Note |
| -- | -- | -- | -- |
| VCN | `${CLUSTER_NAME}-vcn` | CIDR 10.0.0.0/16 | |
| Subnet | `${CLUSTER_NAME}-net-public` | 10.0.0.0/20 | Regional,Resolve DNS (pub) |
| Subnet | `${CLUSTER_NAME}-net-private` | 10.0.128.0/20 | Regional,Resolve DNS (priv)  |
| Internet Gateway | `${CLUSTER_NAME}-igw` | -- | Attached to public route table |
| NAT Gateway | `${CLUSTER_NAME}-natgw` | -- | Attached to private route table |
| Route Table | `${CLUSTER_NAME}-rtb-public` | `0/0` to `igw` | -- |
| Route Table | `${CLUSTER_NAME}-rtb-private` | `0/0` to `natgw` | -- |
| NSG | `${CLUSTER_NAME}-nsg-nlb` | -- | Attached to Load Balancer |
| NSG | `${CLUSTER_NAME}-nsg-controlplane` | -- | Attached to Control Plane nodes |
| NSG | `${CLUSTER_NAME}-nsg-compute` | -- | Attached to Compute nodes |

Steps:

- VCN
- Security List (need?)
- IGW
- NGW
- Route Table: Private
- Route Table: Public
- Subnets
- NSG

```sh
# Base doc for network service
# https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.30.2/oci_cli_docs/cmdref/network.html

# VCN
## https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.30.2/oci_cli_docs/cmdref/network/vcn/create.html
VCN_ID=$(oci network vcn create \
  --compartment-id "${COMPARTMENT_ID_OPENSHIFT}" \
  --display-name "${CLUSTER_NAME}-vcn" \
  --cidr-block "10.0.0.0/20" \
  --dns-label "ocp" \
  --wait-for-state AVAILABLE \
  --query data.id --raw-output)

# IGW
## https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.30.2/oci_cli_docs/cmdref/network/internet-gateway/create.html
IGW_ID=$(oci network internet-gateway create \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  --display-name "${CLUSTER_NAME}-igw" \
  --is-enabled true \
  --wait-for-state AVAILABLE \
  --vcn-id $VCN_ID \
  --query data.id --raw-output)

# NAT Gateway
## https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.30.2/oci_cli_docs/cmdref/network/nat-gateway/create.html
NGW_ID=$(oci network nat-gateway create \
  --compartment-id ${COMPARTMENT_ID_OPENSHIFT} \
  --display-name "${CLUSTER_NAME}-natgw" \
  --vcn-id $VCN_ID \
  --wait-for-state AVAILABLE \
  --query data.id --raw-output)

# Route Table: Public
## https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.30.2/oci_cli_docs/cmdref/network/route-table/create.html
RTB_PUB_ID=$(oci network route-table create \
  --compartment-id ${COMPARTMENT_ID_OPENSHIFT} \
  --vcn-id $VCN_ID \
  --display-name "${CLUSTER_NAME}-rtb-public" \
  --route-rules "[{\"cidrBlock\":\"0.0.0.0/0\",\"networkEntityId\":\"$IGW_ID\"}]" \
  --wait-for-state AVAILABLE \
  --query data.id --raw-output)

# Route Table: Private
RTB_PVT_ID=$(oci network route-table create \
  --compartment-id ${COMPARTMENT_ID_OPENSHIFT} \
  --vcn-id $VCN_ID \
  --display-name "${CLUSTER_NAME}-rtb-private" \
  --route-rules "[{\"cidrBlock\":\"0.0.0.0/0\",\"networkEntityId\":\"$NGW_ID\"}]" \
  --wait-for-state AVAILABLE \
  --query data.id --raw-output)

# Subnet Public (regional)
# https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.30.2/oci_cli_docs/cmdref/network/subnet/create.html
SUBNET_ID_PUBLIC=$(oci network subnet create \
  --compartment-id ${COMPARTMENT_ID_OPENSHIFT} \
  --vcn-id $VCN_ID \
  --display-name "${CLUSTER_NAME}-net-public" \
  --dns-label "pub" \
  --cidr-block "10.0.0.0/21" \
  --route-table-id $RTB_PUB_ID \
  --wait-for-state AVAILABLE \
  --query data.id --raw-output)

# Subnet Private (regional)
SUBNET_ID_PRIVATE=$(oci network subnet create \
  --compartment-id ${COMPARTMENT_ID_OPENSHIFT} \
  --vcn-id $VCN_ID \
  --display-name "${CLUSTER_NAME}-net-private" \
  --dns-label "priv" \
  --cidr-block "10.0.8.0/21" \
  --route-table-id $RTB_PVT_ID \
  --prohibit-internet-ingress true \
  --prohibit-public-ip-on-vnic true \
  --wait-for-state AVAILABLE \
  --query data.id --raw-output)


# NSGs (empty to allow be referenced in the rules)
## NSG Control Plane
## https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.30.2/oci_cli_docs/cmdref/network/nsg/create.html
NSG_ID_CPL=$(oci network nsg create \
  --compartment-id ${COMPARTMENT_ID_OPENSHIFT} \
  --vcn-id $VCN_ID \
  --display-name "${CLUSTER_NAME}-nsg-controlplane" \
  --wait-for-state AVAILABLE \
  --query data.id --raw-output)

## NSG Compute/workers
NSG_ID_CMP=$(oci network nsg create \
  --compartment-id ${COMPARTMENT_ID_OPENSHIFT} \
  --vcn-id $VCN_ID \
  --display-name "${CLUSTER_NAME}-nsg-compute" \
  --wait-for-state AVAILABLE \
  --query data.id --raw-output)

## NSG Load Balancers
NSG_ID_NLB=$(oci network nsg create \
  --compartment-id ${COMPARTMENT_ID_OPENSHIFT} \
  --vcn-id $VCN_ID \
  --display-name "${CLUSTER_NAME}-nsg-nlb" \
  --wait-for-state AVAILABLE \
  --query data.id --raw-output)

# NSG Rules: Control Plane NSG
## https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.30.2/oci_cli_docs/cmdref/network/nsg/rules/add.html
# oci network NSG rules add --generate-param-json-input security-rules
cat <<EOF > ./oci-vcn-nsg-rule-nodes.json
[
  {
    "description": "allow all outbound traffic",
    "protocol": "all", "destination": "0.0.0.0/0", "destination-type": "CIDR_BLOCK",
    "direction": "EGRESS", "is-stateless": false
  },
  {
    "description": "All from control plane NSG",
    "direction": "INGRESS", "is-stateless": false,
    "protocol": "all",
    "source": "$NSG_ID_CPL", "source-type": "NETWORK_SECURITY_GROUP"
  },
  {
    "description": "All from control plane NSG",
    "direction": "INGRESS", "is-stateless": false,
    "protocol": "all",
    "source": "$NSG_ID_CMP", "source-type": "NETWORK_SECURITY_GROUP"
  },
  {
    "description": "All from control plane NSG",
    "direction": "INGRESS", "is-stateless": false,
    "protocol": "all",
    "source": "$NSG_ID_NLB", "source-type": "NETWORK_SECURITY_GROUP"
  },
  {
    "description": "allow ssh to nodes",
    "direction": "INGRESS", "is-stateless": false,
    "protocol": "6",
    "source": "0.0.0.0/0", "source-type": "CIDR_BLOCK",
    "tcp-options": {
      "destination-port-range": {
        "max": 22,
        "min": 22
      }
    }
  }
]
EOF

oci network nsg rules add \
  --nsg-id "${NSG_ID_CPL}" \
  --security-rules file://oci-vcn-nsg-rule-nodes.json

oci network nsg rules add \
  --nsg-id "${NSG_ID_CMP}" \
  --security-rules file://oci-vcn-nsg-rule-nodes.json

# NSG Security rules for NSG
cat <<EOF > ./oci-vcn-nsg-rule-nlb.json
[
  {
    "description": "allow Kube API",
    "direction": "INGRESS", "is-stateless": false,
    "source-type": "CIDR_BLOCK", "protocol": "6", "source": "0.0.0.0/0",
    "tcp-options": { "destination-port-range": {
      "max": 6443, "min": 6443
    }}
  },
  {
    "description": "allow Kube API to Control Plane",
    "destination": "$NSG_ID_CPL",
    "destination-type": "NETWORK_SECURITY_GROUP",
    "direction": "EGRESS", "is-stateless": false,
    "protocol": "6", "tcp-options":{"destination-port-range":{
      "max": 6443, "min": 6443
    }}
  },
  {
    "description": "allow MCS listener from control plane pool",
    "direction": "INGRESS",
    "is-stateless": false, "protocol": "6",
    "source": "$NSG_ID_CPL", "source-type": "NETWORK_SECURITY_GROUP",
    "tcp-options": {"destination-port-range":{
      "max": 22623, "min": 22623
    }}
  },
  {
    "description": "allow MCS listener from compute pool",
    "direction": "INGRESS",
    "is-stateless": false, "protocol": "6",
    "source": "$NSG_ID_CMP", "source-type": "NETWORK_SECURITY_GROUP",
    "tcp-options": {"destination-port-range": {
      "max": 22623, "min": 22623
    }}
  },
  {
    "description": "allow MCS listener access the Control Plane backends",
    "destination": "$NSG_ID_CPL",
    "destination-type": "NETWORK_SECURITY_GROUP",
    "direction": "EGRESS", "is-stateless": false,
    "protocol": "6", "tcp-options": {"destination-port-range": {
      "max": 22623, "min": 22623
    }}
  },
  {
    "description": "allow listener for Ingress HTTP",
    "direction": "INGRESS", "is-stateless": false,
    "source-type": "CIDR_BLOCK", "protocol": "6", "source": "0.0.0.0/0",
    "tcp-options": {"destination-port-range": {
      "max": 80, "min": 80
    }}
  },
  {
    "description": "allow listener for Ingress HTTPS",
    "direction": "INGRESS", "is-stateless": false,
    "source-type": "CIDR_BLOCK", "protocol": "6", "source": "0.0.0.0/0",
    "tcp-options": {"destination-port-range": {
      "max": 443, "min": 443
    }}
  },
  {
    "description": "allow backend access the Compute pool for HTTP",
    "destination": "$NSG_ID_CMP",
    "destination-type": "NETWORK_SECURITY_GROUP",
    "direction": "EGRESS", "is-stateless": false,
    "protocol": "6", "tcp-options": {"destination-port-range": {
      "max": 80, "min": 80
    }}
  },
  {
    "description": "allow backend access the Compute pool for HTTPS",
    "destination": "$NSG_ID_CMP",
    "destination-type": "NETWORK_SECURITY_GROUP",
    "direction": "EGRESS", "is-stateless": false,
    "protocol": "6", "tcp-options": {"destination-port-range": {
      "max": 443, "min": 443
    }}
  }
]
EOF

oci network nsg rules add \
  --nsg-id "${NSG_ID_NLB}" \
  --security-rules file://oci-vcn-nsg-rule-nlb.json
```

### Load Balancer

Steps to create the OCI Network Load Balancer (NLB) to the cluster.

A single NLB is created with listeners to Kubernetes API Server, Machine
Config Server (MCS) and Ingress for HTTP and HTTPS. The MCS is
the only one with internal access.

The following resources will be created in the NLB:

- Backend Sets (BSet):

| BSet Name | Port | Health Check (Proto/Path/Interval/Timeout) |
| -- | -- | -- |
| `${CLUSTER_NAME}-api` | TCP/6443 | HTTPS`/readyz`/10/3 |
| `${CLUSTER_NAME}-mcs` | TCP/22623 | HTTPS`/healthz`/10/3 |
| `${CLUSTER_NAME}-http` | TCP/80 | TCP/80/10/3 |
| `${CLUSTER_NAME}-https` | TCP/443 | TCP/443/10/3 |

- Listeners:

| Name | Port | BSet Name |
| -- | -- | -- |
| `${CLUSTER_NAME}-api` | TCP/6443 | `${CLUSTER_NAME}-api` |
| `${CLUSTER_NAME}-mcs` | TCP/22623 | `${CLUSTER_NAME}-mcs` |
| `${CLUSTER_NAME}-http` | TCP/80 | `${CLUSTER_NAME}-http` |
| `${CLUSTER_NAME}-https` | TCP/443 | `${CLUSTER_NAME}-https` |

Steps:

- Get the Public Subnet ID
- Get Security Group ID
- Create NLB
- Create BackendSets
- Create Listeners

```sh
# NLB base: https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.30.2/oci_cli_docs/cmdref/nlb.html

# Create BackendSets
## Kubernetes API Server (KAS): api
## Machine Config Server (MCS): mcs
## Ingress HTTP
## Ingress HTTPS
cat <<EOF > ./oci-nlb-backends.json
{
  "${CLUSTER_NAME}-api": {
    "health-checker": {
      "interval-in-millis": 10000,
      "port": 6443,
      "protocol": "HTTPS",
      "retries": 3,
      "return-code": 200,
      "timeout-in-millis": 3000,
      "url-path": "/readyz"
    },
    "ip-version": "IPV4",
    "is-preserve-source": false,
    "name": "${CLUSTER_NAME}-api",
    "policy": "FIVE_TUPLE"
  },
  "${CLUSTER_NAME}-mcs": {
    "health-checker": {
      "interval-in-millis": 10000,
      "port": 22623,
      "protocol": "HTTPS",
      "retries": 3,
      "return-code": 200,
      "timeout-in-millis": 3000,
      "url-path": "/healthz"
    },
    "ip-version": "IPV4",
    "is-preserve-source": false,
    "name": "${CLUSTER_NAME}-mcs",
    "policy": "FIVE_TUPLE"
  },
  "${CLUSTER_NAME}-ingress-http": {
    "health-checker": {
      "interval-in-millis": 10000,
      "port": 80,
      "protocol": "TCP",
      "retries": 3,
      "timeout-in-millis": 3000
    },
    "ip-version": "IPV4",
    "is-preserve-source": false,
    "name": "${CLUSTER_NAME}-ingress-http",
    "policy": "FIVE_TUPLE"
  },
  "${CLUSTER_NAME}-ingress-https": {
    "health-checker": {
      "interval-in-millis": 10000,
      "port": 443,
      "protocol": "TCP",
      "retries": 3,
      "timeout-in-millis": 3000
    },
    "ip-version": "IPV4",
    "is-preserve-source": false,
    "name": "${CLUSTER_NAME}-ingress-https",
    "policy": "FIVE_TUPLE"
  }
}
EOF

cat <<EOF > ./oci-nlb-listeners.json
{
  "${CLUSTER_NAME}-api": {
    "default-backend-set-name": "${CLUSTER_NAME}-api",
    "ip-version": "IPV4",
    "name": "${CLUSTER_NAME}-api",
    "port": 6443,
    "protocol": "TCP"
  },
  "${CLUSTER_NAME}-mcs": {
    "default-backend-set-name": "${CLUSTER_NAME}-mcs",
    "ip-version": "IPV4",
    "name": "${CLUSTER_NAME}-mcs",
    "port": 22623,
    "protocol": "TCP"
  },
  "${CLUSTER_NAME}-ingress-http": {
    "default-backend-set-name": "${CLUSTER_NAME}-ingress-http",
    "ip-version": "IPV4",
    "name": "${CLUSTER_NAME}-ingress-http",
    "port": 80,
    "protocol": "TCP"
  },
  "${CLUSTER_NAME}-ingress-https": {
    "default-backend-set-name": "${CLUSTER_NAME}-ingress-https",
    "ip-version": "IPV4",
    "name": "${CLUSTER_NAME}-ingress-https",
    "port": 443,
    "protocol": "TCP"
  }
}
EOF

# NLB create
# https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.30.2/oci_cli_docs/cmdref/nlb/network-load-balancer/create.html
NLB_ID=$(oci nlb network-load-balancer create \
  --compartment-id ${COMPARTMENT_ID_OPENSHIFT} \
  --display-name "${CLUSTER_NAME}-nlb" \
  --subnet-id "${SUBNET_ID_PUBLIC}" \
  --backend-sets file://oci-nlb-backends.json \
  --listeners file://oci-nlb-listeners.json \
  --network-security-group-ids "[\"$NSG_ID_NLB\"]" \
  --is-private false \
  --nlb-ip-version "IPV4" \
  --wait-for-state ACCEPTED \
  --query data.id --raw-output)
```

### DNS

Steps to create the resource records pointing to the API address (public and private), and
to the default router.

The following DNS records will be created:

| Domain | Record | Value |
| -- | -- | -- |
| `${CLUSTER_NAME}`.`${BASE_DOMAIN}` | api | Public IP Address or DNS for the Load Balancer |
| `${CLUSTER_NAME}`.`${BASE_DOMAIN}` | api-int | Private IP Address or DNS for the Load Balancer |
| `${CLUSTER_NAME}`.`${BASE_DOMAIN}` | *.apps | Public IP Address or DNS for the Load Balancer |

!!! tip "Helper"
    It's not required to have a publicly accessible API and DNS domain, alternatively, you can use a bastion host to access the private API endpoint.

Steps:

- Get Public IP for LB
- Get Private IP for LB
- Create records

```sh
# NLB IPs
## https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.30.2/oci_cli_docs/cmdref/nlb/network-load-balancer/list.html
## Public
NLB_IP_PUBLIC=$(oci nlb network-load-balancer list \
  --compartment-id ${COMPARTMENT_ID_OPENSHIFT} \
  --display-name "${CLUSTER_NAME}-nlb" \
  | jq -r '.data.items[0]["ip-addresses"][] | select(.["is-public"]==true) | .["ip-address"]')

## Private
NLB_IP_PRIVATE=$(oci nlb network-load-balancer list \
  --compartment-id ${COMPARTMENT_ID_OPENSHIFT} \
  --display-name "${CLUSTER_NAME}-nlb" \
  | jq -r '.data.items[0]["ip-addresses"][] | select(.["is-public"]==false) | .["ip-address"]')

# DNS record
## Assuming the zone already exists and is in DNS_COMPARTMENT_ID
DNS_RECORD_APIINT="api-int.${CLUSTER_NAME}.${BASE_DOMAIN}"
oci dns record rrset patch \
  --compartment-id ${DNS_COMPARTMENT_ID} \
  --domain "${DNS_RECORD_APIINT}" \
  --rtype "A" \
  --zone-name-or-id "${BASE_DOMAIN}" \
  --scope GLOBAL \
  --items "[{
    \"domain\": \"${DNS_RECORD_APIINT}\",
    \"rdata\": \"${NLB_IP_PRIVATE}\",
    \"rtype\": \"A\", \"ttl\": 300
  }]"

DNS_RECORD_APIEXT="api.${CLUSTER_NAME}.${BASE_DOMAIN}"
oci dns record rrset patch \
  --compartment-id ${DNS_COMPARTMENT_ID} \
  --domain "${DNS_RECORD_APIEXT}" \
  --rtype "A" \
  --zone-name-or-id "${BASE_DOMAIN}" \
  --scope GLOBAL \
  --items "[{
    \"domain\": \"${DNS_RECORD_APIEXT}\",
    \"rdata\": \"${NLB_IP_PUBLIC}\",
    \"rtype\": \"A\", \"ttl\": 300
  }]"

DNS_RECORD_APPS="*.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
oci dns record rrset patch \
  --compartment-id ${DNS_COMPARTMENT_ID} \
  --domain "${DNS_RECORD_APPS}" \
  --rtype "A" \
  --zone-name-or-id "${BASE_DOMAIN}" \
  --scope GLOBAL \
  --items "[{
    \"domain\": \"${DNS_RECORD_APPS}\",
    \"rdata\": \"${NLB_IP_PUBLIC}\",
    \"rtype\": \"A\", \"ttl\": 300
  }]"
```

## Section 2. Preparing the installation

This section describes how to set up OpenShift to customize the manifests
used in the installation.

### Create the installer configuration

Modify and export the variables used to build the `install-config.yaml` and
the later steps:
```sh
INSTALL_DIR=./install-dir
mkdir -p $INSTALL_DIR

SSH_PUB_KEY_FILE="${HOME}/.ssh/bundle.pub"
PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
```

#### Create install-config.yaml

Create the `install-config.yaml` setting the platform type to `external`:

```sh
cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
platform:
  external:
    platformName: oci
publish: External
pullSecret: >
  $(cat ${PULL_SECRET_FILE})
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
```

### Create manifests

```sh
openshift-install create manifests --dir $INSTALL_DIR
```

#### Create manifests for OCI Cloud Controller Manager

The steps in this section describe how to customize the OpenShift installation
providing the Cloud Controller Manager manifests to be added in the bootstrap process.

!!! warning "Info"
    This guide is based on the OCI CCM v1.26.0. You must read the
    [project documentation](https://github.com/oracle/oci-cloud-controller-manager)
    for more information.

Steps:

- Create the namespace manifest:

!!! danger "Important"
    Red Hat does not recommend creating resources in namespaces prefixed with `kube-*`
    and `openshift-*`.

    The custom namespace manifest must be created, and then deployment manifests must
    be adapted to use the custom namespace.

    See [the documentation](https://docs.openshift.com/container-platform/4.13/applications/projects/working-with-projects.html) for more information.


```sh
OCI_CCM_NAMESPACE=oci-cloud-controller-manager

cat <<EOF > ${INSTALL_DIR}/manifests/oci-00-ccm-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: $OCI_CCM_NAMESPACE
  annotations:
    workload.openshift.io/allowed: management
    include.release.openshift.io/self-managed-high-availability: "true"
  labels:
    "pod-security.kubernetes.io/enforce": "privileged"
    "pod-security.kubernetes.io/audit": "privileged"
    "pod-security.kubernetes.io/warn": "privileged"
    "security.openshift.io/scc.podSecurityLabelSync": "false"
    "openshift.io/run-level": "0"
    "pod-security.kubernetes.io/enforce-version": "v1.24"
EOF
```

<!-- !!! danger "TODO"
    - The Pod Admission Security must be reviewed aiming to use other than `privileged`
    - Set [critical pod annotation](https://kubernetes.io/docs/tasks/administer-cluster/guaranteed-scheduling-critical-addon-pods/#rescheduler-guaranteed-scheduling-of-critical-add-ons) in this namespace. -->


- Export the variables used to create the OCI CCM Cloud Config:

```sh
OCI_CLUSTER_REGION=us-sanjose-1

# Review the defined vars
cat <<EOF>/dev/stdout
OCI_CLUSTER_REGION=$OCI_CLUSTER_REGION
VCN_ID=$VCN_ID
SUBNET_ID_PUBLIC=$SUBNET_ID_PUBLIC
EOF
```

- Create the OCI CCM configuration as a secret stored in the install directory:

```sh
cat <<EOF > ./oci-secret-cloud-provider.yaml
auth:
  region: $OCI_CLUSTER_REGION
useInstancePrincipals: true
compartment: $COMPARTMENT_ID_OPENSHIFT
vcn: $VCN_ID
loadBalancer:
  securityListManagementMode: None
  subnet1: $SUBNET_ID_PUBLIC
EOF

cat <<EOF > ${INSTALL_DIR}/manifests/oci-01-ccm-00-secret.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: oci-cloud-controller-manager
  namespace: $OCI_CCM_NAMESPACE
data:
  cloud-provider.yaml: $(base64 -w0 < ./oci-secret-cloud-provider.yaml)
EOF
```

<!--
!!! warning "Question"
    - Is it possible to use NSG instead of SecList in Load Balancer?
-->

- Download manifests from [OCI CCM's Github](https://github.com/oracle/oci-cloud-controller-manager)
  and save it in the directory `${INSTALL_DIR}/manifests`:

```sh
CCM_RELEASE=v1.26.0

wget https://github.com/oracle/oci-cloud-controller-manager/releases/download/${CCM_RELEASE}/oci-cloud-controller-manager-rbac.yaml -O oci-cloud-controller-manager-rbac.yaml

wget  https://github.com/oracle/oci-cloud-controller-manager/releases/download/${CCM_RELEASE}/oci-cloud-controller-manager.yaml -O oci-cloud-controller-manager.yaml
```

- Patch the RBAC file setting the correct namespace in the `ServiceAccount`:

```sh
./yq ". | select(.kind==\"ServiceAccount\").metadata.namespace=\"$OCI_CCM_NAMESPACE\"" oci-cloud-controller-manager-rbac.yaml > ./oci-cloud-controller-manager-rbac_patched.yaml
```

- Patch the RBAC file setting the correct namespace in the `ServiceAccount`:

```sh
cat << EOF > ./oci-ccm-rbac_patch_crb-subject.yaml
- kind: ServiceAccount
  name: cloud-controller-manager
  namespace: $OCI_CCM_NAMESPACE
EOF

./yq eval-all -i ". | select(.kind==\"ClusterRoleBinding\").subjects *= load(\"oci-ccm-rbac_patch_crb-subject.yaml\")" ./oci-cloud-controller-manager-rbac_patched.yaml
```

- Split the RBAC manifest file:

```sh
./yq -s '"./oci-01-ccm-01-rbac_" + $index' ./oci-cloud-controller-manager-rbac_patched.yaml &&\
mv -v ./oci-01-ccm-01-rbac_*.yml ${INSTALL_DIR}/manifests/
```

- Patch the CCM DaemonSet manifest setting the namespace, append the tolerations,
  and add env vars for the kube API URL used in OpenShift:

<!-- TODO: create the expression to merge both paths into a single yq statement. -->

```sh
cat <<EOF > ./oci-cloud-controller-manager-ds_patch1.yaml
metadata:
  namespace: $OCI_CCM_NAMESPACE
spec:
  template:
    spec:
      tolerations:
        - key: node.kubernetes.io/not-ready
          operator: Exists
          effect: NoSchedule
EOF

# Create the containers' env patch
cat <<EOF > ./oci-cloud-controller-manager-ds_patch2.yaml
spec:
  template:
    spec:
      containers:
        - env:
          - name: KUBERNETES_PORT
            value: "tcp://api-int.$CLUSTER_NAME.$BASE_DOMAIN:6443"
          - name: KUBERNETES_PORT_443_TCP
            value: "tcp://api-int.$CLUSTER_NAME.$BASE_DOMAIN:6443"
          - name: KUBERNETES_PORT_443_TCP_ADDR
            value: "api-int.$CLUSTER_NAME.$BASE_DOMAIN"
          - name: KUBERNETES_PORT_443_TCP_PORT
            value: "6443"
          - name: KUBERNETES_PORT_443_TCP_PROTO
            value: "tcp"
          - name: KUBERNETES_SERVICE_HOST
            value: "api-int.$CLUSTER_NAME.$BASE_DOMAIN"
          - name: KUBERNETES_SERVICE_PORT
            value: "6443"
          - name: KUBERNETES_SERVICE_PORT_HTTPS
            value: "6443"
EOF

# Merge required objects for the pod's template spec
./yq eval-all '. as $item ireduce ({}; . *+ $item)' oci-cloud-controller-manager.yaml oci-cloud-controller-manager-ds_patch1.yaml > oci-cloud-controller-manager-ds_patched1.yaml

# Merge required objects for the pod's containers spec
./yq eval-all '.spec.template.spec.containers[] as $item ireduce ({}; . *+ $item)' oci-cloud-controller-manager-ds_patched1.yaml ./oci-cloud-controller-manager-ds_patch2.yaml > ./oci-cloud-controller-manager-ds_patched2.yaml

# merge patches to ${INSTALL_DIR}/manifests/oci-01-ccm-02-daemonset.yaml
./yq eval-all '.spec.template.spec.containers[] *= load("./oci-cloud-controller-manager-ds_patched2.yaml")' oci-cloud-controller-manager-ds_patched1.yaml > ${INSTALL_DIR}/manifests/oci-01-ccm-02-daemonset.yaml
```

The following CCM manifest files must be created in the installation `manifests/` directory:

```sh
$ tree $INSTALL_DIR/manifests/
[...]
├── oci-00-ccm-namespace.yaml
├── oci-01-ccm-00-secret.yaml
├── oci-01-ccm-01-rbac_0.yml
├── oci-01-ccm-01-rbac_1.yml
├── oci-01-ccm-01-rbac_2.yml
├── oci-01-ccm-02-daemonset.yaml
[...]
```

#### Create custom manifests for Kubelet

The Kubelet parameter `providerID` is the unique identifier of the instance in OCI.
It must be set before the node is initialized by CCM using a custom MachineConfig.

The Provider ID must be set dynamically for each node. The steps below describe
how to create a MachineConfig object to create a systemd unit to create a kubelet
configuration discovering the Provider ID in OCI by querying the
[Instance Metadata Service (IMDS)](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/gettingmetadata.htm).

Steps:

- Create the butane files for master and worker configurations:

```sh
function create_machineconfig_kubelet() {
    local node_role=$1
    cat << EOF > ./mc-kubelet-$node_role.bu
variant: openshift
version: 4.13.0
metadata:
  name: 00-$node_role-kubelet-providerid
  labels:
    machineconfiguration.openshift.io/role: $node_role
storage:
  files:
  - mode: 0755
    path: "/usr/local/bin/kubelet-providerid"
    contents:
      inline: |
        #!/bin/bash
        set -e -o pipefail
        NODECONF=/etc/systemd/system/kubelet.service.d/20-providerid.conf
        if [ -e "\${NODECONF}" ]; then
            echo "Not replacing existing \${NODECONF}"
            exit 0
        fi

        PROVIDERID=\$(curl -H "Authorization: Bearer Oracle" -sL http://169.254.169.254/opc/v2/instance/ | jq -r .id);

        cat > "\${NODECONF}" <<EOF
        [Service]
        Environment="KUBELET_PROVIDERID=\${PROVIDERID}"
        EOF
systemd:
  units:
  - name: kubelet-providerid.service
    enabled: true
    contents: |
      [Unit]
      Description=Fetch kubelet provider id from Metadata
      After=NetworkManager-wait-online.service
      Before=kubelet.service
      [Service]
      ExecStart=/usr/local/bin/kubelet-providerid
      Type=oneshot
      [Install]
      WantedBy=network-online.target
EOF
}

create_machineconfig_kubelet "master"
create_machineconfig_kubelet "worker"
```

- Process the butane files to `MachineConfig` objects:

```sh
function process_butane() {
    local src_file=$1; shift
    local dest_file=$1

    ./butane $src_file -o $dest_file
}

process_butane "./mc-kubelet-master.bu" "${INSTALL_DIR}/openshift/99_openshift-machineconfig_00-master-kubelet-providerid.yaml"
process_butane "./mc-kubelet-worker.bu" "${INSTALL_DIR}/openshift/99_openshift-machineconfig_00-worker-kubelet-providerid.yaml"
```

The MachineConfig files must exist:

```sh
ls ${INSTALL_DIR}/openshift/99_openshift-machineconfig_00-*-kubelet-providerid.yaml
```

### Create ignition files

Once the manifests are placed, you can create the cluster ignition configurations:

~~~bash
openshift-install create ignition-configs --dir $INSTALL_DIR
~~~

The ignition files must be generated in the install directory (files with extension `*.ign`):

```text
$ tree $INSTALL_DIR
/path/to/install-dir
├── auth
│   ├── kubeadmin-password
│   └── kubeconfig
├── bootstrap.ign
├── master.ign
├── metadata.json
└── worker.ign
```

## Section 3. Create the cluster

The first part of this section describes how to create the compute nodes and dependencies,
once the instances are provisioned, the bootstrap will initialize the control plane, and then
when control plane nodes join the cluster, are initialized by CCM, and the control plane
workloads scheduled, the bootstrap will be completed.

The second part describes how to approve the CSR for worker nodes, and to review
the cluster installation.

### Cluster nodes

Every node role uses different ignition files. The following table shows which
ignition file is required for each node role:

| Node Name  | Ignition file | Fetch source |
| -- | -- | -- |
| bootstrap | `${PWD}/user-data-bootstrap.json` | Preauthenticated URL |
| control planes nodes (pool) | `${INSTALL_DIR}/master.json` | Internal Load Balancer (MCS) |
| compute nodes (pool) | `${INSTALL_DIR}/worker.json` | Internal Load Balancer (MCS) |

Run the following commands to populate the values for the environment variables required to create instances:

- `IMAGE_ID`: Custom RHCOS image previously uploaded.
- `SUBNET_ID_PUBLIC`: Public regional subnet used in bootstrap.
- `SUBNET_ID_PRIVATE`: Private regional subnet used to create control plane and compute nodes.
- `NSG_ID_CPL`: Network Security Group ID used in Control Planes

```sh
# Gather subnet IDs
SUBNET_ID_PUBLIC=$(oci network subnet list --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  | jq -r '.data[] | select(.["display-name"] | endswith("public")).id')

SUBNET_ID_PRIVATE=$(oci network subnet list --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  | jq -r '.data[] | select(.["display-name"] | endswith("private")).id')

# Gather the Network Security group for the control plane
NSG_ID_CPL=$(oci network nsg list -c $COMPARTMENT_ID_OPENSHIFT \
  | jq -r '.data[] | select(.["display-name"] | endswith("controlplane")).id')

NSG_ID_CMP=$(oci network nsg list -c $COMPARTMENT_ID_OPENSHIFT \
  | jq -r '.data[] | select(.["display-name"] | endswith("compute")).id')
```

!!! warning "Check if required variables have values before proceeding"
    ```
    cat <<EOF>/dev/stdout
    COMPARTMENT_ID_OPENSHIFT=$COMPARTMENT_ID_OPENSHIFT
    SUBNET_ID_PUBLIC=$SUBNET_ID_PUBLIC
    SUBNET_ID_PRIVATE=$SUBNET_ID_PRIVATE
    NSG_ID_CPL=$NSG_ID_CPL
    EOF
    ```

!!! tip "Helper - OCI CLI documentation"
    - [`oci compute image list`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.29.1/oci_cli_docs/cmdref/compute/image/list.html)
    - [`oci network subnet list`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.29.1/oci_cli_docs/cmdref/network/subnet/list.html)
    - [`oci network nsg list`](#)

#### Upload the RHCOS image

The image used in this guide is QCOW2. The `openshift-install` command
provides the option `coreos print-stream-json` to show all the available
artifacts. The steps below describe how to download the image, upload it to
an OCI bucket, and then create a custom image.

- Get the image name to be used in later steps:
```sh
IMAGE_NAME=$(basename $(openshift-install coreos print-stream-json | jq -r '.architectures["x86_64"].artifacts["openstack"].formats["qcow2.gz"].disk.location'))
```

- Download the `QCOW2` image:
```sh
wget $(openshift-install coreos print-stream-json | jq -r '.architectures["x86_64"].artifacts["openstack"].formats["qcow2.gz"].disk.location')
```

- Create the bucket:
```sh
BUCKET_NAME="${CLUSTER_NAME}-infra"
oci os bucket create --name $BUCKET_NAME --compartment-id $COMPARTMENT_ID_OPENSHIFT
```

!!! tip "Helper - OCI CLI documentation"
    - [`oci os bucket create`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.29.1/oci_cli_docs/cmdref/os/bucket/create.html)

    OCI Console path: `Menu > Storage > Buckets > (Choose the Compartment `openshift`) > Create Bucket`

- Upload the image to OCI Bucket:
```sh
oci os object put -bn $BUCKET_NAME --name images/${IMAGE_NAME} --file ${IMAGE_NAME}
```

!!! tip "Helper - OCI CLI documentation"
    - [`oci os object put`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.29.1/oci_cli_docs/cmdref/os/object/put.html)

    OCI Console path: `Menu > Storage > Buckets > (Choose the Compartment `openshift`) > (Choose the Bucket `openshift-infra`) > Objects > Upload`

- Import to the Instance Image service:
```sh
STORAGE_NAMESPACE=$(oci os ns get | jq -r .data)
oci compute image import from-object -bn $BUCKET_NAME --name images/${IMAGE_NAME} \
    --compartment-id $COMPARTMENT_ID_OPENSHIFT -ns $STORAGE_NAMESPACE \
    --display-name ${IMAGE_NAME} --launch-mode "PARAVIRTUALIZED" \
    --source-image-type "QCOW2"

# Gather the Custom Compute image for RHCOS
IMAGE_ID=$(oci compute image list --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  --display-name $IMAGE_NAME | jq -r '.data[0].id')
```
!!! tip "Helper"
    OCI CLI documentation for [`oci compute image import`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.29.1/oci_cli_docs/cmdref/compute/image/import/from-object.html)

    OCI CLI documentation for [`oci os ns get`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.29.1/oci_cli_docs/cmdref/os/ns/get.html)

#### Bootstrap

The bootstrap node is responsible for creating the temporary control plane and serve
the ignition files to other nodes through the MCS.

The OCI user data has a size limitation that prevents to use of the bootstrap
ignition file directly when launching the node. A new ignition file will be
created replacing it with a remote URL fetching from the temporary Bucket Object URL.

Once the bootstrap instance is created, it must be attached to the load balancer in the
Backend Sets of Kubernetes API Server and Machine Config Server.

Steps:

- Upload the `bootstrap.ign` to the infrastructure bucket

```sh
oci os object put -bn $BUCKET_NAME --name bootstrap-${CLUSTER_NAME}.ign \
    --file $INSTALL_DIR/bootstrap.ign
```

!!! tip "Helper"
    OCI CLI documentation for [`oci os object put`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.29.1/oci_cli_docs/cmdref/os/object/put.html)


- Generate the pre-authenticated request to generate a unique URL used by the bootstrap to access the ignition file stored in the OCI object store:

!!! warning "Attention"
    The bucket object URL will expire in one hour if you are planning to create
    the bootstrap later, please adjust the `$EXPIRES_TIME`.

    The install certificates expire 24 hours after the ignition files have been
    created, consider regenerating it if the ignitions are older than that.

```sh
EXPIRES_TIME=$(date -d '+1 hour' --rfc-3339=seconds)
IGN_BOOTSTRAP_URL=$(oci os preauth-request create --name bootstrap-${CLUSTER_NAME} \
    -bn $BUCKET_NAME -on bootstrap-${CLUSTER_NAME}.ign \
    --access-type ObjectRead  --time-expires "$EXPIRES_TIME" \
    | jq -r '.data["full-path"]')
```

!!! tip "Helper"
    OCI CLI documentation for [`oci os preauth-request create`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.29.0/oci_cli_docs/cmdref/os/preauth-request/create.html)

The generated URL for the ignition file `bootstrap.ign` must be available in the `$IGN_BOOTSTRAP_URL`.

- Create the ignition file to boot the bootstrap node, pointing to the remote ignition source:

```sh
cat <<EOF > ./user-data-bootstrap.json
{
  "ignition": {
    "config": {
      "replace": {
        "source": "${IGN_BOOTSTRAP_URL}"
      }
    },
    "version": "3.1.0"
  }
}
EOF
```

- Launch the instance for the bootstrap:

```sh
AVAILABILITY_DOMAIN="gzqB:US-SANJOSE-1-AD-1"
INSTANCE_SHAPE="VM.Standard.E4.Flex"

oci compute instance launch \
    --hostname-label "bootstrap" \
    --display-name "bootstrap" \
    --availability-domain "$AVAILABILITY_DOMAIN" \
    --fault-domain "FAULT-DOMAIN-1" \
    --compartment-id $COMPARTMENT_ID_OPENSHIFT \
    --subnet-id $SUBNET_ID_PUBLIC \
    --nsg-ids "[\"$NSG_ID_CPL\"]" \
    --shape "$INSTANCE_SHAPE" \
    --shape-config "{\"memoryInGBs\":16.0,\"ocpus\":8.0}" \
    --source-details "{\"bootVolumeSizeInGBs\":120,\"bootVolumeVpusPerGB\":60,\"imageId\":\"${IMAGE_ID}\",\"sourceType\":\"image\"}" \
    --agent-config '{"areAllPluginsDisabled": true}' \
    --assign-public-ip True \
    --user-data-file "./user-data-bootstrap.json" \
    --defined-tags "{\"$CLUSTER_NAME\":{\"role\":\"master\"}}"
```

!!! tip "Helper - OCI CLI documentation"
    - [`oci compute instance launch`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.29.1/oci_cli_docs/cmdref/compute/instance/launch.html)
    - [`oci compute shape list`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.29.1/oci_cli_docs/cmdref/compute/shape/list.html)

!!! tip "Follow the bootstrap process"
    You can SSH to the node and follow the bootstrap process:
    `journalctl -b -f -u release-image.service -u bootkube.service`


- Discover the load balancer's backend sets and the bootstrap instance IDs:

```sh
BES_API_NAME=$(oci nlb backend-set list --network-load-balancer-id $NLB_ID | jq -r '.data.items[] | select(.name | endswith("api")).name')
BES_MCS_NAME=$(oci nlb backend-set list --network-load-balancer-id $NLB_ID | jq -r '.data.items[] | select(.name | endswith("mcs")).name')

INSTANCE_ID_BOOTSTRAP=$(oci compute instance list  -c $COMPARTMENT_ID_OPENSHIFT | jq -r '.data[] | select((.["display-name"]=="bootstrap") and (.["lifecycle-state"]=="RUNNING")).id')

test -z $INSTANCE_ID_BOOTSTRAP && echo "ERR: Bootstrap Instance ID not found=[$INSTANCE_ID_BOOTSTRAP]. Try again."
```

!!! tip "Helper - OCI CLI documentation"
    - [`oci nlb network-load-balancer list`]()
    - [`oci nlb backend-set list`]()
    - [`oci compute instance list`]()

- Attach the bootstrap instance to the "API" backend set:

```sh
# oci nlb backend-set update --generate-param-json-input backends
cat <<EOF > ./nlb-bset-backends-api.json
[
  {
    "isBackup": false,
    "isDrain": false,
    "isOffline": false,
    "name": "${INSTANCE_ID_BOOTSTRAP}:6443",
    "port": 6443,
    "targetId": "${INSTANCE_ID_BOOTSTRAP}"
  }
]
EOF

# Update API Backend Set
oci nlb backend-set update --force \
  --backend-set-name $BES_API_NAME \
  --network-load-balancer-id $NLB_ID \
  --backends file://nlb-bset-backends-api.json \
  --wait-for-state SUCCEEDED
```

!!! tip "Helper - OCI CLI documentation"
    - [`oci nlb backend-set update`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.29.1/oci_cli_docs/cmdref/nlb/backend-set/update.html)

- Attach the bootstrap instance to the "MCS" backend set:

```sh
cat <<EOF > ./nlb-bset-backends-mcs.json
[
  {
    "isBackup": false,
    "isDrain": false,
    "isOffline": false,
    "name": "${INSTANCE_ID_BOOTSTRAP}:22623",
    "port": 22623,
    "targetId": "${INSTANCE_ID_BOOTSTRAP}"
  }
]
EOF

oci nlb backend-set update --force \
  --backend-set-name $BES_MCS_NAME \
  --network-load-balancer-id $NLB_ID \
  --backends file://nlb-bset-backends-mcs.json \
  --wait-for-state SUCCEEDED
```

#### Control Plane

Three control plane instances will be created. The instances is created using
[Instance Pool](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/creatinginstancepool.htm), which will automatically inherit the same configuration and attach
to the required listeners: API and MCS.

- Creating the instance configuration required by the instance pool:

```sh
INSTANCE_CONFIG_CONTROLPLANE="${CLUSTER_NAME}-controlplane"
# To generate all the options:
# oci compute-management instance-configuration create --generate-param-json-input instance-details
cat <<EOF > ./instance-config-details-controlplanes.json
{
  "instanceType": "compute",
  "launchDetails": {
    "agentConfig": {"areAllPluginsDisabled": true},
    "compartmentId": "$COMPARTMENT_ID_OPENSHIFT",
    "createVnicDetails": {
      "assignPrivateDnsRecord": true,
      "assignPublicIp": false,
      "nsgIds": ["$NSG_ID_CPL"],
      "subnetId": "$SUBNET_ID_PRIVATE"
    },
    "definedTags": {
      "$CLUSTER_NAME": {
        "role": "master"
      }
    },
    "displayName": "${CLUSTER_NAME}-controlplane",
    "launchMode": "PARAVIRTUALIZED",
    "metadata": {"user_data": "$(base64 -w0 < $INSTALL_DIR/master.ign)"},
    "shape": "$INSTANCE_SHAPE",
    "shapeConfig": {"memoryInGBs":16.0,"ocpus":8.0},
    "sourceDetails": {"bootVolumeSizeInGBs":120,"bootVolumeVpusPerGB":60,"imageId":"${IMAGE_ID}","sourceType":"image"}
  }
}
EOF

oci compute-management instance-configuration create \
  --display-name "$INSTANCE_CONFIG_CONTROLPLANE" \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  --instance-details file://instance-config-details-controlplanes.json
```

- Creating the instance pool:

```sh
INSTANCE_POOL_CONTROLPLANE="${CLUSTER_NAME}-controlplane"
INSTANCE_CONFIG_ID_CPL=$(oci compute-management instance-configuration list \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  | jq -r ".data[] | select(.[\"display-name\"] | startswith(\"$INSTANCE_CONFIG_CONTROLPLANE\")).id")

#
# oci compute-management instance-pool create --generate-param-json-input load-balancers
cat <<EOF > ./instance-pool-loadbalancers-cpl.json
[
  {
    "backendSetName": "$BES_API_NAME",
    "loadBalancerId": "$NLB_ID",
    "port": 6443,
    "vnicSelection": "PrimaryVnic"
  },
  {
    "backendSetName": "$BES_MCS_NAME",
    "loadBalancerId": "$NLB_ID",
    "port": 22623,
    "vnicSelection": "PrimaryVnic"
  }
]
EOF

# oci compute-management instance-pool create --generate-param-json-input placement-configurations
cat <<EOF > ./instance-pool-placement.json
[
  {
    "availabilityDomain": "$AVAILABILITY_DOMAIN",
    "faultDomains": ["FAULT-DOMAIN-1","FAULT-DOMAIN-2","FAULT-DOMAIN-3"],
    "primarySubnetId": "$SUBNET_ID_PRIVATE",
  }
]
EOF

oci compute-management instance-pool create \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  --instance-configuration-id "$INSTANCE_CONFIG_ID_CPL" \
  --size 0 \
  --display-name "$INSTANCE_POOL_CONTROLPLANE" \
  --placement-configurations "file://instance-pool-placement.json" \
  --load-balancers file://instance-pool-loadbalancers-cpl.json
```

!!! tip "Helper - OCI CLI documentation"
    - [`oci compute-management instance-pool create`](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.35.0/oci_cli_docs/cmdref/compute-management/instance-pool/create.html)

- Scale up (alternatively the `--size` can be adjusted when creating the Instance Pool):

```sh
INSTANCE_POOL_ID_CPL=$(oci compute-management instance-pool list \
    --compartment-id  $COMPARTMENT_ID_OPENSHIFT \
    | jq -r ".data[] | select(
        (.[\"display-name\"]==\"$INSTANCE_POOL_CONTROLPLANE\") and
        (.[\"lifecycle-state\"]==\"RUNNING\")
    ).id")

oci compute-management instance-pool update --instance-pool-id $INSTANCE_POOL_ID_CPL --size 3
```

!!! tip "Helper - OCI CLI documentation"
    - [`oci compute-management instance-pool update `](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.35.0/oci_cli_docs/cmdref/compute-management/instance-pool/update.html)

#### Compute/workers

- Creating the instance configuration:

```sh
INSTANCE_CONFIG_COMPUTE="${CLUSTER_NAME}-compute"

# oci compute-management instance-configuration create --generate-param-json-input instance-details
cat <<EOF > ./instance-config-details-compute.json
{
  "instanceType": "compute",
  "launchDetails": {
    "agentConfig": {"areAllPluginsDisabled": true},
    "compartmentId": "$COMPARTMENT_ID_OPENSHIFT",
    "createVnicDetails": {
      "assignPrivateDnsRecord": true,
      "assignPublicIp": false,
      "nsgIds": ["$NSG_ID_CMP"],
      "subnetId": "$SUBNET_ID_PRIVATE"
    },
    "definedTags": {
      "$CLUSTER_NAME": {
        "role": "worker"
      }
    },
    "displayName": "${CLUSTER_NAME}-worker",
    "launchMode": "PARAVIRTUALIZED",
    "metadata": {"user_data": "$(base64 -w0 < $INSTALL_DIR/worker.ign)"},
    "shape": "$INSTANCE_SHAPE",
    "shapeConfig": {"memoryInGBs":16.0,"ocpus":8.0},
    "sourceDetails": {"bootVolumeSizeInGBs":120,"bootVolumeVpusPerGB":20,"imageId":"${IMAGE_ID}","sourceType":"image"}
  }
}
EOF

oci compute-management instance-configuration create \
  --display-name "$INSTANCE_CONFIG_COMPUTE" \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  --instance-details file://instance-config-details-compute.json
```

- Creating the instance pool:

```sh
INSTANCE_POOL_COMPUTE="${CLUSTER_NAME}-compute"
INSTANCE_CONFIG_ID_CMP=$(oci compute-management instance-configuration list \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  | jq -r ".data[] | select(.[\"display-name\"] | startswith(\"$INSTANCE_CONFIG_COMPUTE\")).id")

BES_HTTP_NAME=$(oci nlb backend-set list --network-load-balancer-id $NLB_ID \
  | jq -r '.data.items[] | select(.name | endswith("http")).name')
BES_HTTPS_NAME=$(oci nlb backend-set list --network-load-balancer-id $NLB_ID \
  | jq -r '.data.items[] | select(.name | endswith("https")).name')

#
# oci compute-management instance-pool create --generate-param-json-input load-balancers
cat <<EOF > ./instance-pool-loadbalancers-cmp.json
[
  {
    "backendSetName": "$BES_HTTP_NAME",
    "loadBalancerId": "$NLB_ID",
    "port": 80,
    "vnicSelection": "PrimaryVnic"
  },
  {
    "backendSetName": "$BES_HTTPS_NAME",
    "loadBalancerId": "$NLB_ID",
    "port": 443,
    "vnicSelection": "PrimaryVnic"
  }
]
EOF

oci compute-management instance-pool create \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  --instance-configuration-id "$INSTANCE_CONFIG_ID_CMP" \
  --size 0 \
  --display-name "$INSTANCE_POOL_COMPUTE" \
  --placement-configurations "[{\"availabilityDomain\":\"$AVAILABILITY_DOMAIN\",\"faultDomains\":[\"FAULT-DOMAIN-1\",\"FAULT-DOMAIN-2\",\"FAULT-DOMAIN-3\"],\"primarySubnetId\":\"$SUBNET_ID_PRIVATE\"}]" \
  --load-balancers file://instance-pool-loadbalancers-cmp.json
```

- Scale up the compute nodes:

```sh
INSTANCE_POOL_ID_CMP=$(oci compute-management instance-pool list \
    --compartment-id  $COMPARTMENT_ID_OPENSHIFT \
    | jq -r ".data[] | select(
        (.[\"display-name\"]==\"$INSTANCE_POOL_COMPUTE\") and
        (.[\"lifecycle-state\"]==\"RUNNING\")
    ).id")

oci compute-management instance-pool update --instance-pool-id $INSTANCE_POOL_ID_CMP --size 2
```

### Review the installation

Export the kubeconfig:

```sh
export KUBECONFIG=$INSTALL_DIR/auth/kubeconfig
```

#### OCI Cloud Controller Manager

- Check if the CCM pods have been started and nodes initialized:

```sh
oc logs -f daemonset.apps/oci-cloud-controller-manager -n oci-cloud-controller-manager


```

Example output:

```
I0816 04:22:12.019529       1 node_controller.go:484] Successfully initialized node inst-rdlw6-demo-oci-003-controlplane.priv.ocp.oraclevcn.com with cloud provider
```

- Check if the nodes have been initialized:

```sh
oc get nodes
```

- Check if the controllers are running for each master:

```sh
oc get all -n oci-cloud-controller-manager
```

#### Approve certificates for compute nodes

When you add machines to a cluster, two pending certificate signing requests (CSRs) are generated for each machine that you added. You must confirm that these CSRs are approved or, if necessary, approve them yourself. The client requests must be approved first, followed by the server requests.

Check the pending certificates using `oc get csr -w`, then approve those by running:

```sh
oc adm certificate approve $(oc get csr  -o json | jq -r '.items[] | select(.status.certificate == null).metadata.name')
```

Observe the nodes joining in the cluster by running: `oc get nodes -w`.

#### Wait for Bootstrap to complete

Check if you can remove the bootstrap instance when the control plane
nodes have been up and running correctly. You can check by running
the following command:

```sh
openshift-install --dir $INSTALL_DIR wait-for bootstrap-complete
```

Example output:
```text
INFO It is now safe to remove the bootstrap resources 
INFO Time elapsed: 1s   
```

#### Check installation complete

It is also possible to wait for the installation to complete by using the
`openshift-install` binary:

```sh
openshift-install --dir $INSTALL_DIR wait-for install-complete
```

Example output:

```text
$ openshift-install --dir $INSTALL_DIR wait-for install-complete
INFO Waiting up to 40m0s (until 6:17PM -03) for the cluster at https://api.oci-ext00.mydomain.com:6443 to initialize... 
INFO Checking to see if there is a route at openshift-console/console... 
INFO Install complete!                            
INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/home/me/oci/oci-ext00/auth/kubeconfig' 
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.oci-ext00.mydomain 
INFO Login to the console with user: "kubeadmin", and password: "[super secret]" 
INFO Time elapsed: 2s                             
```

Alternatively, you can watch the cluster operators to follow the installation process:

```sh
watch -n5 oc get clusteroperators
```

The cluster will be ready to use once the operators are stabilized.

If you have issues, you can start exploring the [Throubleshooting Installations page](https://docs.openshift.com/container-platform/4.13/support/troubleshooting/troubleshooting-installations.html).

## Destroy the cluster

This section provides a single script to clean up the resources created by this user guide.

Run the following command to delete the resource considering the dependencies:

```sh
# Compute
## Clean up instances
oci compute instance terminate --force \
  --instance-id $INSTANCE_ID_BOOTSTRAP

oci compute-management instance-pool terminate --force \
  --instance-pool-id $INSTANCE_POOL_ID_CMP \
    --wait-for-state TERMINATED
oci compute-management instance-configuration delete --force \
  --instance-configuration-id $INSTANCE_CONFIG_ID_CMP

oci compute-management instance-pool terminate --force \
  --instance-pool-id $INSTANCE_POOL_ID_CPL \
  --wait-for-state TERMINATED
oci compute-management instance-configuration delete --force \
  --instance-configuration-id $INSTANCE_CONFIG_ID_CPL

## Custom image
oci compute image delete --force --image-id ${IMAGE_ID}

# IAM
## Remove policy
oci iam policy delete --force \
  --policy-id $(oci iam policy list \
    --compartment-id $COMPARTMENT_ID_OPENSHIFT \
    --name $POLICY_NAME | jq -r .data[0].id) \
  --wait-for-state DELETED

## Remove dynamic group
oci iam dynamic-group delete --force \
  --dynamic-group-id $(oci iam dynamic-group list \
    --name $DYNAMIC_GROUP_NAME | jq -r .data[0].id) \
  --wait-for-state DELETED

## Remove tag namespace and key
oci iam tag-namespace retire --tag-namespace-id $TAG_NAMESPACE_ID
oci iam tag-namespace cascade-delete \
  --tag-namespace-id $TAG_NAMESPACE_ID \
  --wait-for-state SUCCEEDED

## Bucket
for RES_ID in $(oci os preauth-request list   --bucket-name "$BUCKET_NAME" | jq -r .data[].id); do
  echo "Deleting Preauth request $RES_ID"
  oci os preauth-request delete --force \
    --bucket-name "$BUCKET_NAME" \
    --par-id "${RES_ID}";
done
oci os object delete --force \
  --bucket-name "$BUCKET_NAME" \
  --object-name "images/${IMAGE_NAME}"
oci os object delete --force \
  --bucket-name "$BUCKET_NAME" \
  --object-name "bootstrap-${CLUSTER_NAME}.ign"
oci os bucket delete --force \
  --bucket-name "$BUCKET_NAME"

# Load Balancer
oci nlb network-load-balancer delete --force \
  --network-load-balancer-id $NLB_ID \
  --wait-for-state SUCCEEDED

# Network and dependencies
for RES_ID in $(oci network subnet list \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  --vcn-id $VCN_ID | jq -r .data[].id); do
  echo "Deleting Subnet $RES_ID"
  oci network subnet delete --force \
    --subnet-id $RES_ID \
    --wait-for-state TERMINATED;
done

for RES_ID in $(oci network nsg list \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  --vcn-id $VCN_ID | jq -r .data[].id); do
  echo "Deleting NSG $RES_ID"
  oci network nsg delete --force \
    --nsg-id $RES_ID \
    --wait-for-state TERMINATED;
done

for RES_ID in $(oci network security-list list \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  --vcn-id $VCN_ID \
  | jq -r '.data[] | select(.["display-name"]  | startswith("Default") | not).id'); do
  echo "Deleting SecList $RES_ID"
  oci network security-list delete --force \
    --security-list-id $RES_ID \
    --wait-for-state TERMINATED;
done

oci network route-table delete --force \
    --wait-for-state TERMINATED \
    --rt-id $(oci network route-table list \
      --compartment-id $COMPARTMENT_ID_OPENSHIFT \
      --vcn-id $VCN_ID \
      | jq -r '.data[] | select(.["display-name"] | endswith("rtb-public")).id')

oci network route-table delete --force \
    --wait-for-state TERMINATED \
    --rt-id $(oci network route-table list \
      --compartment-id $COMPARTMENT_ID_OPENSHIFT \
      --vcn-id $VCN_ID \
      | jq -r '.data[] | select(.["display-name"] | endswith("rtb-private")).id')

for RES_ID in $(oci network nat-gateway list \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  --vcn-id $VCN_ID | jq -r .data[].id); do
  echo "Deleting NATGW $RES_ID"
  oci network nat-gateway delete --force \
    --nat-gateway-id $RES_ID \
    --wait-for-state TERMINATED;
done

for RES_ID in $(oci network internet-gateway list \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  --vcn-id $VCN_ID | jq -r .data[].id); do
  echo "Deleting IGW $RES_ID"
  oci network internet-gateway delete --force \
    --ig-id $RES_ID \
    --wait-for-state TERMINATED;
done

oci network vcn delete --force \
  --vcn-id $VCN_ID \
  --wait-for-state TERMINATED

# Compartment
oci iam compartment delete --force \
  --compartment-id $COMPARTMENT_ID_OPENSHIFT \
  --wait-for-state SUCCEEDED
```

## Summary

This guide walked through an OpenShift deployment on Oracle Cloud Infrastructure, a non-integrated provider, using the feature Platform External introduced in 4.14. The feature allows an initial integration with OCI without needing to change the OpenShift code base.

It will also open the possibility to quickly deploy cloud provider components natively, like CSI drivers, which mostly require extra setup with CCM.

## Next steps

- [Validating an installation](https://docs.openshift.com/container-platform/4.13/installing/validating-an-installation.html#validating-an-installation)
- [Running conformance tests in non-integrated providers](./conformance-tests-opct.md)