# WIP | Installing OCP with Platform External on AWS with CCM using UPI model with CI scripts

!!! warning "STATE: Draft"
    This document is under development.

## AWS

- Set the workflow requirements:

```sh
export RELEASE_REPO=~/go/src/github.com/mtulio/release
export PULL_SECRET_FILE=~/.openshift/pull-secret-latest.json

export CLUSTER_NAME="local-op-$(cat /dev/random | env LC_CTYPE=C tr -cd 'a-f0-9' | head -c 5)"
export STEP_WORKDIR=/tmp/${CLUSTER_NAME}
mkdir -v $STEP_WORKDIR

# Export the variables used in the workflow
export STEP_WORKDIR=$STEP_WORKDIR
export SHARED_DIR=$STEP_WORKDIR/shared
export ARTIFACT_DIR=$STEP_WORKDIR/artifact
export PROFILE_DIR=$STEP_WORKDIR/profile
export CLUSTER_PROFILE_DIR=$PROFILE_DIR

mkdir -vp $STEP_WORKDIR $SHARED_DIR $ARTIFACT_DIR $CLUSTER_PROFILE_DIR

export PLATFORM_EXTERNAL_CCM_ENABLED=yes
export PROVIDER_NAME=aws
export BASE_DOMAIN=devcluster.openshift.com

export JOB_NAME=platform-external-install-aws
export BUILD_ID=000

export PROVIDER_NAME=aws
export AWS_REGION=us-east-1
export LEASED_RESOURCE=${AWS_REGION}

export BOOTSTRAP_INSTANCE_TYPE=m6i.xlarge
export MASTER_INSTANCE_TYPE=m6i.xlarge
export WORKER_INSTANCE_TYPE=m6i.xlarge
export OCP_ARCH=amd64

export PLATFORM_EXTERNAL_CCM_ENABLED=yes

ln -svf $HOME/.aws/credentials ${CLUSTER_PROFILE_DIR}/.awscred;
ln -svf $HOME/.ssh/id_rsa.pub ${CLUSTER_PROFILE_DIR}/ssh-publickey;

# Create the base Install-Config.yaml
cat << EOF > ${SHARED_DIR}/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
platform:
  external: {}
pullSecret: '$(cat ${PULL_SECRET_FILE} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
EOF

```

Installing by stages:

- Stage 1: OpenShift configuration:

> Mostly OpenShift. Shared responsability with provider when setting the MachineConfig to set the ProviderID to Kubelet

```sh
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/conf/platform-external-conf-commands.sh
```

- Stage 2: Infrastructure Provisioning (Provider's specific)

```sh
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/aws/install/platform-external-cluster-aws-install-commands.sh

bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/wait-for/api-bootstrap/platform-external-cluster-wait-for-api-bootstrap-commands.sh

```

- Stage 3: Cloud Controller Manager (CCM) Setup (Provider's specific)

```sh

bash $RELEASE_REPO/ci-operator/step-registry/platform-external/conf/ccm/aws/platform-external-conf-ccm-aws-commands.sh
```

- Final Stage: Wait for cluster installation finished

```sh
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/wait-for/install-complete/platform-external-cluster-wait-for-install-complete-commands.sh
```

Tests:

- Test Stage: openshift e2e (TODO)


Deprovision:

- Destroy Stage: Destroy infrastructure resources (Provider's specific)

```sh
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/aws/destroy/platform-external-cluster-aws-destroy-commands.sh
```


## OCI

- Set the workflow requirements:

```sh
export RELEASE_REPO=~/go/src/github.com/mtulio/release
export PULL_SECRET_FILE=~/.openshift/pull-secret-latest.json

export CLUSTER_NAME="local-op-$(cat /dev/random | env LC_CTYPE=C tr -cd 'a-f0-9' | head -c 5)"
export STEP_WORKDIR=/tmp/${CLUSTER_NAME}
mkdir -v $STEP_WORKDIR

# Export the variables used in the workflow
export STEP_WORKDIR=$STEP_WORKDIR
export SHARED_DIR=$STEP_WORKDIR/shared
export ARTIFACT_DIR=$STEP_WORKDIR/artifact
export PROFILE_DIR=$STEP_WORKDIR/profile
export CLUSTER_PROFILE_DIR=$PROFILE_DIR
export CUSTOM_PROFILE_DIR=${PROFILE_DIR}

mkdir -vp $STEP_WORKDIR $SHARED_DIR $ARTIFACT_DIR $CLUSTER_PROFILE_DIR $CUSTOM_PROFILE_DIR

export PLATFORM_EXTERNAL_CCM_ENABLED=yes
export PROVIDER_NAME=oci
export BASE_DOMAIN=us-ashburn-1.splat-oci.devcluster.openshift.com

export REGION=us-ashburn-1
export LEASED_RESOURCE=${AWS_REGION}

export JOB_NAME=platform-external-install-aws
export BUILD_ID=000

export BOOTSTRAP_INSTANCE_TYPE=tbd
export MASTER_INSTANCE_TYPE=tbd
export WORKER_INSTANCE_TYPE=tbd
export OCP_ARCH=tbd

export PLATFORM_EXTERNAL_CCM_ENABLED=yes

export OCI_CONFIG=${HOME}/.oci/ocp-ci/config
export OCI_COMPARTMENTS_ENV=${HOME}/.oci/compartments.env
# cat <<EOF > ${CUSTOM_PROFILE_DIR}/compartments.env
# # Compartment that the cluster will be installed
# OCI_COMPARTMENT_ID="ocid1.compartment.oc1..."

# # Compartment that the DNS Zone is created (based domain)
# # Only RR will be added
# OCI_COMPARTMENT_ID_DNS="ocid1.compartment.oc1..."

# # Compartment that the OS Image will be created
# OCI_COMPARTMENT_ID_IMAGE="ocid1.compartment.oc1..."
# EOF

#ln -svf $HOME/.aws/credentials ${CUSTOM_PROFILE_DIR}/.awscred;
ln -svf $HOME/.ssh/id_rsa.pub ${CUSTOM_PROFILE_DIR}/ssh-publickey;

# Create the base Install-Config.yaml
cat << EOF > ${SHARED_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: $CLUSTER_NAME
platform:
  external: {}
pullSecret: '$(cat ${PULL_SECRET_FILE} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
EOF
```

Installing by stages:

- Stage 1: OpenShift configuration:

> Mostly OpenShift. Shared responsability with provider when setting the MachineConfig to set the ProviderID to Kubelet

```sh
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/conf/platform-external-conf-commands.sh
```

- Stage 2: Infrastructure Provisioning (Provider's specific)

```sh
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/oci/install/platform-external-cluster-oci-install-commands.sh

bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/wait-for/api-bootstrap/platform-external-cluster-wait-for-api-bootstrap-commands.sh

```

- Stage 3: Cloud Controller Manager (CCM) Setup (Provider's specific)

```sh

bash $RELEASE_REPO/ci-operator/step-registry/platform-external/conf/ccm/aws/platform-external-conf-ccm-aws-commands.sh
```

- Final Stage: Wait for cluster installation finished

```sh
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/wait-for/install-complete/platform-external-cluster-wait-for-install-complete-commands.sh
```

Tests:

- Test Stage: openshift e2e (TODO)


Deprovision:

- Destroy Stage: Destroy infrastructure resources (Provider's specific)

```sh
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/aws/destroy/platform-external-cluster-aws-destroy-commands.sh
```

## OCI terraform

```sh

export RELEASE_REPO=~/go/src/github.com/mtulio/release
export PULL_SECRET_FILE=~/.openshift/pull-secret-latest.json

export CLUSTER_NAME="local-op-$(cat /dev/random | env LC_CTYPE=C tr -cd 'a-f0-9' | head -c 5)"
export STEP_WORKDIR=/tmp/${CLUSTER_NAME}
mkdir -v $STEP_WORKDIR

# Export the variables used in the workflow
export STEP_WORKDIR=$STEP_WORKDIR
export SHARED_DIR=$STEP_WORKDIR/shared
export ARTIFACT_DIR=$STEP_WORKDIR/artifact
export PROFILE_DIR=$STEP_WORKDIR/profile
export CLUSTER_PROFILE_DIR=$PROFILE_DIR
export CUSTOM_PROFILE_DIR=${PROFILE_DIR}

mkdir -vp $STEP_WORKDIR $SHARED_DIR $ARTIFACT_DIR $CLUSTER_PROFILE_DIR $CUSTOM_PROFILE_DIR

export PLATFORM_EXTERNAL_CCM_ENABLED=yes
export PROVIDER_NAME=oci
export BASE_DOMAIN=splat-oci.devcluster.openshift.com

export REGION=us-sanjose-1
export LEASED_RESOURCE=${AWS_REGION}

export JOB_NAME=platform-external-install-aws
export BUILD_ID=000

export BOOTSTRAP_INSTANCE_TYPE=tbd
export MASTER_INSTANCE_TYPE=tbd
export WORKER_INSTANCE_TYPE=tbd
export OCP_ARCH=tbd

export PLATFORM_EXTERNAL_CCM_ENABLED=yes

export OCI_CONFIG=${HOME}/.oci/ocp-ci/config
export OCI_COMPARTMENTS_ENV=${HOME}/.oci/compartments.env
# cat <<EOF > ${CUSTOM_PROFILE_DIR}/compartments.env
# # Compartment that the cluster will be installed
# OCI_COMPARTMENT_ID="ocid1.compartment.oc1..."

# # Compartment that the DNS Zone is created (based domain)
# # Only RR will be added
# OCI_COMPARTMENT_ID_DNS="ocid1.compartment.oc1..."

# # Compartment that the OS Image will be created
# OCI_COMPARTMENT_ID_IMAGE="ocid1.compartment.oc1..."
# EOF

#ln -svf $HOME/.aws/credentials ${CUSTOM_PROFILE_DIR}/.awscred;
ln -svf $HOME/.ssh/id_rsa.pub ${CUSTOM_PROFILE_DIR}/ssh-publickey;

# Create the base Install-Config.yaml
cat << EOF > ${SHARED_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: $CLUSTER_NAME
platform:
  external: {}
pullSecret: '$(cat ${PULL_SECRET_FILE} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
EOF

bash $RELEASE_REPO/ci-operator/step-registry/platform-external/conf/platform-external-conf-commands.sh

bash -x $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/oci/install/platform-external-cluster-oci-install-commands.sh

bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/wait-for/api-bootstrap/platform-external-cluster-wait-for-api-bootstrap-commands.sh

# CCM
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/ccm/conf/oci/platform-external-ccm-conf-oci-commands.sh

bash $RELEASE_REPO/ci-operator/step-registry/platform-external/ccm/deploy/platform-external-ccm-deploy-commands.sh

# install complete
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/wait-for/install-complete/platform-external-cluster-wait-for-install-complete-commands.sh

# Destroy
bash -x $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/oci/destroy/platform-external-cluster-oci-destroy-commands.sh
```