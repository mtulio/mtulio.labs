# cloud-iac

Cloud Infra as a Code.

## Usage

### Create network stack only (from k8s template)

```bash
$(which time) -v make k8s-create-network-aws-use1
```

### Create an OpenShift cluster on AWS (UPI)

```bash
CONFIG_CLUSTER_NAME=mrbupi \
    $(which time) -v make openshift-install INSTALL_DIR=${PWD}/.install-dir-upi
```

### Create an OpenShift cluster on AWS with no integration (platform=None)

Create the cluster:
```bash
INSTALL_DIR="${PWD}/.install-dir-none"
make clean INSTALL_DIR=${INSTALL_DIR}
CONFIG_CLUSTER_NAME=mrbnone \
    EXTRA_ARGS='-e custom_image_id=ami-0a57c1b4939e5ef5b -e config_platform="" -vvv' \
    $(which time) -v make openshift-install INSTALL_DIR=${INSTALL_DIR}
```

- Approve the certificates to Compute nodes join to the cluster
```bash
for i in $(oc --kubeconfig ${PWD}/.install-dir-none/auth/kubeconfig get csr --no-headers | grep -i pending |  awk '{ print $1 }'); do oc --kubeconfig ${PWD}/.install-dir-none/auth/kubeconfig adm certificate approve $i; done
```

Create the ingress Load Balancers on AWS:

```bash
$(which time) -v make openshift-stack-loadbalancers-none INSTALL_DIR=${INSTALL_DIR}
```

Check the COs

```
oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig get co -w
```

Destroy a cluster:

```bash
# Destroy the ingress LB first
make openshift-destroy INSTALL_DIR=${INSTALL_DIR} PROVIDER=aws-none EXTRA_ARGS='-t loadbalancer'

# Destroy the cluster
INSTALL_DIR="${PWD}/.install-dir-none"
make openshift-destroy INSTALL_DIR=${INSTALL_DIR}
```

### Network

- create AWS VPC

```bash
ansible-playbook net-create.yaml \
    -e provider=aws \
    -e name=k8s
```
