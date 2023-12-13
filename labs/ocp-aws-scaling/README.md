# Kubernetes Scale Validation

Simple way to create "workloads" (pause pods with fixed requests) to validate the
cluster scale up/down.

## Requirements

### Install OpenShift

```sh
CLUSTER_NAME=aws-as-02
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

### Install clients

- helm

```sh
wget -O /tmp/helm.tgz  https://get.helm.sh/helm-v3.13.2-linux-amd64.tar.gz
tar xvfz /tmp/helm.tgz -C /tmp && mv /tmp/linux-amd64/helm ~/bin
```

- kustomize

```sh
wget -O /tmp/kustomize.tgz  https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.3.0/kustomize_v5.3.0_linux_amd64.tar.gz
tar xvfz /tmp/kustomize.tgz  -C ~/bin/
```

## Setup cluster

### OpenShift cluster auto scaling

```sh
oc apply -k setup-autoscaler-ocp/

# Keep two nodes running into single-zone (two replicas), scale down other
# MachineSets.
MSET_NAME_1A=$(oc get machineset -n openshift-machine-api --no-headers | grep us-east-1a | awk '{print$1}')
oc scale machineset --replicas=2 $MSET_NAME_1A -n openshift-machine-api

for MSET_NAME in $(oc get machineset -n openshift-machine-api --no-headers | awk '{print$1}' | grep -v $MSET_NAME_1A); do
  oc scale machineset --replicas=0 $MSET_NAME -n openshift-machine-api
  # Apply taints to the remaining machine sets to make sure nothing else will
  # interact with those nodes while the tests are running.
  oc patch machineset ${MSET_NAME} -n openshift-machine-api --type=merge \
    --patch "{
    \"spec\":{
      \"template\":{
        \"spec\":{
          \"metadata\":{\"labels\":{\"lab-scaling-test\":\"true\"}},
          \"taints\":[{\"key\": \"lab-scaling-test\", \"effect\":\"NoSchedule\"}]
          }}}}"
  cat <<EOF | oc apply -f -
apiVersion: "autoscaling.openshift.io/v1beta1"
kind: "MachineAutoscaler"
metadata:
  name: "worker-${MSET_NAME}" 
  namespace: "openshift-machine-api"
spec:
  minReplicas: 0
  maxReplicas: 4
  scaleTargetRef: 
    apiVersion: machine.openshift.io/v1beta1
    kind: MachineSet 
    name: ${MSET_NAME}
EOF
done
```

Deploy [kube-ops-view](https://codeberg.org/hjacobs/kube-ops-view/src/branch/main/openshift):

```sh
#oc new-project ops-view
oc apply -k deploy-ops-view

kubectl port-forward service/kube-ops-view 8080:80
```

## Run the tests

- Deploy the base app

~~~sh
oc apply -k deploy-inflate/

oc get all -n lab-scaling
~~~

- Warm up the scale (deploy single pod):

~~~sh
oc apply -k overlay/inflate-00-up-1

oc get pods -n lab-scaling
~~~

> Check if the ClusterAutoscaling triggered the Machine creation through MachineAutoscaling/MachineSet.

- Inflate the cluster to 25 pods

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