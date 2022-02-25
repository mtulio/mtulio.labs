## Deploying High Scale OpenShift Cluster on AWS | etcd cluster offload from Control Plane | Machinery

<!---
State: WIP

Goals:

- Describe steps to setup etcd on custom nodes, and join to the cluster

-->

References:

- CEO / StaticPodOperator: https://github.com/openshift/cluster-etcd-operator/blob/master/docs/etcd-tls-assets.md#static-pod-operator
- Static Pod Operator code: https://github.com/openshift/library-go/blob/master/pkg/operator/staticpod/controllers.go

- Static Pods
  - https://github.com/openshift/cluster-etcd-operator/blob/5e3bf2afb81387c73e87cff9835053883e0f9393/pkg/operator/clustermembercontroller/clustermembercontroller.go#L63
  - https://github.com/openshift/cluster-etcd-operator/blob/e9c303d825f12e133f87deab5edc4b98161b6bc7/vendor/github.com/openshift/library-go/pkg/operator/resource/resourceapply/core.go#L160
  - https://github.com/openshift/cluster-etcd-operator/blob/e9c303d825f12e133f87deab5edc4b98161b6bc7/pkg/operator/targetconfigcontroller/targetconfigcontroller.go#L194
  - https://github.com/openshift/library-go/blob/master/pkg/operator/staticpod/controllers.go#L75
  - https://github.com/openshift/library-go/blob/master/pkg/operator/staticpod/installerpod/cmd.go

- ETCD clustering SD: https://etcd.io/docs/v3.4/op-guide/clustering/

- Not supported note: https://access.redhat.com/solutions/4833531
- RFE for CP MachineSet (Vertical only): https://github.com/openshift/enhancements/pull/943/files


- replacing etcd:
```
id=$(sudo crictl ps --name etcd-member | awk 'FNR==2{ print $1}') && sudo crictl exec -it $id /bin/sh \
  export ETCDCTL_API=3 ETCDCTL_CACERT=/etc/ssl/etcd/ca.crt ETCDCTL_CERT=$(find /etc/ssl/ -name *peer*crt) ETCDCTL_KEY=$(find /etc/ssl/ -name *peer*key); etcdctl member list -w table
```

## Summary of increasing cluster size:

Note from [official doc](https://etcd.io/docs/v3.2/op-guide/runtime-configuration/):

> Change the cluster size
> 
> Increasing the cluster size can enhance failure tolerance and provide better read performance. Since clients can read from any member, increasing the number of members increases the overall serialized read throughput.
> 
> Decreasing the cluster size can improve the write performance of a cluster, with a trade-off of decreased resilience. Writes into the cluster are replicated to a majority of members of the cluster before considered committed. Decreasing the cluster size lowers the majority, and each write is committed more quickly.

### Problems found:



### DRAFT / Notes

Steps:

- Install etcd on custom nodes



Raw Steps:

- Add CVO overrides

```bash
cat << EOF > oc-cvo-override-etcd-add.yaml
- op: add
  path: /spec/overrides
  value:
  - kind: Deployment
    group: apps/v1
    name: etcd-operator
    namespace: openshift-etcd-operator
    unmanaged: true
EOF

yq . oc-cvo-override-etcd-add.yaml |awk -v ORS= -v OFS= '{$1=$1}1'

oc patch clusterversion version \
  --type json \
  -p '[{"op":"add","path":"/spec/overrides","value":[{"kind":"Deployment","group":"apps/v1","name":"etcd-operator","namespace":"openshift-etcd-operator","unmanaged":true}]}]'

# Check
oc get clusterversion version -o json |jq .spec.overrides
oc get deployment.apps/etcd-operator -n openshift-etcd-operator -o json |jq .metadata.ownerReferences

```


- Change the node selector of etcd-operator

`oc edit deployment.apps/etcd-operator -n openshift-etcd-operator`

`spec.template.spec.containers[0].nodeSelector`
```diff
      nodeSelector:
        node-role.kubernetes.io/master: ""
+       node-role.kubernetes.io/etcd: ""
```

To install etcd on the node, needed to force the master tag

oc label node ip-10-0-140-17.ec2.internal node-role.kubernetes.io/master=


The scripts to install etcd are hard linked with master node. The operator continues watching the nodes to detect new Master:
`etcd-operator` log:
```
I0215 17:21:35.708560       1 event.go:285] Event(v1.ObjectReference{Kind:"Deployment", Namespace:"openshift-etcd-operator", Name:"etcd-operator", UID:"0b27f777-4eca-45ca-b8ea-d50a99f6b515", APIVersion:"apps/v1", ResourceVersion:"", FieldPath:""}): type: 'Normal' reason: 'MasterNodeObserved' Observed new master node ip-10-0-140-17.ec2.internal

I0215 17:21:35.838266       1 event.go:285] Event(v1.ObjectReference{Kind:"Deployment", Namespace:"openshift-etcd-operator", Name:"etcd-operator", UID:"0b27f777-4eca-45ca-b8ea-d50a99f6b515", APIVersion:"apps/v1", ResourceVersion:"", FieldPath:""}): type: 'Normal' reason: 'ConfigMapUpdated' Updated ConfigMap/etcd-pod -n openshift-etcd:
cause by changes in data.pod.yaml

```

When new master is found, the two CM is populated with new IPs of master:

```
oc get cm  -n openshift-etcd etcd-scripts -o yaml
oc get cm  -n openshift-etcd etcd-pod -o yaml
```

The challenge is to understand what component updates this script.
- Where it's defined?
- How we can trigger the installation of etcd static pods without adding node-role master to etcd nodes?
- do I need to install etcd pods and join to the cluster by hand?


oc exec \
    -n openshift-etcd \
    etcd-${node_name} -- etcdctl member list -w table 2>/dev/null


https://gist.github.com/fjcloud/40620f14b3a8ea701296776cc75cad69

oc wait co kube-apiserver--for=condition=available=true --for=condition=progressing=false

Limitations to deploy 5 nodes:
- quorum does not increase to 5 (did not found what need to be adjusted)
- the CEO does not deploy in custom node-role (eg etcd)
