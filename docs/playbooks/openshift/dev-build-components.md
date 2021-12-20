# OpenShift Development | Build components

## machine-config-operator

Clone the git repository

```shell
cd ${GOHOME}/go/src/github.com/openshift/
git clone --recursive https://github.com/openshift/machine-config-operator
cd machine-config-operator
```

Build and push:
```shell
podman build -f Dockerfile.rhel7 -t quay.io/${QUAY_USER}/machine-config-operator:latest && \
    podman push quay.io/${QUAY_USER}/machine-config-operator:latest
```

## cluster-config-operator
Clone the git repository

```shell
cd ${GOHOME}/go/src/github.com/openshift/
git clone --recursive https://github.com/openshift/cluster-config-operator
cd cluster-config-operator
```

Build and push:
```shell
podman build -f Dockerfile.rhel7 -t quay.io/${QUAY_USER}/cluster-config-operator:latest && \
    podman push quay.io/${QUAY_USER}/cluster-config-operator:latest
```
