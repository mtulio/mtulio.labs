# Installing Hypershift on AWS with STS (unfinished/wip)

Steps to create a cluster with authentication mode with STS in AWS, then install Hypershift using STS (unfinished/unsupported).

References:

- [OCP Doc: Steps to create the cluster with STS](https://docs.openshift.com/container-platform/4.11/authentication/managing_cloud_provider_credentials/cco-mode-sts.html#cco-mode-sts)
- [OCP on AWS - Install cluster with STS with a single command](./ocp-aws-cco-sts-install-quickly.md)
- [Hypershift - Getting started](https://hypershift-docs.netlify.app/getting-started/)

## Steps to create the Hypershift environment

The first step is to install the OpenShift cluster with manual authentication mode with STS, then install HyperShift operator.

```bash
CLUSTER_NAME_OSHIFT="mrboshift01"
CLUSTER_NAME_HSHIFT="mrbhshift04"
```

### Installing OpenShift (Management Cluster)

The steps to install OpenShift cluster quickly on AWS with STS is defined [here](./ocp-aws-cco-sts-install-quickly.md):

```bash
CLUSTER_NAME="${CLUSTER_NAME_OSHIFT}" &&\
  CLUSTER_BASE_DOMAIN="devcluster.openshift.com" &&\
  create_cluster $CLUSTER_NAME
```

### Installing Hypershift operator

Steps:

- Build
```bash
git clone https://github.com/openshift/hypershift.git hypershift-src
cd hypershift-src
make build
cd -
cp hypershift-src/bin/hypershift .
```

### Setup the Hypershift operator

- Create the public zone (skip when already exists)

```bash
BASE_DOMAIN="${CLUSTER_NAME_OSHIFT}-hypershift.${CLUSTER_BASE_DOMAIN}"
aws route53 create-hosted-zone --name $BASE_DOMAIN \
    --caller-reference "${BASE_DOMAIN}"

# Add zone delegation
```

- Create the S3 Bucket

```bash
BUCKET_NAME=${CLUSTER_NAME_OSHIFT}-hypershift-oidc
aws s3api create-bucket --acl public-read --bucket $BUCKET_NAME
```

- Hypershift install

```bash
REGION=us-east-1
BUCKET_NAME=${CLUSTER_NAME_OSHIFT}-hypershift-oidc
AWS_CREDS="$HOME/.aws/credentials"

./hypershift install \
    --oidc-storage-provider-s3-bucket-name $BUCKET_NAME \
    --oidc-storage-provider-s3-credentials $AWS_CREDS \
    --oidc-storage-provider-s3-region $REGION
```

- Check the objects

```bash
$ oc get cm oidc-storage-provider-s3-config -n kube-public -o yaml
apiVersion: v1
data:
  name: hshift02-mrbhypershift01-oidc
  region: us-east-1
kind: ConfigMap
metadata:
  creationTimestamp: "2022-08-01T21:28:01Z"
  name: oidc-storage-provider-s3-config
  namespace: kube-public
  resourceVersion: "27742"

# Users's admin credentials saved
$ oc get secret -n hypershift hypershift-operator-oidc-provider-s3-credentials -o jsonpath={.data.credentials} |base64 -d 
[openshift-dev]
aws_access_key_id = AKIAT[redacted]
aws_secret_access_key = [redacted]
```

### Install the HostedCluster

- Create a HostedCluster

```bash
REGION=us-east-1
BASE_DOMAIN="${CLUSTER_NAME_OSHIFT}-hypershift.${CLUSTER_BASE_DOMAIN}"
AWS_CREDS="$HOME/.aws/credentials"
PULL_SECRET="$HOME/.openshift/pull-secret-latest.json"

./hypershift create cluster aws \
    --name $CLUSTER_NAME_HSHIFT \
    --node-pool-replicas=3 \
    --base-domain $BASE_DOMAIN \
    --pull-secret $PULL_SECRET \
    --aws-creds $AWS_CREDS \
    --region $REGION \
    --generate-ssh
```

- Check HostedClusters

```
$ oc get --namespace clusters hostedclusters
NAME          VERSION   KUBECONFIG                     PROGRESS   AVAILABLE   PROGRESSING   MESSAGE
mrbhshift03             mrbhshift03-admin-kubeconfig   Partial    True        False         The hosted control plane is available

$ oc get pods -n clusters-mrbhshift03
```

- Generate Kubeconfig for HostedCluster

```bash
./hypershift create kubeconfig > kubeconfig-$CLUSTER_NAME_HSHIFT.yaml
```

- Get pods for the HostedCluster

```bash
oc --kubeconfig kubeconfig-$CLUSTER_NAME_HSHIFT.yaml get pods -A
```

- Delete remainging namespaces

```
oc delete ns clusters hypershift
```

- Delete the cluster (Management Cluster)

```
destroy_cluster $CLUSTER_NAME
```


#### Destroy

- Destroy a HostedCluster

```bash
./hypershift destroy cluster aws \
    --name $CLUSTER_NAME_HSHIFT \
    --aws-creds $AWS_CREDS
```


- Destroy the Management Cluster (OpenShift)

```bash
destroy_cluster ${CLUSTER_NAME}
```
