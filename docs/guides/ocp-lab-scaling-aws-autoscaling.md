# OpenShift AutoScaling Playground

Install kustomize

~~~sh
wget -O /tmp/kustomize.tgz  https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.3.0/kustomize_v5.3.0_linux_amd64.tar.gz
tar xvfz /tmp/kustomize.tgz  -C ~/bin/
~~~

## Install OCP

```sh
oc adm release extract -a $PULL_SECRET_FILE --tools quay.io/openshift-release-dev/ocp-release:4.15.0-ec.3-x86_64
tar xfz openshift-install*.tar.gz

CLUSTER_NAME=aws-as-01
INSTALL_DIR=${PWD}/installdir-${CLUSTER_NAME}
mkdir $INSTALL_DIR

cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
publish: External
pullSecret: '$(cat $PULL_SECRET_FILE)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: devcluster.openshift.com
platform:
  aws:
    region: us-east-1
EOF

./openshift-install create cluster --dir $INSTALL_DIR
```

## Enable Autoscaler

- https://docs.openshift.com/container-platform/4.14/machine_management/applying-autoscaling.html
- https://docs.openshift.com/container-platform/4.14/machine_management/applying-autoscaling.html

```sh
# Create Cluster AS
cat << EOF | oc create -f -
apiVersion: "autoscaling.openshift.io/v1"
kind: "ClusterAutoscaler"
metadata:
  name: "default"
spec:
  podPriorityThreshold: -10 
  resourceLimits:
    maxNodesTotal: 10 
    cores:
      min: 8 
      max: 80 
    memory:
      min: 4 
      max: 128 
  logVerbosity: 4 
  scaleDown: 
    enabled: true 
    delayAfterAdd: 10m 
    delayAfterDelete: 5m 
    delayAfterFailure: 30s 
    unneededTime: 5m 
    utilizationThreshold: "0.4" 
EOF

# Create MAS

machinesets=("us-east-1a")
machinesets+=("us-east-1b")
machinesets+=("us-east-1c")
machinesets+=("us-east-1d")
machinesets+=("us-east-1e")
machinesets+=("us-east-1f")

for ms in ${machinesets[*]}; do
    ms_name=$()
    echo "Creating MachineAutoscaler for machineSet=${ms_name}"
    cat <<EOF | oc create -f -
apiVersion: "autoscaling.openshift.io/v1beta1"
kind: "MachineAutoscaler"
metadata:
  name: "worker-${ms}" 
  namespace: "openshift-machine-api"
spec:
  minReplicas: 1 
  maxReplicas: 4 
  scaleTargetRef: 
    apiVersion: machine.openshift.io/v1beta1
    kind: MachineSet 
    name: ${ms_name}
EOF
done
```

- https://docs.openshift.com/container-platform/4.14/nodes/scheduling/nodes-scheduler-profiles.html
```sh
apiVersion: config.openshift.io/v1
kind: Scheduler
metadata:
  name: cluster
#...
spec:
  mastersSchedulable: false
  profile: HighNodeUtilization 
#...
```

## Setup environment

- Scale down the us-east-1c: `oc scale machineset --replicas=0 aws-as-01-5n92l-worker-us-east-1c -n openshift-machine-api`

- Set the taints to NoSchedule to existing worker nodes
~~~sh
for NODE in $(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[*].metadata.name}'); do oc label node default-worker=true; oc adm taint node $NODE default-worker=true:NoSchedule --overwrite; done
~~~

- Create MAS

~~~sh
#machinesets=("us-east-1a")
#machinesets+=("us-east-1b")
zones=("us-east-1c")
zones+=("us-east-1d")
zones+=("us-east-1f")

infra_name=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')

for zone in ${zones[*]}; do
    ms_name=${infra_name}-worker-${zone}
    echo "Creating MachineAutoscaler for machineSet=${ms_name}"
    cat <<EOF | oc create -f -
apiVersion: "autoscaling.openshift.io/v1beta1"
kind: "MachineAutoscaler"
metadata:
  name: "worker-${zone}" 
  namespace: "openshift-machine-api"
spec:
  minReplicas: 1 
  maxReplicas: 4 
  scaleTargetRef: 
    apiVersion: machine.openshift.io/v1beta1
    kind: MachineSet 
    name: ${ms_name}
EOF
done
~~~

- Create CA

~~~sh
cat << EOF | oc create -f -
apiVersion: "autoscaling.openshift.io/v1"
kind: "ClusterAutoscaler"
metadata:
  name: "default"
spec:
  podPriorityThreshold: -10 
  resourceLimits:
    maxNodesTotal: 10 
    cores:
      min: 8 
      max: 80 
    memory:
      min: 4 
      max: 128 
  logVerbosity: 4 
  scaleDown: 
    enabled: true 
    delayAfterAdd: 10m 
    delayAfterDelete: 5m 
    delayAfterFailure: 30s 
    unneededTime: 5m 
    utilizationThreshold: "0.4" 
EOF
~~~

- create

~~~sh
oc apply -k deploy-inflate/

oc get all -n lab-scaling
~~~

- scale warm

~~~sh
oc apply -k overlay/inflate-00-up-1-1
~~~

- Check machine created:

~~~sh

~~~

- inflate more

~~~sh
oc apply -k overlay/inflate-00-up-25-25/
~~~

CA scaled two more nodes but kept a lot of pods pending.
MCA also scaled in the same AZ. Pending pod

~~~
$ oc describe pod inflate-74447488bd-x5k4d -n lab-scaling  | tail  -n 1
  Normal   NotTriggerScaleUp  53s (x26 over 9m22s)   cluster-autoscaler  pod didn't trigger scale-up: 3 max cluster memory limit reached

$ oc get pods  -n lab-scaling -o wide |awk '{print$7}' | sort | uniq -c
      3 ip-10-0-70-168.ec2.internal
      3 ip-10-0-77-101.ec2.internal
      3 ip-10-0-79-130.ec2.internal
      1 NODE
     16 <none>
~~~

- patch AS to use more CPU

~~~sh
 config.openshift.io/v1
kind: Scheduler
metadata:
  name: cluster
$ oc patch scheduler.config.openshift.io cluster -n openshift-machine-api --type=merge --patch "{\"spec\":{\"profile\":\"HighNodeUtilization\"}}"
~~~

- scale down pods 1:1

~~~sh
$ oc apply -k overlay/inflate-00-up-1-1
namespace/lab-scaling unchanged
deployment.apps/inflate configured
~~~

- a new node was scaled (???)

~~~sh
$ oc get pods  -n lab-scaling -o wide -w
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                          NOMINATED NODE   READINESS GATES
inflate-74447488bd-5z2mp   1/1     Running   0          16m   10.130.2.9   ip-10-0-79-130.ec2.internal   <none>           <none>

$ oc get machines -n openshift-machine-api -w
NAME                                      PHASE         TYPE         REGION      ZONE         AGE
aws-as-01-5n92l-master-0                  Running       m6i.xlarge   us-east-1   us-east-1a   73m
aws-as-01-5n92l-master-1                  Running       m6i.xlarge   us-east-1   us-east-1b   73m
aws-as-01-5n92l-master-2                  Running       m6i.xlarge   us-east-1   us-east-1c   73m
aws-as-01-5n92l-worker-us-east-1a-4plbb   Running       m6i.xlarge   us-east-1   us-east-1a   70m
aws-as-01-5n92l-worker-us-east-1b-zwwhm   Running       m6i.xlarge   us-east-1   us-east-1b   70m
aws-as-01-5n92l-worker-us-east-1f-7qjdm   Running       m6i.xlarge   us-east-1   us-east-1f   16m
aws-as-01-5n92l-worker-us-east-1f-c998f   Running       m6i.xlarge   us-east-1   us-east-1f   16m
aws-as-01-5n92l-worker-us-east-1f-cv8sb   Running       m6i.xlarge   us-east-1   us-east-1f   25m
aws-as-01-5n92l-worker-us-east-1f-m27mf   Provisioned   m6i.xlarge   us-east-1   us-east-1f   2m11s
aws-as-01-5n92l-worker-us-east-1f-m27mf   Provisioned   m6i.xlarge   us-east-1   us-east-1f   3m28s
aws-as-01-5n92l-worker-us-east-1f-m27mf   Running       m6i.xlarge   us-east-1   us-east-1f   3m28s
aws-as-01-5n92l-worker-us-east-1f-m27mf   Running       m6i.xlarge   us-east-1   us-east-1f   4m27s

$ oc get nodes
NAME                          STATUS   ROLES                  AGE     VERSION
ip-10-0-13-127.ec2.internal   Ready    worker                 67m     v1.28.3+20a5764
ip-10-0-14-126.ec2.internal   Ready    control-plane,master   78m     v1.28.3+20a5764
ip-10-0-18-72.ec2.internal    Ready    worker                 67m     v1.28.3+20a5764
ip-10-0-27-11.ec2.internal    Ready    control-plane,master   76m     v1.28.3+20a5764
ip-10-0-42-140.ec2.internal   Ready    control-plane,master   78m     v1.28.3+20a5764
ip-10-0-70-168.ec2.internal   Ready    worker                 17m     v1.28.3+20a5764
ip-10-0-74-116.ec2.internal   Ready    worker                 3m16s   v1.28.3+20a5764
ip-10-0-77-101.ec2.internal   Ready    worker                 17m     v1.28.3+20a5764
ip-10-0-79-130.ec2.internal   Ready    worker                 25m     v1.28.3+20a5764
~~~

- scale up again

~~~sh

~~~

- check pods (a few allocated, 3 by node)

~~~sh
$ oc get pods  -n lab-scaling -o wide --no-headers |awk '{print$7}' | sort | uniq -c
      3 ip-10-0-70-168.ec2.internal
      3 ip-10-0-74-116.ec2.internal
      3 ip-10-0-77-101.ec2.internal
      3 ip-10-0-79-130.ec2.internal
     13 <none>
~~~

- Checking one pod

~~~sh
Events:
  Type     Reason             Age                  From                Message
  ----     ------             ----                 ----                -------
  Warning  FailedScheduling   4m1s                 default-scheduler   0/9 nodes are available: 2 node(s) had untolerated taint {default-worker: true}, 3 node(s) had untolerated taint {node-role.kubernetes.io/master: }, 4 Insufficient cpu. preemption: 0/9 nodes are available: 4 No preemption victims found for incoming pod, 5 Preemption is not helpful for scheduling..
  Warning  FailedScheduling   2m53s                default-scheduler   0/9 nodes are available: 2 node(s) had untolerated taint {default-worker: true}, 3 node(s) had untolerated taint {node-role.kubernetes.io/master: }, 4 Insufficient cpu. preemption: 0/9 nodes are available: 4 No preemption victims found for incoming pod, 5 Preemption is not helpful for scheduling..
  Normal   NotTriggerScaleUp  26s (x6 over 3m19s)  cluster-autoscaler  pod didn't trigger scale-up: 1 max node group size reached, 2 node(s) didn't match Pod's node affinity/selector
  Normal   NotTriggerScaleUp  6s (x6 over 3m38s)   cluster-autoscaler  pod didn't trigger scale-up: 2 node(s) didn't match Pod's node affinity/selector, 1 max node group size reached
~~~

- Scale down pods

~~~sh
$ oc get pods  -n lab-scaling -o wide --no-headers |awk '{print$7}' | sort | uniq -c
      1 ip-10-0-79-130.ec2.internal
~~~

- Waiting for nodes scale down

~~~sh
$ oc get machines -n openshift-machine-api 
NAME                                      PHASE     TYPE         REGION      ZONE         AGE
aws-as-01-5n92l-master-0                  Running   m6i.xlarge   us-east-1   us-east-1a   99m
aws-as-01-5n92l-master-1                  Running   m6i.xlarge   us-east-1   us-east-1b   99m
aws-as-01-5n92l-master-2                  Running   m6i.xlarge   us-east-1   us-east-1c   99m
aws-as-01-5n92l-worker-us-east-1a-4plbb   Running   m6i.xlarge   us-east-1   us-east-1a   96m
aws-as-01-5n92l-worker-us-east-1b-zwwhm   Running   m6i.xlarge   us-east-1   us-east-1b   96m
aws-as-01-5n92l-worker-us-east-1f-cv8sb   Running   m6i.xlarge   us-east-1   us-east-1f   51m
~~~

- Scale medium

~~~sh
oc apply -k overlay/inflate-00-up-8
~~~

- only 3 by node

~~~sh
$ oc get pods  -n lab-scaling -o wide --no-headers |awk '{print$7}' | sort | uniq -c
      3 ip-10-0-79-130.ec2.internal
      5 <none>
~~~

- provisioned two nodes

~~~sh
$ oc get machines -n openshift-machine-api 
NAME                                      PHASE          TYPE         REGION      ZONE         AGE
aws-as-01-5n92l-master-0                  Running        m6i.xlarge   us-east-1   us-east-1a   102m
aws-as-01-5n92l-master-1                  Running        m6i.xlarge   us-east-1   us-east-1b   102m
aws-as-01-5n92l-master-2                  Running        m6i.xlarge   us-east-1   us-east-1c   102m
aws-as-01-5n92l-worker-us-east-1a-4plbb   Running        m6i.xlarge   us-east-1   us-east-1a   99m
aws-as-01-5n92l-worker-us-east-1b-zwwhm   Running        m6i.xlarge   us-east-1   us-east-1b   99m
aws-as-01-5n92l-worker-us-east-1f-9pw6m   Provisioning   m6i.xlarge   us-east-1   us-east-1f   31s
aws-as-01-5n92l-worker-us-east-1f-cv8sb   Running        m6i.xlarge   us-east-1   us-east-1f   54m
aws-as-01-5n92l-worker-us-east-1f-n4fff   Provisioning   m6i.xlarge   us-east-1   us-east-1f   31s

$ oc get deployment.apps/inflate  -n lab-scaling -o yaml | yq ea .spec.template.spec.containers -
- image: public.ecr.aws/eks-distro/kubernetes/pause:3.2
  imagePullPolicy: IfNotPresent
  name: inflate
  resources:
    requests:
      cpu: "1"
      memory: 1Gi
  terminationMessagePath: /dev/termination-log
  terminationMessagePolicy: File

$ oc get node ip-10-0-79-130.ec2.internal -o yaml | yq ea .status.capacity -
cpu: "4"
ephemeral-storage: 125238252Ki
hugepages-1Gi: "0"
hugepages-2Mi: "0"
memory: 16092956Ki
pods: "250"

$ oc get machineautoscaler -A
NAMESPACE               NAME                REF KIND     REF NAME                            MIN   MAX   AGE
openshift-machine-api   worker-us-east-1c   MachineSet   aws-as-01-5n92l-worker-us-east-1c   1     4     64m
openshift-machine-api   worker-us-east-1d   MachineSet   aws-as-01-5n92l-worker-us-east-1d   1     4     64m
openshift-machine-api   worker-us-east-1f   MachineSet   aws-as-01-5n92l-worker-us-east-1f   1     4     64m

$ oc get machineset -A
NAMESPACE               NAME                                DESIRED   CURRENT   READY   AVAILABLE   AGE
openshift-machine-api   aws-as-01-5n92l-worker-us-east-1a   1         1         1       1           107m
openshift-machine-api   aws-as-01-5n92l-worker-us-east-1b   1         1         1       1           107m
openshift-machine-api   aws-as-01-5n92l-worker-us-east-1c   0         0                             107m
openshift-machine-api   aws-as-01-5n92l-worker-us-east-1d   0         0                             107m
openshift-machine-api   aws-as-01-5n92l-worker-us-east-1f   3         3         3       3           107m
~~~

## Scale

```sh

cat <<EOF > ./deploy-inflate/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
  namespace: lab-scaling
spec:
  replicas: 0
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      nodeSelector:
        type: karpenter
      terminationGracePeriodSeconds: 0
      containers:
        - name: inflate
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.2
          resources:
            requests:
              cpu: 1
              memory: 1Gi
EOF

$ kubectl scale -n other deployment/inflate --replicas 5

$ kubectl rollout status -n other deployment/inflate --timeout=180s
```

~~~sh

kubectl apply -k overlay/production
~~~


References:

- https://www.eksworkshop.com/docs/autoscaling/workloads/cluster-proportional-autoscaler/
- https://archive.eksworkshop.com/beginner/085_scaling_karpenter/automatic_node_provisioning/
- 