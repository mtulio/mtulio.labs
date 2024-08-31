# Platform External Development Tips

The section described in this document describe the hard way to
resolve the dependencies and run the required steps to create a cluster using
Platform External with OpenShift CI scripts.

> TODO: move to container image.

## Requirements

- Define the path the openshift/release repository is cloned:

```sh
RELEASE_REPO=~/go/src/github.com/mtulio/release
PULL_SECRET_FILE=~/.openshift/pull-secret-latest.json
```

- Create a symbolic link to installer repository simulate the `upi-installer` image:

```sh
INSTALLER=${HOME}/go/src/github.com/mtulio/installer-upi
sudo ln -svf ${INSTALLER} /var/lib/openshift-install
```

- Install Clients (under `${HOME}/bin`):

```sh
# yq
wget -O ~/bin/yq3 https://github.com/mikefarah/yq/releases/download/3.4.0/yq_linux_amd64 && \
chmod u+x ~/bin/yq3

wget -O ~/bin/yq4 https://github.com/mikefarah/yq/releases/download/v4.34.1/yq_linux_amd64 && \
chmod u+x ~/bin/yq4

# butane
wget -O ~/bin/butane "https://github.com/coreos/butane/releases/download/v0.18.0/butane-x86_64-unknown-linux-gnu" &&\
chmod u+x ~/bin/butane
```

- Install AWS CLI:

```sh
# For AWS:
pip3 install awscli
```

- Export the variables to use the steps locally:

```sh
export STEP_WORKDIR=/tmp/local-op-$(cat /dev/random | env LC_CTYPE=C tr -cd 'a-f0-9' | head -c 6)
mkdir -v $STEP_WORKDIR
```

> NOTE: the `STEP_WORKDIR` will be used in the following steps.

## Section 1. Create the Configuration

- Run conf step:

```sh
export CLUSTER_PROFILE_DIR=$STEP_WORKDIR

export STEP_WORKDIR=$STEP_WORKDIR
export SHARED_DIR=$STEP_WORKDIR/shared
export ARTIFACT_DIR=$STEP_WORKDIR/artifact

export JOB_NAME=platform-external-install-aws
export BUILD_ID=000

# Export the variables used in the workflow
export STEP_WORKDIR=$STEP_WORKDIR
export SHARED_DIR=$STEP_WORKDIR/shared
export ARTIFACT_DIR=$STEP_WORKDIR/artifact

mkdir -vp $STEP_WORKDIR $SHARED_DIR $ARTIFACT_DIR

export PLATFORM_EXTERNAL_CCM_ENABLED=yes
export PROVIDER_NAME=aws
export BASE_DOMAIN=devcluster.openshift.com
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.15.0-rc.5-x86_64"

# Create the Install-Config.yaml
## TODO: use the ipi-conf

cat << EOF > ${SHARED_DIR}/install-config.yaml
apiVersion: v1
metadata:
  name: $(basename $STEP_WORKDIR)
platform:
  external: {}
pullSecret: '$(cat ${PULL_SECRET_FILE} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
EOF

bash -x $RELEASE_REPO/ci-operator/step-registry/platform-external/pre/init/platform-external-pre-init-commands.sh
bash -x $RELEASE_REPO/ci-operator/step-registry/platform-external/pre/conf/platform-external-pre-conf-commands.sh
bash -x $RELEASE_REPO/ci-operator/step-registry/platform-external/pre/conf/manifests/platform-external-pre-conf-manifests-commands.sh
```


## Section 2. Install the cluster

### Step:Pre

- Run AWS install with upi method:

```sh
export PROVIDER_NAME=aws
export AWS_REGION=us-east-1
export LEASED_RESOURCE=${AWS_REGION}

export BOOTSTRAP_INSTANCE_TYPE=m6i.xlarge
export MASTER_INSTANCE_TYPE=m6i.xlarge
export WORKER_INSTANCE_TYPE=m6i.xlarge
export OCP_ARCH=amd64

export PLATFORM_EXTERNAL_CCM_ENABLED=yes

mkdir -vp $STEP_WORKDIR $SHARED_DIR $ARTIFACT_DIR
ln -svf $HOME/.aws/credentials ${STEP_WORKDIR}/.awscred


bash -x $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/aws/install/platform-external-cluster-aws-install-commands.sh
```

- Wait for API UP on bootstrap

```sh
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/wait-for/api-bootstrap/platform-external-cluster-wait-for-api-bootstrap-commands.sh
```


## Section 3. Install CCM

```sh
bash -x $RELEASE_REPO/ci-operator/step-registry/platform-external/ccm/conf/aws/platform-external-ccm-conf-aws-commands.sh

bash -x $RELEASE_REPO/ci-operator/step-registry/platform-external/ccm/deploy/platform-external-ccm-deploy-commands.sh
```

- Wait for install complete:

```sh
bash -x $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/wait-for/ready/control/platform-external-cluster-wait-for-ready-control-commands.sh
bash -x $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/wait-for/ready/compute/platform-external-cluster-wait-for-ready-compute-commands.sh

bash -x $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/wait-for/complete/platform-external-cluster-wait-for-complete-commands.sh
```

- Destroy bootstrap

```sh
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/aws/destroy/bootstrap/platform-external-cluster-aws-destroy-bootstrap-commands.sh
```

### Step:Test

- RUn e2e:

```sh
export CLUSTER_TYPE=external
export TEST_CSI_DRIVER_MANIFEST=""
export TEST_TYPE=suite
export TEST_ARGS=""
export TEST_SUITE=openshift/conformance/parallel
export TEST_SKIPS=""

bash -x $RELEASE_REPO/ci-operator/step-registry/openshift/e2e/test/openshift-e2e-test-commands.sh

```

## Section Final. Destroy Environment

```sh
bash $RELEASE_REPO/ci-operator/step-registry/platform-external/cluster/aws/destroy/platform-external-cluster-aws-destroy-commands.sh
```