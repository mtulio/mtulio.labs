# ROSA References | Notes

## Workshops

- https://mobb.ninja/docs/rosa/cluster-metrics-to-aws-prometheus/

## Usage

### Common usual commands:

```bash
./rosa whoami
./rosa verify quota
./rosa create cluster --sts
./rosa create account-roles
./rosa create cluster --sts
./rosa create operator-roles --cluster mrbrosa
./rosa create oidc-provider --cluster mrbrosa
./rosa describe cluster -c mrbrosa
./rosa get nodes
./rosa describe cluster -c mrbrosa
./rosa list -c mrbrosa
./rosa list machinepools -c mrbrosa
./rosa list clusters
```

### Get credentials

<todo>

- Get your offline token from https://console.redhat.com/openshift/token
- Login
```bash
rosa login --token=<offline-token>
```

### Create a cluster

<todo>

### Destroy a cluster

```bash
rosa delete cluster -c $CLUSTER_NAME
rosa delete operator-roles -c $CLUSTER_NAME
rosa delete oidc-provider -c $CLUSTER_NAME
```

## References:

- [CLI](https://docs.openshift.com/rosa/rosa_cli/rosa-get-started-cli.html)
- [Getting started with ROSA](https://docs.openshift.com/rosa/rosa_install_access_delete_clusters/rosa-sts-creating-a-cluster-quickly.html)
