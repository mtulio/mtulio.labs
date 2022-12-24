# okd-installer

Ansible Collection OKD Installer use cases.

## OPCT Cluster Management

### Default AWS Cluster

- Create Cluster AWS with version 4.12.0-rc.4

```bash
ansible-playbook opct-cluster-create-aws.yaml -e cluster_name=opct22122301 -e cluster_version=4.12.0-rc.4
```

- Delete Cluster AWS

```bash
ansible-playbook opct-cluster-delete-aws.yaml -e cluster_name=opct22122301
```

To customize the variables, like AWS region, edit the group `opct_aws` in the inventory file [./inventories/local.yaml](./inventories/local.yaml).

