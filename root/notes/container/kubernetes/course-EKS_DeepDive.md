# AWS EKS - Elastic Kubernetes Service



# [Linux Academy Course: EKS Deep Dive](https://github.com/linuxacademy/eks-deep-dive-2019)

## Lecture: EKS Architecture

What is EKS?
Managed Control Plane
Kubernetes & VPC Networking
AWS CNI Network Plugin
EKS-optimized AMI
Spot Instances


## Lecture: Configuring an EKS Cluster

Creating the EKS service role
Creating the VPC infrastructure using CloudFormation
Creating a cluster in the AWS Management Console
Installing kubectl, aws-iam-authenticator and awscli
Configuring kubectl for EKS
Configuring aws-iam-authenticator

Commands

```
kubectl version --client
aws eks update-kubeconfig --name EKSDeepDive
kubectl config view
kubectl cluster info
```

## Lecture: Provisioning Worker Nodes

Launching EKS worker nodes
Deploying the [Kubernetes dashboard](https://github.com/kubernetes/dashboard)

## Lecture: IAM Authentication

```
aws sts get-caller-identity
```

* Edit permissions on config map using kubectl

```
kubectl edit -n kube-system configmap/aws-auth

---
appVersion: v1
data:
  mapRoles: |
    [...]
  mapUsers: |
    - userarn: arn..
      username: alice
      groups:
        - system:masters
```

# Developing for EKS
