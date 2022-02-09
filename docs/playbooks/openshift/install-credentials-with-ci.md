# OCP Installer Development | Getting credentials with CI

The credentials used by installer is commonly called `pull-secret`.

You can otain the pull-secret for free on Red Hat Portal using your RHNID.

## Getting credentials (basic)

Visit the portal and get the credentials: [openshift.com/try](https://openshift.com/try)


## Getting credentials with CI Registry

'CI registry' is a image registry that holds the most recent images from CI builds.

If you want to test a recent release you that was not yet delivered, you may want to run those steps.

**Those steps will be restrict only for OpenShift developers.**

References:

- [OpenShift CI Registry documentation](https://registry.ci.openshift.org/)
- [OpenShift release sample for dev-preview](https://mirror2.openshift.com/pub/openshift-v4/x86_64/clients/ocp-dev-preview/latest-4.10/release.txt)


Steps:

- Set env vars

``` shell
TS="$(date +%Y%m%d%H%M)"
BASE_DIR="${HOME}/.openshift"
export PULL_SECRET_BKP="${BASE_DIR}/pull-secret-${TS}-bkp.json"
export PULL_SECRET_CI="${BASE_DIR}/pull-secret-${TS}-ci.json"
export PULL_SECRET="${BASE_DIR}/pull-secret-${TS}.json"
export PULL_SECRET_LATEST_LINK="${BASE_DIR}/pull-secret-latest.json"
mkdir -p ${BASE_DIR}
```

- Download the pull secret from portal and save it on `${PULL_SECRET_BKP}`

Direct link to [AWS IPI](https://console.redhat.com/openshift/install/aws/installer-provisioned)

- [Login to CI Cluster to retrieve a token](https://oauth-openshift.apps.ci.l2s4.p1.openshiftapps.com/oauth/token/display)

- Login on CLI using the token provided

Example:
```bash
oc login --token=<my token> --server=https://api.ci.l2s4.p1.openshiftapps.com:6443
```

- Get CI Credentials

```bash
cp ${PULL_SECRET_BKP} ${PULL_SECRET_CI}
oc registry login --to=${PULL_SECRET_CI}
```

- Merge CI credentials

```bash
cat ${PULL_SECRET_CI} |awk -v ORS= -v OFS= '{$1=$1}1' > ${PULL_SECRET}
```

- Check your credentials

Inspect:
```bash
jq . ${PULL_SECRET}
```

Use the credentials bundle on installer configuration:
```bash
cat ${PULL_SECRET}
```

- Link to latest (optional)

```bash
ln -svf ${PULL_SECRET} ${PULL_SECRET_LATEST_LINK}
```
