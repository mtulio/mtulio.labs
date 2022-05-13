# cloud-iac

Cloud Infra as a Code.

## Setup

Clone the project
```bash
git clone -b cloud-iac --recursive git@github.com:mtulio/mtulio.labs.git cloud-iac
cd cloud-iac/labs/
```

## Usage

### Export the environment variables used to create the cluster

Create `.env` file or just export it to your session:
```bash
cat <<EOF> .env
export CONFIG_BASE_DOMAIN=mydomain.openshift.com
export CONFIG_CLUSTER_NAME=mrbans
export CONFIG_REGION=us-east-1
export CONFIG_PULL_SECRET_FILE=/home/mtulio/.openshift/pull-secret-latest.json
export CONFIG_SSH_KEY="$(cat ~/.ssh/id_rsa.pub)"
EOF
```

Load it:
```bash
source .env
```

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
for i in $(oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig \
            get csr --no-headers    | \
            grep -i pending         | \
            awk '{ print $1 }')     ; do \
    oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig \
        adm certificate approve $i; \
done
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

### Create an OpenShift cluster on DigitalOcean with no integration (platform=None)

Authentication:
- Create an [Token](https://cloud.digitalocean.com/account/api/tokens)
- Export it: `export DO_API_TOKEN=value`
- Alternatively, setup the CLI](https://docs.digitalocean.com/reference/doctl/how-to/install/)
- Install ansible collection for DO
- Install the collection (it's constantly updating)
```
ansible-galaxy collection install community.digitalocean
```

Targets available:
- Gen Config
```bash
INSTALL_DIR="${PWD}/.install-dir-mrbdo"
make clean INSTALL_DIR=${INSTALL_DIR}
CONFIG_CLUSTER_NAME=mrbdo \
    CONFIG_PROVIDER="do" \
    INSTALL_DIR="${INSTALL_DIR}" \
    CONFIG_REGION="nyc3" \
    EXTRA_ARGS='-e custom_image_id=fedora-coreos-34.20210626.3.1-digitalocean.x86_64.qcow2.gz -e config_platform="" -vvv' \
    CONFIG_BASE_DOMAIN="splat-do.devcluster.openshift.com" \
    $(which time) -v make openshift-config
```

- Config load
```bash
CONFIG_CLUSTER_NAME=mrbdo \
    CONFIG_PROVIDER="do" \
    INSTALL_DIR="${PWD}/.install-dir-mrbdo" \
    CONFIG_REGION="nyc3" \
    EXTRA_ARGS='-e config_platform="" -vvv' \
    $(which time) -v make openshift-config-load
```

- Create Network Stack
```bash
CONFIG_CLUSTER_NAME=mrbdo \
    CONFIG_PROVIDER="do" \
    INSTALL_DIR="${PWD}/.install-dir-mrbdo" \
    CONFIG_REGION="nyc3" \
    EXTRA_ARGS="-e config_platform="" -vvv -e region=${CONFIG_REGION}" \
    $(which time) -v make openshift-stack-network
```

- Create DNS
```bash
CONFIG_CLUSTER_NAME=mrbdo \
    CONFIG_PROVIDER="do" \
    INSTALL_DIR="${PWD}/.install-dir-mrbdo" \
    CONFIG_REGION="nyc3" \
    EXTRA_ARGS='-e config_platform="" -vvv' \
    $(which time) -v make openshift-stack-dns
```


- Create Load Balancers
> DO LB is limited the HC by LB, not rule, so it can be a problem
> when specific service goes down. Recommened is to create one LB by
> rule with proper health check (not cover here)
```bash
CONFIG_CLUSTER_NAME=mrbdo \
    CONFIG_PROVIDER="do" \
    INSTALL_DIR="${PWD}/.install-dir-mrbdo" \
    CONFIG_REGION="nyc3" \
    EXTRA_ARGS='-e config_platform="" -vvv' \
    $(which time) -v make openshift-stack-loadbalancers
```


- Bootstrap setup
> ny{1,2} region is crashing on Spaces API.
```bash
CONFIG_CLUSTER_NAME=mrbdo \
    CONFIG_PROVIDER="do" \
    INSTALL_DIR="${PWD}/.install-dir-mrbdo" \
    CONFIG_REGION="nyc3" \
    EXTRA_ARGS='-e config_platform="" -vvv' \
    $(which time) -v make openshift-bootstrap-setup
```

- Bootstrap create
```bash
CONFIG_CLUSTER_NAME=mrbdo \
    CONFIG_PROVIDER="do" \
    INSTALL_DIR="${PWD}/.install-dir-mrbdo" \
    CONFIG_REGION="nyc3" \
    EXTRA_ARGS='-e config_platform="" -vvv' \
    $(which time) -v make openshift-stack-bootstrap
```


- Destroy the resources
```bash
CONFIG_CLUSTER_NAME=mrbdo \
    CONFIG_PROVIDER="do" \
    CONFIG_REGION="nyc3" \
    INSTALL_DIR="${PWD}/.install-dir-mrbdo" \
    EXTRA_ARGS='-vvv' \
    make openshift-destroy
```


### Network

- create AWS VPC

```bash
ansible-playbook net-create.yaml \
    -e provider=aws \
    -e name=k8s
```
