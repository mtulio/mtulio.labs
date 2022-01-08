# AWS EKS | Notes

## Create a cluster

- Create a cluster

```bash
eksctl create cluster \
    --name mrb-test \
    --version 1.21
```

- Create without node group

```bash
eksctl create cluster \
    --name mrb-test \
    --version 1.21 \
    --without-nodegroup
```

- Create with OIDC support

```bash
eksctl create cluster \
    --name mrb-oidc \
    --version 1.21 \
    --with-oidc
```
