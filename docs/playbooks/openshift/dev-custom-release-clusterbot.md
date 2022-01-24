# OpenShift Development | Create custom release with cluster-bot

cluster-bot will run the same steps to [create a custom release](./dev-custom-release.md) running:

```bash
build openshift/<project>#<PR>
```

Then one release image will be created for you in a specific CI cluster.

To retrieve that image you will need to get the CI credentials specific for the cluster that release was created and merge it with your pull-secret. See the steps:

- Build the release image from a PR
- Login to the cluster

get the cluster to login (from log)
```
INFO[2022-01-21T02:59:47Z] Using namespace https://console.build01.ci.openshift.org/k8s/cluster/projects/ci-ln-5dv97zt 
```

login to `https://oauth-openshift.apps.<cluster>` to get the token and CLI command line:

```
https://oauth-openshift.apps.build01.ci.openshift.org/oauth/token/display

```

login to cli:
```bash
oc login --token=<redacted> --server=https://api.<cluster>: 6443
```

- Login to the registry mergin with your current pull-secret

```bash
oc registry login --to=${PULL_SECRET}
```

- Fix formating issues with pull-secret

```bash
cp ${PULL_SECRET} ${PULL_SECRET}.tmp
cat ${PULL_SECRET}.tmp |awk -v ORS= -v OFS= '{$1=$1}1' > ${PULL_SECRET}
```
