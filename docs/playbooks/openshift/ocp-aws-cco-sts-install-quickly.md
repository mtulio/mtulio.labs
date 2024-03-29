# OCP on AWS - Installing a cluster with STS quickly on AWS

Install the OCP cluster on AWS with manual Authentication with STS with a single command.

The motivation of this playbook is to create a default cluster with STS support running a single command, without customizations, avoiding following many steps - most used in laboratory environments as it is setting the installer to use a non-HA environment (single AZ).

## Steps

- Define the functions to create and destroy the cluster (copy/paste)

```bash

custom_vars() {
  cat<<'EOF'> ~/.env-ocp-sts-aws
export REGION=${CLUSTER_REGION:-'us-east-1'}
export VERSION=${CLUSTER_VERSION:-4.11.8}

export PULL_SECRET_FILE=${HOME}/.openshift/pull-secret-latest.json
export SSH_PUB_KEY_FILE="${HOME}/.ssh/id_rsa.pub"

export OUTPUT_DIR_CCO="${PWD}/${CLUSTER_NAME}-cco/"
export INSTALL_DIR="${PWD}/${CLUSTER_NAME}-installer"
EOF

}

install_clients() {
  echo "> Clients - checking existing clients [oc && openshift-install]"
  local need_install=false
  if [[ ! -x ./oc ]] || [[ ! -x ./openshift-install ]]
  then
    need_install=true
  fi

  if [[ $need_install == true ]]
  then
    echo ">> Clients - oc or openshift-install not found on the current dir, downloading..."
    oc adm release extract \
      --tools quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64 \
      -a ${PULL_SECRET_FILE}

    tar xvfz openshift-client-linux-${VERSION}.tar.gz
    tar xvfz openshift-install-linux-${VERSION}.tar.gz
  fi

  echo "> Clients - checking existing clients [ccoctl]"
  if [[ ! -x ./ccoctl ]]
  then
    echo ">> Clients - ccoctl not found on the current dir, downloading..."
    RELEASE_IMAGE=$(./openshift-install version | awk '/release image/ {print $3}')
    CCO_IMAGE=$(oc adm release info --image-for='cloud-credential-operator' $RELEASE_IMAGE)
    ./oc image extract $CCO_IMAGE --file="/usr/bin/ccoctl" -a ${PULL_SECRET_FILE}
    chmod 775 ccoctl
    #./ccoctl --help
  fi
}

cco_create() {
  echo "> CCO - Creating key-par"
  mkdir -p ${OUTPUT_DIR_CCO}
  ./ccoctl aws create-key-pair \
    --output-dir ${OUTPUT_DIR_CCO}

  echo "> CCO - Creating IdP"
  ./ccoctl aws create-identity-provider \
    --name=${CLUSTER_NAME} \
    --region=${REGION} \
    --public-key-file=${OUTPUT_DIR_CCO}/serviceaccount-signer.public \
    --output-dir=${OUTPUT_DIR_CCO}/

  echo "> CCO - Extracting CredentialsRequests from release payload"
  RELEASE_IMAGE=$(./openshift-install version | awk '/release image/ {print $3}')
  ./oc adm release extract --credentials-requests \
    --cloud=aws \
    --to=${OUTPUT_DIR_CCO}/credrequests \
    ${RELEASE_IMAGE}

  if [[ ! -d ${OUTPUT_DIR_CCO}/credrequests ]]; then
    echo "ERROR directory not found: ${OUTPUT_DIR_CCO}/credrequests"
    return 1
  fi

  sleep 5;
  AWS_IAM_OIDP_ARN=$(aws iam list-open-id-connect-providers \
      | jq -r ".OpenIDConnectProviderList[] | \
          select(.Arn | contains(\"${CLUSTER_NAME}-oidc\") ).Arn")
  echo "> CCO - Creating IAM Roles for IdP [${AWS_IAM_OIDP_ARN}]"
  ./ccoctl aws create-iam-roles \
    --name=${CLUSTER_NAME} \
    --region=${REGION} \
    --credentials-requests-dir=${OUTPUT_DIR_CCO}/credrequests \
    --identity-provider-arn=${AWS_IAM_OIDP_ARN} \
    --output-dir ${OUTPUT_DIR_CCO}

  echo "> CCO - Copying manifests to Install directory"
  cp -rvf ${OUTPUT_DIR_CCO}/manifests/* \
    ${INSTALL_DIR}/manifests
  cp -rvf ${OUTPUT_DIR_CCO}/tls \
    ${INSTALL_DIR}/
}

cco_destroy() {
  ./ccoctl aws delete \
    --name=${CLUSTER_NAME} \
    --region=${REGION}
}

setup_installer() {
  echo "> Creating install-config.yaml"
  # Create a single-AZ install config
  mkdir -p ${INSTALL_DIR}
  cat <<EOF | envsubst > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${CLUSTER_BASE_DOMAIN}
credentialsMode: Manual
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${REGION}
    defaultMachinePlatform:
      zones:
      - ${REGION}a
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF
  echo ">> install-config.yaml created: "
  cat ${INSTALL_DIR}/install-config.yaml
  ./openshift-install create manifests --dir $INSTALL_DIR --log-level=debug
}

patch_secrets_to_regional_endpoint() {
  echo "Patching Credentials secrets..."
  sed -i '/\[default\].*/a\'$'    sts_regional_endpoints = regional' $INSTALL_DIR/manifests/*-credentials.yaml
}

create_cluster() {
  CLUSTER_NAME=$1
  custom_vars
  source ~/.env-ocp-sts-aws
  install_clients
  setup_installer
  cco_create
  if [[ "${PATCH_SECRETS_REGIONAL:-}" == "true" ]]; then
    patch_secrets_to_regional_endpoint
  fi
  ./openshift-install create cluster --dir $INSTALL_DIR --log-level=debug
}

destroy_cluster() {
  source ~/.env-ocp-sts-aws
  ./openshift-install destroy cluster --dir $INSTALL_DIR --log-level=debug
  cco_destroy
}
```

- Create the cluster with the name "labsts":

```bash
CLUSTER_NAME="labsts07" &&\
  CLUSTER_BASE_DOMAIN="devcluster.openshift.com" &&\
  create_cluster $CLUSTER_NAME
```

- Create the cluster changing the default image:

```bash
CLUSTER_VERSION="4.11.10" &&\
  CLUSTER_NAME="labsts41110t1" &&\
  CLUSTER_BASE_DOMAIN="devcluster.openshift.com" &&\
  create_cluster $CLUSTER_NAME
```

- Create the cluster patching the Cloud Credential secrets to add the regional endpoint option:

```bash
PATCH_SECRETS_REGIONAL=true &&\
  CLUSTER_VERSION="4.12.0-ec.4" &&\
  CLUSTER_NAME="labsts4120ec4t1" &&\
  CLUSTER_BASE_DOMAIN="devcluster.openshift.com" &&\
  create_cluster $CLUSTER_NAME
```

- Destroy the cluster with the name "`$CLUSTER_NAME`":

```bash
destroy_cluster $CLUSTER_NAME
```

## Validation / Troubleshooting helper

Some *ready* commands to validate the STS Cluster:

- Check version
- Check IssuerURL pointing to OIDC
- Get the public keys from OIDC JWKS endpoint
- Check the secret presented to one Component (Example machine-controllers)


```bash
./oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig get clusterversion


./oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig get authentication -o json |jq -r .items[].spec.serviceAccountIssuer

curl -s $(./oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig get authentication -o json |jq -r .items[].spec.serviceAccountIssuer)/keys.json

./oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig get secrets -n openshift-machine-api aws-cloud-credentials -o json |jq -r .data.credentials |base64 -d

```

- Assume the IAM role using the projected service account token

> Required: aws and oc CLI, OCP and AWS admin grants

```bash
TOKEN_PATH=$(oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' |\
    base64 -d |\
    grep ^web_identity_token_file |\
    awk '{print$3}')

IAM_ROLE=$(oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' |\
    base64 -d |\
    grep ^role_arn |\
    awk '{print$3}')

CAPI_POD=$(oc get pods -n openshift-machine-api \
    -l api=clusterapi \
    -o jsonpath='{.items[*].metadata.name}')

TOKEN=$(oc exec -n openshift-machine-api \
        -c machine-controller ${CAPI_POD} \
        -- cat ${TOKEN_PATH})

aws sts assume-role-with-web-identity \
    --role-arn "${IAM_ROLE}" \
    --role-session-name "my-session" \
    --web-identity-token "${TOKEN}"
```

- Additionaly, check the common error patterns related to OIDC that could happen on the component logs:

> See more: [KCS6965924](https://access.redhat.com/solutions/6965924)

```bash
#./oc logs -n openshift-machine-api -c machine-controller machine-api-controllers-[redacted] | grep -c InvalidIdentityToken

./oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig logs -n openshift-image-registry -l name=cluster-image-registry-operator | grep -c InvalidIdentityToken

./oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig logs -n openshift-image-registry -l name=cluster-image-registry-operator | grep -c WebIdentityErr

./oc --kubeconfig ${INSTALL_DIR}/auth/kubeconfig logs -n openshift-image-registry -l name=cluster-image-registry-operator | grep -c 'Not authorized to perform sts:AssumeRoleWithWebIdentity\\nProgressing: \\tstatus code: 403'

```

- [Simulate IAM Role Permissions](./ocp-aws-cco-simulate-policy.md)

## References

- [Install a OCP Cluster with STS](#)
- [KCS: InvalidIdentityToken when installing OpenShift on AWS using manual authentication mode with STS](https://access.redhat.com/solutions/6965924)
- [KCS: Red Hat OpenShift Container Platform Machine Failed with error launching instance: You are not authorized to perform this operation](https://access.redhat.com/solutions/6969704)
