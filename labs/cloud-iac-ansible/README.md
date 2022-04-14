# cloud-iac

Cloud Infra as a Code.

## Usage

### Network

- create AWS VPC

```bash
ansible-playbook net-create.yaml \
    -e provider=aws \
    -e name=k8s
```
