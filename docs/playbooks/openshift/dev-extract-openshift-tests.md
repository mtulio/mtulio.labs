# OpenShift Development | Extracting openshift-tests utility

How to extract test binaries from an OpenShift release payload image for local or CI-based test execution.

- [Extract openshift-tests binary from payload](#extract-openshift-tests-binary-from-payload) — the core conformance test binary shipped in the `tests` payload image
- [Extract openshift-tests extension binary (OTE) from payload](#extract-openshift-tests-extension-binary-ote-from-payload) — component-specific test extensions shipped inside their operator images

**Related**: [Build components](dev-build-components.md) | [Create custom release](dev-custom-release.md) | [OTE binary listing (upstream)](https://github.com/openshift/origin/blob/main/pkg/test/extensions/binary.go)

## Extract openshift-tests binary from payload

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

## Extract openshift-tests extension binary (OTE) from payload

Steps to extract one OTE (openshift-tests extension) binary from an
image from the core and run tests on it.

The OTE binary used in this test will be CCM-AWS (cloud-controller-manager for provider AWS) OTE available in the payload image `cluster-cloud-controller-manager-operator`.

> NOTE: OTE binaries are saved in the component image. Look at the [binary listing](https://github.com/openshift/origin/blob/main/pkg/test/extensions/binary.go) for more information.

Prerequisites:
- KUBECONFIG environment variable exported of the cluster that will run the tests
- PULL_SECRET_FILE environment variable exported with valid registry credentials to extract the image
- AWS credentials for the target cluster used by the e2e test binary (OTE) to schedule tests in the target cluster and account

```sh
CCCMO_IMAGE=$(oc adm release info --image-for=cluster-cloud-controller-manager-operator)

oc image extract $CCCMO_IMAGE \
    --file="/usr/bin/cloud-controller-manager-aws-tests-ext.gz" \
    -a ${PULL_SECRET_FILE}

gunzip ./cloud-controller-manager-aws-tests-ext.gz &&
    chmod u+x cloud-controller-manager-aws-tests-ext

```

List tests:
```sh
./cloud-controller-manager-aws-tests-ext list tests
```

Run a specific test:

```sh
./cloud-controller-manager-aws-tests-ext run-test "[cloud-provider-aws-e2e] loadbalancer NLB internal should be reachable with hairpinning traffic [Suite:openshift/conformance/parallel]"
```
