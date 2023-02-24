# OCP on AWS - Review CredentialsRequests provided by CCO

Steps to review the existing CredentialsRequests provided by CCO from a given OpenShift release version.

It will extract the CredentialsRequests from a release (required) versus the running on the cluster (secrets).

Steps:

- Get the credentials expected to the release

```bash
export VERSION=4.10.28
export CLUSTER_REGION=us-east-1
export CLUSTER_NAME="my-cluster"
export PULL_SECRET_FILE=${HOME}/.openshift/pull-secret-latest.json
export OUTPUT_DIR_CCO="${PWD}/${CLUSTER_NAME}-cco/"

oc adm release extract \
    --tools quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64 \
    -a ${PULL_SECRET_FILE}

tar xvfz openshift-client-linux-${VERSION}.tar.gz
tar xvfz openshift-install-linux-${VERSION}.tar.gz

RELEASE_IMAGE=$(./openshift-install version | awk '/release image/ {print $3}')
CCO_IMAGE=$(oc adm release info --image-for='cloud-credential-operator' $RELEASE_IMAGE)
./oc image extract $CCO_IMAGE --file="/usr/bin/ccoctl" -a ${PULL_SECRET_FILE}
chmod 775 ccoctl

./oc adm release extract --credentials-requests \
    --cloud=aws \
    --to=${OUTPUT_DIR_CCO}/credrequests \
    ${RELEASE_IMAGE}
```

- Check the credentials from the cluster

> Requires `yq` and `jq`

```bash
OC_CMD="oc"
COMMANDS=()
for file in $(ls ${OUTPUT_DIR_CCO}/credrequests/*.yaml); do
  s_name=$(yq -r .spec.secretRef.name $file) ;
  s_ns=$(yq -r .spec.secretRef.namespace $file) ;
  echo -e "\n# ${s_ns}/secret/${s_name}";
  cmd="${OC_CMD} get secret ${s_name} -n ${s_ns} -o json | jq -r .data.credentials | base64 -d"
  COMMANDS+=( "\n$cmd" );
  echo $cmd
  ${OC_CMD} get secret ${s_name} -n ${s_ns} -o json |jq -r .data.credentials |base64 -d
done

# Get the real's oc command (only when using 'omg')
echo -e "${COMMANDS[@]/${OC_CMD} /oc }"
```
