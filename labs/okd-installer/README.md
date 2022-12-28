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
