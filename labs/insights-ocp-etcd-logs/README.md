# OCP Samples - Providing credentials to custom workloads in AWS

> TODO

## Build (optional)

This describes the steps to create the container use in this sample.

This is optional, the container is already available on Quay.io.

```bash
IMG=quay.io/ocp-samples/insights-ocp-etcd-logs:latest
podman build -f ContainerFile -t ${IMG} .
podman push ${IMG}
```

## Usage

- Pipe the logs of Must-gather
```
grep -rni "apply request took too long" ${MUST_GATHER_PATH} \
    | grep -Po 'took":"([a-z0-9\.]+)"' \
    | awk -F'took":' '{print$2}' \
    | tr -d '"' \
    | ./insights-ocp-etcd-logs
```

- Pipe the logs of containers
```
TODO
```
