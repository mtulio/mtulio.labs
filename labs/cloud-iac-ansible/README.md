# cloud-iac

Cloud Infra as a Code.

## Usage

### Create an OpenShift cluster on AWS (UPI)

```bash
make openshift-install
```
- Install platform none

1. Comment the variable `config_platform` on `vars/openshift.yaml`:
```diff
-config_platform:
-  aws:
-    region: "{{ ocp_config_region }}"
+# config_platform:
+#   aws:
+#     region: "{{ ocp_config_region }}"
```

2. Run the create cluster:
```bash
CONFIG_CLUSTER_NAME=mrbnone EXTRA_ARGS='-e custom_image_id=ami-0a57c1b4939e5ef5b' \
    $(which time) -v make openshift-install INSTALL_DIR=${PWD}/.install-dir-none
```

### Network

- create AWS VPC

```bash
ansible-playbook net-create.yaml \
    -e provider=aws \
    -e name=k8s
```
