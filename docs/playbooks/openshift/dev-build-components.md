# OpenShift Development | Build components

## installer

Clone the repository:
```shell
cd ${GOHOME}/go/src/github.com/openshift/
git clone --recursive https://github.com/openshift/installer
cd installer
```

Build:
```shell
$(which time) -v hack/build.sh
```

Save it in your custom bin path:
```shell
cp -v bin/openshift-install ${MY_BIN}/openshift-install-$(git branch |grep ^'*' |awk '{print$2}')
```

## machine-config-operator

Clone the repository:
```shell
cd ${GOHOME}/go/src/github.com/openshift/
git clone --recursive https://github.com/openshift/machine-config-operator
cd machine-config-operator
```

Build ([reference](https://github.com/openshift/machine-config-operator/blob/master/docs/HACKING.md#build-mco-image)), push and release:

```bash
make image
podman push localhost/machine-config-operator quay.io/$QUAY_USER/machine-config-operator:latest-4.14-external

oc adm release new -n origin --server https://api.ci.openshift.org \
  --from-release "registry.ci.openshift.org/ocp/release:4.14.0-0.nightly-2023-06-27-233015" \
  --to-image quay.io/mrbraga/ocp-release:4.14.0-0.nightly-2023-06-27-233015-mco-installer \
    machine-config-operator=quay.io/mrbraga/machine-config-operator:latest-4.14-external \
    installer=quay.io/mrbraga/openshift-installer:pr7217-external
```

(old) Build and push :
```shell
podman build -f Dockerfile.rhel7 -t quay.io/${QUAY_USER}/machine-config-operator:latest && \
    podman push quay.io/${QUAY_USER}/machine-config-operator:latest
```
## installer

```bash
podman build -f images/installer/Dockerfile.ci -t quay.io/$QUAY_USER/openshift-installer:latest-external .

NEW_VERSION=4.14.0-0.nightly-2023-07-05-071214
#TO_IMAGE=quay.io/mrbraga/ocp-release:$NEW_VERSION
TO_IMAGE=docker.io/mtulio/ocp-release:$NEW_VERSION

BASE_IMAGE="registry.ci.openshift.org/ocp/release:$NEW_VERSION"
oc adm release new -n origin -a $PULL_SECRET_FILE \
  --server https://api.ci.openshift.org \
  --from-release $BASE_IMAGE \
  --to-image $TO_IMAGE \
    installer=quay.io/mrbraga/openshift-installer:pr7217-external

podman pull $TO_IMAGE
podman push $TO_IMAGE quay.io/mrbraga/ocp-release:$NEW_VERSION 
```


## cluster-config-operator

Clone the repository:
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

## cluster-kube-apiserver-operator

Clone the repository:
```shell
cd ${GOHOME}/go/src/github.com/openshift/
git clone --recursive https://github.com/openshift/cluster-kube-apiserver-operator
cd cluster-kube-apiserver-operator
```

Build and push:
```shell
REPO_NAME=cluster-kube-apiserver-operator
podman build \
    --authfile ${PULL_SECRET} \
    -f Dockerfile.rhel7 \
    -t quay.io/${QUAY_USER}/${REPO_NAME}:latest \
    && podman push quay.io/${QUAY_USER}/${REPO_NAME}:latest
```

## API updates

> https://mtulio.net/notes/development/lang_go/?h=go

```bash
#> API repo
# change API and push to a custom repo

#> Library
# from library get the pseudo version
go get -d github.com/mtulio/api@tmp-promote-external
# OR
go get -d github.com/mtulio/api@18d636b
# update go.mod. something like that:
+replace github.com/openshift/api => github.com/mtulio/api v0.0.0-20230630145723-18d636baa7c3

go mod tidy
go mod vendor
git add .
git checkout -b mychange
git push myremote mychange

# get pseudo version
TZ=UTC git --no-pager show \
   --quiet \
   --abbrev=12 \
   --date='format-local:%Y%m%d%H%M%S' \
   --format="%cd-%h"

# or
go list -f '{{.Version}}' -m github.com/mtulio/library-go@tmp-promote-external

#> Component repo (MCO)
# get the pseudo version
go get -d github.com/mtulio/library-go@tmp-promote-external
# update go.mod
replace github.com/openshift/library-go => github.com/mtulio/library-go v0.0.0-20230630150302-deb6056a3b22

go mod tidy
go mod vendor

make image

MCO_VERSION=latest-4.14-external-nofg-crd_manual
podman push localhost/machine-config-operator quay.io/$QUAY_USER/machine-config-operator:$MCO_VERSION

NEW_VERSION=4.14.0-0.nightly-2023-06-27-233015-mco_manual_crd-installer
DOCKER_IMAGE=docker.io/mtulio/ocp-release:$NEW_VERSION
NEW_RELEASE=quay.io/mrbraga/ocp-release:$NEW_VERSION
oc adm release new -n origin -a $PULL_SECRET_FILE \
  --server https://api.ci.openshift.org \
  --from-release "registry.ci.openshift.org/ocp/release:4.14.0-0.nightly-2023-06-27-233015" \
  --to-image $DOCKER_IMAGE \
    machine-config-operator=quay.io/mrbraga/machine-config-operator:$MCO_VERSION \
    installer=quay.io/mrbraga/openshift-installer:pr7217-external

podman pull $DOCKER_IMAGE
podman tag $DOCKER_IMAGE $NEW_RELEASE
podman push $NEW_RELEASE

podman push $NEW_RELEASE quay.io/mrbraga/ocp-release:4.14.0-0.nightly-2023-06-27-233015
```

- Creating OKD release

```bash
# build MCO FCOS
# Add the flag to hack/build-image: --env=TAGS=fcos
make image
MCO_VERSION=latest-4.14-external-crd_manual-okd-fcos
podman push localhost/machine-config-operator quay.io/$QUAY_USER/machine-config-operator:$MCO_VERSION

PULL_SECRET_FILE_OKD=$HOME/.openshift/pull-secret-okd-fake.json 
NEW_VERSION=4.14.0-0.okd-2023-07-03-105114
TO_IMAGE=quay.io/mrbraga/ocp-release:$NEW_VERSION
BASE_IMAGE="registry.ci.openshift.org/origin/release:$NEW_VERSION"
oc adm release new -n origin -a $PULL_SECRET_FILE_OKD \
  --server https://api.ci.openshift.org \
  --from-release $BASE_IMAGE \
  --to-image $TO_IMAGE \
    machine-config-operator=quay.io/mrbraga/machine-config-operator:$MCO_VERSION \
    installer=quay.io/mrbraga/openshift-installer:pr7217-external

# 
# Build with SCOS
# Change Dockerfile: TAGS="scos"
make image
MCO_VERSION=latest-4.14-external-crd_manual-okd-scos
podman push localhost/machine-config-operator quay.io/$QUAY_USER/machine-config-operator:$MCO_VERSION

NEW_VERSION=4.14.0-0.okd-scos-2023-07-02-055557
TO_IMAGE=quay.io/mrbraga/ocp-release:$NEW_VERSION

BASE_IMAGE="registry.ci.openshift.org/origin/release-scos:4.14.0-0.okd-scos-2023-07-02-055557"
oc adm release new -n origin -a $PULL_SECRET_FILE_OKD \
  --server https://api.ci.openshift.org \
  --from-release $BASE_IMAGE \
  --to-image $TO_IMAGE \
    machine-config-operator=quay.io/mrbraga/machine-config-operator:$MCO_VERSION \
    installer=quay.io/mrbraga/openshift-installer:pr7217-external
```

- MCO regen CRD manifests: https://github.com/openshift/machine-config-operator/pull/3567#issuecomment-1440000069

## cluster-kube-controller-manager-operator


```bash
QUAY_USER=mrbraga
REPO_NAME=cluster-kube-controller-manager-operator

podman build \
    --authfile ${PULL_SECRET} \
    -f Dockerfile.rhel7 \
    -t quay.io/${QUAY_USER}/${REPO_NAME}:latest \
    && podman push quay.io/${QUAY_USER}/${REPO_NAME}:latest

TS=$(date +%Y%m%d%H%M)
podman tag quay.io/${QUAY_USER}/${REPO_NAME}:latest "quay.io/${QUAY_USER}/${REPO_NAME}:${TS}" \
podman push "quay.io/${QUAY_USER}/${REPO_NAME}:${TS}"
```


## cluster-cloud-controller-manager-operator (CCCMO/3CMO)


```bash
QUAY_USER=mrbraga
REPO_NAME=cluster-cloud-controller-manager-operator

podman build \
    --authfile ${PULL_SECRET} \
    -f Dockerfile \
    -t quay.io/${QUAY_USER}/${REPO_NAME}:latest \
    && podman push quay.io/${QUAY_USER}/${REPO_NAME}:latest

TS=$(date +%Y%m%d%H%M)
podman tag quay.io/${QUAY_USER}/${REPO_NAME}:latest "quay.io/${QUAY_USER}/${REPO_NAME}:${TS}" \
podman push "quay.io/${QUAY_USER}/${REPO_NAME}:${TS}"
```

## origin

### Container build

1. Get CI credentials and concat to pull secret
1. Connect to VPN: the rhel container will fallback to local repo when building locally, which depends on private net
1. Run the build:

```bash
podman build \
    --authfile ~/.openshift/pull-secret-latest.json \
    -t quay.io/${QUAY_USER}/openshift-tests:latest \
    -f images/tests/Dockerfile.rhel .
``'
