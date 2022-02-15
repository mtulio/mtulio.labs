## Deploying High Scale OpenShift Cluster on AWS | etcd offload from Control Plane

<!---
Goals:

- Offload etcd cluster to dedicated nodes
- make sure the nodes has enough capacity
- use c5n like instances - network optimized instances
- use a NLB in front of etcd cluster - ToDo check if can be possible to use zone afffinity with single endpoint

-->

> ToDo: Describe about the motivation, references of high availability and recomendations to offload etcd cluster from control plane

## Steps to split the cluster

- [Create the Machine objects for etcd cluster](./etcd-dedicated-cluster-1-machinery.md)
- Change the CEO (Cluster etcd operator) to deploy etcd on new nodes
> ToDo check references
- Offload current cluster from existing Control Plane Nodes
- Create a NLB and put in front of etcd cluster

## Next Step

> ToDo: AS Control Plane or Split events object to a new cluster?

> Note: Split tasks should be handled into a second version or new post.

## References:

- [Kube HA topology with an external etcd][k8s-ha-topology-etcd]

- [Kube-apiserver command line reference option to use NLB `--etcd-servers-overrides`][kas-cli-doc]

- [AWS Blog creating Zone affinity with NLB DNS address by ENI][aws-design-az-affinity]


<!---
Link references should be here
-->

[k8s-ha-topology-etcd]: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/#external-etcd-topology
[k8s-ha-kubeadm]: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
[kas-cli-doc]: https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/
[aws-design-az-affinity]: [https://aws.amazon.com/blogs/architecture/improving-performance-and-reducing-cost-using-availability-zone-affinity/]
