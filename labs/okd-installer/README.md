# okd-installer

Ansible Collection OKD Installer use cases.

## Install okd-installer collection


## Use cases

### OPCT Cluster Management

#### Default AWS Cluster

- Create Cluster AWS with version 4.12.0-rc.4

```bash
ansible-playbook opct-cluster-create-aws.yaml -e cluster_name=opct22122301 -e cluster_version=4.12.0-rc.4
```

- Approve certs if still pending CSRs (oc get csr)

```bash
ansible-playbook mtulio.okd_installer.approve_certs -e cluster_name=opct22122304
```

- Enable Image Registry with emptyDir as persistent storage

> It should be enabled when the cluster is installed with flag `create_registry=yes` 

```bash
ansible-playbook mtulio.okd_installer.create_imageregistry \
    -e config_install_dir="${HOME}/.ansible/okd-installer/clusters/opct22122304"
```

- Delete Cluster AWS

```bash
ansible-playbook opct-cluster-delete-aws.yaml -e cluster_name=opct22122301
```

To customize the variables, like AWS region, edit the group `opct_aws` in the inventory file [./inventories/local.yaml](./inventories/local.yaml).

#### AWS Cluster Single AZ


```bash
ansible-playbook opct-cluster-create-aws.yaml \
    -e cluster_name=opct22122301 \
    -e cluster_version=4.12.0-rc.4 \
    -e topology_network=single-AZ \
    -e topology_compute=single-AZ
```

#### Running in Contianer

- Build the container

```bash
podman build -t opct-runner:latest -f hack/opct-runner/Containerfile .
```

- Create the workdir, where the okd-installer will save the environment/state

```bash
mkdir .opct
```

- Create the env file

```bash
cat <<EOF> ./.opct.env
ANSIBLE_UNSAFE_WRITES=1
CONFIG_PULL_SECRET_FILE=/pull-secret.json
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}
EOF
```

- Create the cluster

```bash
podman run \
    --env-file ${PWD}/.opct.env \
    -v ${PWD}/.opct:/root/.ansible/okd-installer:Z \
    -v ${HOME}/.ssh:/root/.ssh:Z \
    -v ${HOME}/.openshift/pull-secret-latest.json:/pull-secret.json \
    --rm opct-runner:latest \
    ansible-playbook opct-cluster-create-aws.yaml \
    -e cluster_name=opct22122901 \
    -e cluster_version=4.12.0-rc.4
```

- Wait the operators to be ready

```bash
podman run \
    --env-file ${PWD}/.opct.env \
    -v ${PWD}/.opct:/root/.ansible/okd-installer:Z \
    --rm opct-runner:latest \
    ansible-playbook opct-wait-for-operators.yaml -e cluster_name=opct22122901
```

- Run OPCT:

***Container***:
```bash
podman run \
    --env-file ${PWD}/.opct.env \
    -v ${PWD}/.opct:/root/.ansible/okd-installer:Z \
    -v ${PWD}/.opct_results:/opct:Z \
    -v ${PWD}/openshift-provider-cert-linux-amd64:/openshift-provider-cert:Z \
    --rm opct-runner:latest \
    ansible-playbook opct-run-tool.yaml -e cluster_name=opct22122901 \
    -e log_pipe=/opct/run.log
```

***Playbook***:
```bash
ansible-playbook opct-run-tool.yaml \
-e cluster_name=opct22122901 \
-e installer_path=${PWD}/.opct \
-e log_pipe=${PWD}/.opct/run.log \
-e opct_bin=${PWD}/openshift-provider-cert-linux-amd64
```

- Delete the cluster

```bash
podman run \
    --env-file ${PWD}/.opct.env \
    -v ${PWD}/.opct:/root/.ansible/okd-installer:Z \
    --rm opct-runner:latest \
    ansible-playbook opct-cluster-delete-aws.yaml \
    -e cluster_name=opct22122903
```


- Single execution

```bash
podman run \
    --env-file ${PWD}/.opct.env \
    -v ${PWD}/.opct:/root/.ansible/okd-installer:Z \
    -v ${HOME}/.ssh:/root/.ssh:Z \
    -v ${HOME}/.openshift/pull-secret-latest.json:/pull-secret.json \
    -v ${PWD}/openshift-provider-cert:/openshift-provider-cert:Z \
    --rm opct-runner:latest \
    ansible-playbook opct-runner-all-aws.yaml \
    -e cluster_name=opct22123001 \
    -e cluster_version=4.11.18 -vvv
```

```bash
ansible-playbook opct-run-tool.yaml \
-e cluster_name=opct22122903 \
-e installer_path=${PWD}/.opct \
-e opct_bin=${PWD}/openshift-provider-cert \
-e skip_prefligth=yes
```
