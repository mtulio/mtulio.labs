# Kubernetes Scaling Lab | Setup OpenShift ClusterAutoscaler

### OpenShift cluster auto scaling

```sh
DEDICATED_NODE=true
PATCH_DEDICATED="{\"spec\":{
      \"template\":{
        \"spec\":{
          \"metadata\":{\"labels\":{\"lab-scaling-test\":\"true\"}},
          \"taints\":[{\"key\": \"lab-scaling-test\", \"effect\":\"NoSchedule\"}]
          }}}}"
PATCH_LABEL="{\"spec\":{
      \"template\":{
        \"spec\":{
          \"metadata\":{\"labels\":{\"lab-scaling-test\":\"true\"}},\"taints\":[]
          }}}}"

# Keep two nodes running into single-zone (two replicas), scale down other
# MachineSets.
MSET_NAME_1A=$(oc get machineset -n openshift-machine-api --no-headers | grep us-east-1a | awk '{print$1}')
oc scale machineset --replicas=2 $MSET_NAME_1A -n openshift-machine-api

for MSET_NAME in $(oc get machineset -n openshift-machine-api --no-headers | awk '{print$1}' | grep -v $MSET_NAME_1A); do
  oc scale machineset --replicas=0 $MSET_NAME -n openshift-machine-api
  # Apply taints to the remaining machine sets to make sure nothing else will
  # interact with those nodes while the tests are running.
  if [[ $DEDICATED_NODE == true ]]; then
    oc patch machineset ${MSET_NAME} -n openshift-machine-api --type=merge --patch "$PATCH_DEDICATED"
  else
    oc patch machineset ${MSET_NAME} -n openshift-machine-api --type=merge --patch "$PATCH_LABEL"
    oc patch machineset ${MSET_NAME} -n openshift-machine-api --type=json --patch='[ { "op":"remove", "path": "/spec/template/spec/taints" }]'
  fi

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

oc apply -k setup-autoscaler-ocp/
```