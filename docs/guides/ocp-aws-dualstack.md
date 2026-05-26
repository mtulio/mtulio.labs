# Installing OpenShift on AWS with Dual-Stack Networking (IPv6 Primary)

Quick guide to install an OpenShift cluster on AWS with dual-stack networking using IPv6 as the primary address family.

## Prerequisites

- OpenShift installer (`openshift-install`) for your target version
- A valid pull secret
- AWS credentials configured
- SSH key pair for node access
- OVN-Kubernetes is required for dual-stack networking

## Steps

### 1. Set environment variables

```bash
export CLUSTER_NAME="ocp-dualstack"
export BASE_DOMAIN="example.com"
export INSTALL_DIR="${HOME}/openshift-labs/${CLUSTER_NAME}"
export AWS_REGION="us-east-1"
```

### 2. Create the install-config

```bash
mkdir -p ${INSTALL_DIR}

cat << EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
metadata:
  name: ${CLUSTER_NAME}
baseDomain: ${BASE_DOMAIN}
platform:
  aws:
    region: ${AWS_REGION}
    ipFamily: DualStackIPv6Primary
networking:
  networkType: OVNKubernetes
  machineNetwork:
    - cidr: 10.0.0.0/16
  clusterNetwork:
    - cidr: fd01::/48
      hostPrefix: 64
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - fd02::/112
    - 172.30.0.0/16
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE})'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
```

!!! note
    The `ipFamily: DualStackIPv6Primary` sets IPv6 as the primary stack. The order of CIDRs in `clusterNetwork` and `serviceNetwork` reflects this: IPv6 ranges come first.

### 3. Back up the install-config

```bash
cp ${INSTALL_DIR}/install-config.yaml \
   ${INSTALL_DIR}/install-config.yaml.bkp
```

### 4. Create the cluster

```bash
openshift-install create cluster \
  --dir ${INSTALL_DIR} \
  --log-level=debug
```

## Verification

### Check node addresses

Nodes should have both IPv4 and IPv6 addresses, with IPv6 listed first:

```bash
oc get nodes -o wide
```

### Check pod networking

```bash
oc get pods -A -o wide | head -20
```

### Check service CIDRs

```bash
oc get network.config cluster -o jsonpath='{.status.serviceNetwork}'
```

Expected output should show both service CIDRs:

```
["fd02::/112","172.30.0.0/16"]
```

### Check cluster network

```bash
oc get network.config cluster -o jsonpath='{.status.clusterNetwork}'
```

### Verify OVN-Kubernetes

```bash
oc get network.operator cluster -o jsonpath='{.spec.defaultNetwork.ovnKubernetesConfig}' | jq .
```

## Troubleshooting

- **Installer fails with unsupported region**: Not all AWS regions support IPv6 in all availability zones. Try a region with broad IPv6 support (e.g., `us-east-1`).
- **Pods stuck in ContainerCreating**: Check OVN-Kubernetes pods in `openshift-ovn-kubernetes` namespace for errors related to IPv6 address allocation.
- **Services unreachable over IPv6**: Ensure security groups allow IPv6 traffic. Check with `oc get svc -A` to verify dual-stack ClusterIPs are assigned.

## Cleanup

```bash
openshift-install destroy cluster \
  --dir ${INSTALL_DIR} \
  --log-level=debug
```

## References

- [OpenShift Networking: OVN-Kubernetes dual-stack](https://docs.openshift.com/container-platform/latest/networking/ovn_kubernetes_network_provider/configuring-egress-ips-ovn.html)
- [AWS VPC dual-stack](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-ip-addressing.html)
