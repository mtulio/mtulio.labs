## OKD/OCP Private | Build container image for Proxy server (squid)

Steps to create container image for proxy server (squid):

- Export env vars:

```sh
export CONTAINER_REPO_SQUID=quay.io/mrbraga/squid
export CONTAINER_VERSION_SQUID=6.6-1.fc39

export PROXY_IMAGE=${CONTAINER_REPO_SQUID}:${CONTAINER_VERSION_SQUID}
```

- Build container image:

```sh
cat << EOF > /tmp/squid.Containerfile
FROM quay.io/fedora/fedora-minimal:39
RUN microdnf install -y bash squid-${CONTAINER_VERSION_SQUID} && \
    microdnf clean all
EOF

podman build -f /tmp/squid.Containerfile -t ${PROXY_IMAGE} /tmp

echo -e "***\nImage built: ${PROXY_IMAGE}"
```