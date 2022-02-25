## Deploying High Scale OpenShift Cluster on AWS | Workload Groups

<!---
State: WIP

Goals:

- Share what is the idea of Workload Groups[1], why use it instead of
machinesets[2].

- Share a simple diagram of how the workloads can be splitted - not going specific as it will be provided each topic, but shrea the steps to do and explanations, to leave the implementation for workload on each section.

[1] Workload groups, or node groups, are group of ASGs used to run specific workloads in a k8s cluster when specifying the Node selector.
[2] ToDo check if machineset will not support the following benefits of ASG: multiple instance types/sizes (m5.xlarge, m6i.large, etc), multiple purchage options (OD and SPOT)

-->

References:

- Read about the [K8s Autoscaler][k8s-autoscaler]
- Read the [ASG guide for EKS][aws-eks-asg-guide]
- Read the AWS Blog: [Creating Kubernetes Auto Scaling Groups for Multiple Availability Zones][aws-blog-k8s-asg]
- Use [Karpenter][karpenter] to scale K8s


[k8s-autoscaler]: https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler
[aws-eks-asg-guide]: https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html
[aws-blog-k8s-asg]: https://aws.amazon.com/blogs/containers/amazon-eks-cluster-multi-zone-auto-scaling-groups/
[karpenter]: https://karpenter.sh/v0.6.1/


## Steps

- Deploy ClusterAutoScaler

- Deploy Karpenter

- EKS notes

## OpenShift Cluster AutoScaler

- It's limited to one CA by cluster, named "default"
- It's linked to one MachineAutoScaler, which is linked to one MachineSet, which is linked to only one InstanceType or AZ


