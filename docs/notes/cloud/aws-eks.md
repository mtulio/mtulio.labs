# AWS EKS | Notes

## Download eksctl

```sh
wget -qO ~/Downloads/eksctl.tar.gz "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
tar xfz  ~/Downloads/eksctl.tar.gz  -C ~/Downloads/
mv ~/Downloads/eksctl ~/bin/
chmod u+x ~/bin/eksctl
```

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

## Login

- Get kubeconfig

```sh
KUBECONFIG=~/.kube/config-tmp
CLUSTER_NAME=mrb-lab-topology
AWS_REGION=us-east-1
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME --kubeconfig $KUBECONFIG
```

## Auto-mode full acces

- Create a cluster with Auto-mode

```sh
CLUSTER_NAME=mrb-am
AWS_REGIOn=us-east-1

eksctl create cluster \
--name $CLUSTER_NAME \
--region  $AWS_REGION \
--version 1.33 \
--enable-auto-mode \
--zones us-east-1a,us-east-1b \
--kubeconfig ~/.kube/eks
```

Access the cluster

```sh
$ kubectl --kubeconfig=/home/mtulio/.kube/eks get nodes
```

## Launch ML instances with Auto Mode

TODO

## Destroy a cluster

```bash
eksctl delete cluster --name mrb-c1
```

## References:

- [EKS Control Planes](https://aws.github.io/aws-eks-best-practices/reliability/docs/controlplane/)
