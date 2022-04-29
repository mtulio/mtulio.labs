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
    --name mrb-c2 \
    --version 1.21 \
    --with-oidc
```

## Destroy a cluster

```bash
eksctl delete cluster --name mrb-c1
```

## References:

- [EKS Control Planes](https://aws.github.io/aws-eks-best-practices/reliability/docs/controlplane/)
