# OpenShift Development | Extracting openshift-tests utility

Steps to extract openshift-tests utility from specific OCP Version.

Steps:

- Download openshift-installer
- Get the Release Image Digest
- Get the Digest from Tests Image (where the openshift-tests binary is)
- Extract the openshift-tests binary

```bash
export VERSION=${CLUSTER_VERSION:-4.11.0}
oc adm release extract \
    --tools quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64 \
    -a ${PULL_SECRET_FILE}

tar xvfz openshift-install-linux-${VERSION}.tar.gz
RELEASE_IMAGE=$(./openshift-install version | awk '/release image/ {print $3}')
TESTS_IMAGE=$(oc adm release info --image-for='tests' $RELEASE_IMAGE)
oc image extract $TESTS_IMAGE \
    --file="/usr/bin/openshift-tests" \
    -a ${PULL_SECRET_FILE}
chmod u+x ./openshift-tests
```

Use it:

```
./openshift-tests run --dry-run openshift/conformance
```
