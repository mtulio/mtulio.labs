# OpenShift Development | Create custom release

Openshift installation (installer) will retrieve a release image to
install different components on the cluster.

By default the installer will retrieve the default release image based on 
the installer version.

It's possible to override the release image used by installer, and also 
possible to create your owns - used to test specific components.

The steps below will cover:

- steps to override a release image
- steps to create a custom release

## Steps to override installer release image

To override the installer release image, just set the environment variable `` and run the installer:

```shell
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/<repo>/origin-release@<digest>"
${INSTALLER} create cluster --log-level debug --dir ${INSTALL_DIR}
```

The warning message should be displayed:
```
WARNING Found override for release image. Please be warned, this is not advised
```

## Create custom release

Visit the public mirror and choose the release you want to use:

- [OpenShift v4 public mirror](https://mirror2.openshift.com/pub/openshift-v4/)

In this example we will use the release `latest-4.10 dev-preview` on arch `x86_64`. You can see the manifest [here](https://mirror2.openshift.com/pub/openshift-v4/x86_64/clients/ocp-dev-preview/latest-4.10/release.txt).

Set the release image digest:

```shell
RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release-nightly"
RELEASE_VERSION="4.10.0-0.nightly-2021-12-14-083101"
RELEASE_DIGEST=$(oc adm release info -a ${PULL_SECRET} "${RELEASE_IMAGE}:${RELEASE_VERSION}" -o json |jq .digest)
OCP_RELEASE_BASE="${RELEASE_IMAGE}@${RELEASE_DIGEST}" 
```

Before proceed you should have those environment variables set:

- `PULL_SECRET` : credentials obtained on Red Hat OpenShift portal.
- `OCP_RELEASE_BASE` : base release image (with digest) obtained on the step above
- `NEW_RELEASE_REGISTRY` : base repository that will be saved new release. Eg: quay.io/mtulio
- `NEW_RELEASE_IMAGE` : image that will be saved new release. Example: quay.io/mtulio/release-image

```shell
cat <<-EOF
  PULL_SECRET=${PULL_SECRET}
  OCP_RELEASE_BASE=${OCP_RELEASE_BASE}
  NEW_RELEASE_REGISTRY=${NEW_RELEASE_REGISTRY}
  NEW_RELEASE_IMAGE=${NEW_RELEASE_IMAGE}
EOF
```

Create the custom release overriding the `machine-api-operator` image with yours*.

> This step is considering that you already build and upload the custom image for `machine-api-operator` to `${NEW_RELEASE_REGISTRY}/machine-api-operator:latest`. See more to build custom components [here](./dev-build-components.md).

```shell
oc adm release new \
  -a ${PULL_SECRET} \
  --from-release ${OCP_RELEASE_BASE} \
  --to-image-base=${NEW_RELEASE_REGISTRY}/origin-cluster-version-operator:latest \
  --to-image "${NEW_RELEASE_IMAGE}:latest" \
    machine-api-operator=${NEW_RELEASE_REGISTRY}/machine-api-operator:latest
```

Done, the new release with image for `` is available to be used by installer. Check the payload:

```shell
oc adm release info -a ${PULL_SECRET} "${NEW_RELEASE_IMAGE}:latest"
```

The set the `OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE` with image digest and run the installer.
