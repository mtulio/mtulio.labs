# Kubernetes scaling exploration

Some options to create "workloads" to exercise the kube cluster scale up/down in OpenShift.

## Requirements

### Install clients

- openshift-install
- oc

**Optional**:

- kustomize

```sh
wget -O /tmp/kustomize.tgz  https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.3.0/kustomize_v5.3.0_linux_amd64.tar.gz
tar xvfz /tmp/kustomize.tgz  -C ~/bin/
```

- k9s

```sh
wget -qO /tmp/k9s.tgz https://github.com/derailed/k9s/releases/download/v0.29.1/k9s_Linux_amd64.tar.gz
tar xvfz /tmp/k9s.tgz  -C /tmp/ && mv /tmp/k9s ~/bin/k9s
```



### Install OpenShift cluster on AWS (default)

```sh
CLUSTER_NAME=aws-as-05
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

### Setup OpenShift cluster auto scaling

Setup the cluster autoscaler used to run the tests:

- [OpenShift ClusterAutoscaler](./setup-ocp-autoscaler.md)
- [Karpenter](./setup-karpenter.md)
- [Spot.io](./setup-spotio.md)

### Deploy monitor kube-ops-view

[kube-ops-view](https://codeberg.org/hjacobs/kube-ops-view/src/branch/main/openshift)
utility helps to visualize (graphical web UI) the nodes
and pod allocation within the cluster.

- Deploy with in OpenShift cluster:

```sh
oc apply -k deploy-ops-view
```

Get the route and open in your browser:

```sh
oc get route -n ocp-ops-view
```

Example: https://proxy-ocp-ops-view.apps.aws-as-03.devcluster.openshift.com/

### Deploy scaling monitor costs

> TBD: How?

## Run tests

### Tests using the 'inflate app'

`inflate app` is merely pause pods with fixed size defined with kustomize to quickly
test the nodes autoscaling.

- Deploy the base app

~~~sh
oc apply -k deploy-inflate/

oc get all -n lab-scaling
~~~

OR deploy without tolerations:

~~~sh
oc apply -k deploy-inflate-no-taint/

oc get all -n lab-scaling
~~~

- Warm up the scale (deploy single pod):

~~~sh
oc apply -k overlay/inflate-00-up-1

oc get pods -n lab-scaling
~~~

> Check if the Cluster Autoscaler triggered the Machine creation through MachineAutoscaling/MachineSet.

- Inflate the cluster to 12 pods (medium?)

> 12 CPU + 12 GiB Mem. 12 == (~4 regular nodes of 4CPU 16GiB [~3GiB] + cluster overhead + spare)

~~~sh
oc apply -k overlay/inflate-00-up-12/

oc get pods -n lab-scaling -o wide -w
~~~


- Inflate the cluster to 25 pods (heavy)

~~~sh
oc apply -k overlay/inflate-00-up-25/

oc get pods -n lab-scaling -o wide -w
~~~

Check if there are nodes scaling:

~~~sh
oc get machines -n openshift-machine-api -w
oc get nodes
~~~

- Scale down to single replica:

~~~sh
oc apply -k overlay/inflate-00-up-1
~~~

- Scale down to 0 replica (expect to remove nodes):

~~~sh
oc apply -k overlay/inflate-00-up-0
~~~

### Tests using the with kube-burner

[kube-burner](https://cloud-bulldozer.github.io/kube-burner/latest/ocp/?h=density+v2#metrics-profile-type)
is a tool to stress kubernetes clusters.

- Install

```sh
wget -qO /tmp/kube-burner.tgz  https://github.com/cloud-bulldozer/kube-burner/releases/download/v1.8.0/kube-burner-V1.8.0-linux-x86_64.tar.gz

tar xfz /tmp/kube-burner.tgz -C /tmp && mv /tmp/kube-burner ~/bin
```

- Run cluster-density-v2

```sh
kube-burner ocp cluster-density-v2 --iterations=1 --churn-duration=5m0s  

kube-burner ocp cluster-density-v2 --iterations=50 --churn-duration=5m0s
```

- Run cluster-density-v2

```sh
kube-burner ocp node-density --pods-per-node=150 --burst 50
```

- (TODO?) Run the web-burner-cluster-density



## References

Other future explorations:

- [AWS Auto Scaling Group with native Kubernetes Cluster Autoscaler](https://aws.github.io/aws-eks-best-practices/cluster-autoscaling/)
- [KEDA + Karpenter](https://github.com/aws-samples/
amazon-eks-scaling-with-keda-and-karpenter)
    - [Use case: Mastercard](https://www.youtube.com/watch?v=yOzyXY97CrI)
- [Native AWS predictive Scaling with Kube?](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-predictive-scaling.html)
