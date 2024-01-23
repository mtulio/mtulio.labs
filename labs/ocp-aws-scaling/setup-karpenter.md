# Kubernetes Scaling Lab | Karpenter

[karpenter.sh](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/)
steps to validate the lab.

## Install clients

- helm

```sh
wget -O /tmp/helm.tgz  https://get.helm.sh/helm-v3.13.2-linux-amd64.tar.gz
tar xvfz /tmp/helm.tgz -C /tmp && mv /tmp/linux-amd64/helm ~/bin
```

## install karpenter

- https://github.com/Spazzy757/helm-to-kustomize
- https://github.com/aws/karpenter-provider-aws/blob/v0.27.0/charts/karpenter/templates/deployment.yaml
file:///home/mtulio/Documents/karpenter-on-openshift.pdf
- https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/
- https://github.com/kubernetes-sigs/kustomize/blob/master/examples/patchMultipleObjects.md

~~~sh
export KARPENTER_NAMESPACE=karpenter
export KARPENTER_VERSION=v0.27.0
export CLUSTER_NAME=$(oc get infrastructures cluster -o jsonpath='{.status.infrastructureName}')

cat <<EOF
KARPENTER_NAMESPACE=$KARPENTER_NAMESPACE
KARPENTER_VERSION=$KARPENTER_VERSION
CLUSTER_NAME=$CLUSTER_NAME
EOF

oc apply -k deploy-karpenter/

mkdir deploy-karpenter/tmp
helm repo add -n karpenter karpenter-${KARPENTER_VERSION} https://public.ecr.aws/karpenter/karpenter
helm repo update


helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" --namespace "${KARPENTER_NAMESPACE}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait

oc patch 

oc debug pods deployment.apps/karpenter -n karpenter --image registry.access.redhat.com/ubi8/toolbox
~~~