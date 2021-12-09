# Cluster Version Operator


## Add unmanaged services

Tell CVO to does not manage specific components, the it's possible to run customizations on the object.

Example: Set openshift-apiserver and openshift-image-registry Deployment as unmanaged by CVO:

- Create the patch object
```
cat <<EOF > oc-cvo-unmanage-api_registry.yaml
- op: add
  path: /spec/overrides
  value:
  - kind: Deployment
    group: apps/v1
    name: cluster-image-registry-operator
    namespace: openshift-image-registry
    unmanaged: true
EOF
```

- Patch the CVO
~~~
$ oc patch clusterversion version --type json -p "$(cat oc-cvo-unmanage-api_registry.yaml)"
~~~

- Check the changes

``` json
$ oc get clusterversion version  -o json |jq .spec.overrides
[
  {
    "group": "apps/v1",
    "kind": "Deployment",
    "name": "cluster-image-registry-operator",
    "namespace": "openshift-image-registry",
    "unmanaged": true
  }
]
```

- Scale to scale down the `cluster-image-registry-operator`

``` shell
oc --kubeconfig ${KUBECONFIG} \
    scale --replicas=0 \
    deployment.apps/openshift-apiserver-operator \
    -n openshift-apiserver-operator
```

- Observe if CVO will not touch on it:

```
$ oc --kubeconfig ${KUBECONFIG}     get      deployment.apps/openshift-apiserver-operator     -n openshift-apiserver-operator
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
openshift-apiserver-operator   0/0     0            0           16h

oc --kubeconfig ${KUBECONFIG}     get  pods -l name=openshift-apiserver-operator     -n openshift-apiserver-operator
```

- Make your changes! Eg Running your custom image:

``` shell
# check current image and pull policy
oc --kubeconfig ${KUBECONFIG} \
  -n openshift-image-registry \
  get deployment/cluster-image-registry-operator \
  -o json |jq -r '.spec.template.spec.containers[] | ("\n", .name, .image, .imagePullPolicy)'

# Patch the deployment with the custom image
oc --kubeconfig ${KUBECONFIG} \
 -n openshift-image-registry \
  patch deployment/cluster-image-registry-operator \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"quay.io/rhn_support_mrbraga/cluster-image-registry-operator:ups_pr724_v20211119002811"},{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value":"Always"}]'

# check current image and pull policy
oc --kubeconfig ${KUBECONFIG} \
  -n openshift-image-registry \
  get deployment/cluster-image-registry-operator \
  -o json |jq -r '.spec.template.spec.containers[] | ("\n", .name, .image, .imagePullPolicy)'

# Make sure the pods is running
oc --kubeconfig ${KUBECONFIG} \
  -n openshift-image-registry \
  -l name=cluster-image-registry-operator \
  get pods

# Check the Pod Image
oc --kubeconfig ${KUBECONFIG} \
  -n openshift-image-registry \
  get pods -l name=cluster-image-registry-operator \
  -o json |jq -r '.items[].spec.containers[] | ("\n", .name, .image)'
```
