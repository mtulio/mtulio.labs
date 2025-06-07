# WIP | Installing OCP on AWS with customized cluster network MTU

!!! warning "STATE: Draft"
    This document is under development.

- Local Zones, regular

```sh

CLUSTER_NAME=aws-mtu-1k-03
INSTALL_DIR=${PWD}/installdir-${CLUSTER_NAME}
mkdir $INSTALL_DIR
cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: devcluster.openshift.com
platform:
  aws:
    region: us-east-1
    clusterNetworkMTU: 1100
compute:
- name: edge
  platform:
    aws:
      zones:
      - us-east-1-bos-1a
EOF

export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.15.0-ec.2-x86_64"
./openshift-install create manifests --dir $INSTALL_DIR



oc get network.config cluster -o json | jq .status
```

- Local Zones with higher MTU

- Local Zones, regular

```sh

CLUSTER_NAME=aws-mtu4-8k
INSTALL_DIR=${PWD}/installdir-${CLUSTER_NAME}
mkdir $INSTALL_DIR
cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
featureSet: CustomNoUpgrade
metadata:
  name: $CLUSTER_NAME
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: devcluster.openshift.com
platform:
  aws:
    region: us-west-2
    clusterNetworkMTU: 8901
compute:
- name: edge
  platform:
    aws:
      zones:
      - us-west-2-lax-1a
EOF

export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.15.0-ec.2-x86_64"
./openshift-install create manifests --dir $INSTALL_DIR


oc get network.config cluster -o json | jq .status
```


```sh
CLUSTER_NAME=mtu04
mkdir installer-$CLUSTER_NAME
cat << EOF > "installer-${CLUSTER_NAME}/install-config.yaml"
apiVersion: v1
baseDomain: devcluster.openshift.com
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform:
    aws:
      zones: us-east-1-nyc-1a
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 3
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetworkMTU: 1300
platform:
  aws:
    region: us-east-1
publish: External
EOF

./openshift-install create manifests -dir "installer${CLUSTER_NAME}"
```

```sh
CLUSTER_NAME=nomtuawsB
mkdir "installer-$CLUSTER_NAME"

cat << EOF > "installer-${CLUSTER_NAME}/install-config.yaml"
apiVersion: v1
baseDomain: devcluster.openshift.com
metadata:
  name: ${CLUSTER_NAME}
platform:
  aws:
    region: us-east-1
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
   $(cat ~/.ssh/id_rsa.pub)
EOF
./openshift-install create manifests -dir "installer${CLUSTER_NAME}"
```



```sh
CLUSTER_NAME=nomtuazure03
mkdir installer-$CLUSTER_NAME
cat << EOF > installer-${CLUSTER_NAME}/install-config.yaml 
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: splat.azure.devcluster.openshift.com
networking:
  clusterNetworkMTU: 1225
platform:
  azure:
    baseDomainResourceGroupName: os4-common
    cloudName: AzurePublicCloud
    outboundType: Loadbalancer
    region: eastus
EOF
./openshift-install create manifests -dir "installer${CLUSTER_NAME}"

```


## Final manual e2e

~~~sh
./openshift-install version

CLUSTER_NAME=mtu-edge-7k
INSTALL_DIR=${PWD}/installdir-${CLUSTER_NAME}
mkdir $INSTALL_DIR
cat << EOF > $INSTALL_DIR/install-config.yaml
apiVersion: v1
metadata:
  name: $CLUSTER_NAME
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: devcluster.openshift.com
networking:
  clusterNetworkMTU: 7000
platform:
  aws:
    region: us-west-2
compute:
- name: edge
  platform:
    aws:
      zones:
      - us-west-2-lax-1a
EOF

export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/openshift-release-dev/ocp-release:4.15.0-ec.1-x86_64"
./openshift-install create manifests --dir $INSTALL_DIR

# Check
$ yq ea .spec.defaultNetwork $INSTALL_DIR/manifests/cluster-network-03-config.yml
ovnKubernetesConfig:
  egressIPConfig: {}
  mtu: 7000
type: OVNKubernetes


# Install
./openshift-install create cluster --dir $INSTALL_DIR
~~~


## Pull images from internal registry to validate higher MTU between the zone and in the region

~~~sh
NODE_NAME=$(oc get nodes -l node-role.kubernetes.io/edge='' -o jsonpath={.items[0].metadata.name})
KPASS=$(cat ${INSTALL_DIR}/auth/kubeadmin-password)

API_INT=$(oc get infrastructures cluster -o jsonpath={.status.apiServerInternalURI})

oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "\
oc login --insecure-skip-tls-verify -u kubeadmin -p ${KPASS} ${API_INT}; \
podman login -u kubeadmin -p \$(oc whoami -t) image-registry.openshift-image-registry.svc:5000; \
podman pull image-registry.openshift-image-registry.svc:5000/openshift/tests"
~~~