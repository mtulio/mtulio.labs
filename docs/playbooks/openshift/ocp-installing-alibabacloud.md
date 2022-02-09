# OCP IPI install on AlibabaCloud

This article describe how to install OpenShift Countainer Platform in Alibaba Cloud (`alibabacloud`) provider using IPI.

## Setup

Accounts:
- OpenShift 4.10+ (Tech-Preview)
- OCP installer credentials ('pull-secret')
- valid AlibabaCloud account

Packages to be installed:
- OpenShift Installer (openshift-installer)
- OpenShift client (oc)
- jq/yq
- ccoctl

Environment variables should be set

- `CLUSTER_NAME` : cluster name used when creating the install-config. It will be used to prefix resource names
- `REGION` : AlibabaCloud region to setup resources. Should be the same used on install-config.
- `PULL_SECRET` : path to credentials downloaded from Cloud Console.(ToDo provide a link)
- `INSTALL_DIR` : installation directory
- `ALIBABA_CLOUD_ACCESS_KEY_ID` : AlibabaCloud access key for programatic access
- `ALIBABA_CLOUD_ACCESS_KEY_SECRET`: AlibabaCloud secret key for programatic access

## create install config

- Create the base install-config

```bash
./openshift-install \
  create install-config --dir ${INSTALL_DIR}
```

- Copy the base config to be customized

```bash
cp ${INSTALL_DIR}/install-config.yaml ${PWD}/install-config-base.yaml
```

## Customize the configuration

You can skip this section if you don't want to customize the configuration

### Network customization: using existing VPC

Installer option: `platform.alibabacloud.vpcID`

- Set the env vars:

```bash
VPC_NAME="${CLUSTER_NAME}-vpc"
VPC_CIDR_BLOCK="10.0.0.0/16"
```

- Create the VPC

```bash
aliyun vpc CreateVpc \
    --RegionId "${REGION}" \
    --CidrBlock "${VPC_CIDR_BLOCK}" \
    --Description "OpenShift Cluster VPC" \
    --VpcName "${VPC_NAME}"
```

- Get the VPC_ID

```bash
VPC_ID="$(aliyun vpc DescribeVpcs \
    --RegionId "${REGION}" \
    --VpcName ${VPC_NAME} \
    |jq -r '.Vpcs.Vpc[].VpcId')"
echo ${VPC_ID}
```

- Update the installer-config with VPC_ID

```bash
# Update the config
yq -y --in-place \
  ".platform.alibabacloud.vpcID=\"${VPC_ID}\"" \
  ${INSTALL_DIR}/install-config.yaml

# Check it
yq .platform.alibabacloud.vpcID ${INSTALL_DIR}/install-config.yaml
```

### Network customization: using existing VSwitch

Installer option: `platform.alibabacloud.vswitchIDs`

- Create the VPC (section above)

- Create the vSwitchs on zones A and B

```bash
# A
ZONE_A_ID="${REGION}a"
ZONE_A_CIDR="10.0.0.0/20"
aliyun vpc CreateVSwitch \
  --RegionId "${REGION}"\
  --VpcId "${VPC_ID}" \
  --CidrBlock "${ZONE_A_CIDR}"  \
  --ZoneId "${ZONE_A_ID}" \
  --Description "vSwitch for cluster ${CLUSTER_NAME}"\
  --VSwitchName "${CLUSTER_NAME}-vsw-a"

# B
ZONE_B_ID="${REGION}b"
ZONE_B_CIDR="10.0.16.0/20"
aliyun vpc CreateVSwitch \
  --RegionId "${REGION}"\
  --VpcId "${VPC_ID}" \
  --CidrBlock "${ZONE_B_CIDR}"  \
  --ZoneId "${ZONE_B_ID}" \
  --Description "vSwitch for cluster ${CLUSTER_NAME}"\
  --VSwitchName "${CLUSTER_NAME}-vsw-b"

# A2
ZONE_A2_ID="${REGION}a"
ZONE_A2_CIDR="10.0.32.0/20"
aliyun vpc CreateVSwitch \
  --RegionId "${REGION}"\
  --VpcId "${VPC_ID}" \
  --CidrBlock "${ZONE_A2_CIDR}"  \
  --ZoneId "${ZONE_A2_ID}" \
  --Description "vSwitch for cluster ${CLUSTER_NAME}"\
  --VSwitchName "${CLUSTER_NAME}-vsw-a2"

# B2
ZONE_B2_ID="${REGION}b"
ZONE_B2_CIDR="10.0.64.0/20"
aliyun vpc CreateVSwitch \
  --RegionId "${REGION}"\
  --VpcId "${VPC_ID}" \
  --CidrBlock "${ZONE_B2_CIDR}"  \
  --ZoneId "${ZONE_B2_ID}" \
  --Description "vSwitch for cluster ${CLUSTER_NAME}"\
  --VSwitchName "${CLUSTER_NAME}-vsw-b2"
```

- Get the resources ID

```bash
# VSwitchs
VSW_A=$(aliyun vpc DescribeVSwitches \
  --RegionId "${REGION}"\
  --VSwitchName "${CLUSTER_NAME}-vsw-a" \
  | jq -r .VSwitches.VSwitch[].VSwitchId
)
VSW_B=$(aliyun vpc DescribeVSwitches \
  --RegionId "${REGION}"\
  --VSwitchName "${CLUSTER_NAME}-vsw-b" \
  | jq -r .VSwitches.VSwitch[].VSwitchId
)

echo "${VSW_A} ${VSW_B}"
```

- Create EIP for NatGW

```bash
aliyun vpc AllocateEipAddress \
  --RegionId "${REGION}" \
  --Name "natgw" \
  --InternetChargeType PayByTraffic > out.json
eip_id=$(jq -r '.AllocationId' out.json)
eip_addr=$(jq -r '.EipAddress' out.json)
```

- Create the NatGW for each Zone (vSwitch) (ToDo]

```bash
# AZ A
aliyun vpc CreateNatGateway \
  --RegionId "${REGION}" \
  --VpcId "${VPC_ID}" \
  --Name "${CLUSTER_NAME}-natgw" \
  --AutoPay false \
  --IcmpReplyEnabled true \
  --InstanceChargeType "PostPaid" \
  --InternetChargeType "PayByLcu" \
  --NatType "Enhanced" \
  --NetworkType "internet" \
  --SecurityProtectionEnabled false \
  --VSwitchId ${VSW_A} \
  --Description "NatGW for VPC ${VPC_NAME}"

```

- Get NatGW ID
```bash
# VSwitchs
NGW=$(aliyun ecs DescribeNatGateways \
  --RegionId "${REGION}" \
  --VpcId "${VPC_ID}" |jq -r .NatGateways.NatGateway[].NatGatewayId
)

echo "${NGW}"

NGW_SNAT_TB_ID="$(
  aliyun vpc GetNatGatewayAttribute  --NatGatewayId $NGW |jq -r .SnatTable.SnatTableId
)"
```

- create eip
```bash
aliyun vpc AssociateEipAddress \
  --RegionId "${REGION}" \
  --AllocationId ${eip_id} \
  --InstanceType 'Nat' \
  --InstanceId "${NGW}"
```

- associate SNAT entries for each vsw

```bash
aliyun vpc CreateSnatEntry \
  --RegionId "${REGION}" \
  --SnatIp ${eip_addr} \
  --SnatTableId ${NGW_SNAT_TB_ID} \
  --SnatEntryName "SNAT-VSW-A" \
  --SourceVSwitchId "${VSW_A}"

aliyun vpc CreateSnatEntry \
  --RegionId "${REGION}" \
  --SnatIp ${eip_addr} \
  --SnatTableId ${NGW_SNAT_TB_ID} \
  --SnatEntryName "SNAT-VSW-B" \
  --SourceVSwitchId "${VSW_B}"
```


- Update the installer-config with VPC_ID

```bash
# Update the config
yq -y --in-place \
  ".platform.alibabacloud.vpcID=\"${VPC_ID}\"" \
  ${INSTALL_DIR}/install-config.yaml
yq -y --in-place \
  ".platform.alibabacloud.vswitchIDs=[\"${VSW_A}\",\"${VSW_B}\"]" \
  ${INSTALL_DIR}/install-config.yaml

# Check it
yq .platform.alibabacloud ${INSTALL_DIR}/install-config.yaml
```

### Restricted network customization

Dependencies:

- crete VPC with NatGW

Steps:

- Create SG

```bash
aliyun ecs CreateSecurityGroup \
  --RegionId "${REGION}" \
  --Description "mirror-registry" \
  --SecurityGroupName "mirrorregistry" \
  --VpcId "${VPC_ID}"

SG_ID="$(
  aliyun ecs DescribeSecurityGroups --SecurityGroupName "mirrorregistry" |jq -r .SecurityGroups.SecurityGroup[].SecurityGroupId
)"

aliyun ecs AuthorizeSecurityGroup \
  --RegionId "${REGION}" \
  --SecurityGroupId "${SG_ID}" \
  --IpProtocol "tcp" \
  --PortRange 22/22 \
  --SourceCidrIp "0.0.0.0/0"

# Quay
aliyun ecs AuthorizeSecurityGroup \
  --RegionId "${REGION}" \
  --SecurityGroupId "${SG_ID}" \
  --IpProtocol "tcp" \
  --PortRange 8443/8443 \
  --SourceCidrIp "0.0.0.0/0"

# docker registry
aliyun ecs AuthorizeSecurityGroup \
  --RegionId "${REGION}" \
  --SecurityGroupId "${SG_ID}" \
  --IpProtocol "tcp" \
  --PortRange 5000/5000 \
  --SourceCidrIp "0.0.0.0/0"
```

- create key par

```bash
aliyun ecs ImportKeyPair \
  --RegionId "${REGION}" \
  --KeyPairName "$(whoami)" \
  --PublicKeyBody "$(cat ${HOME}/.ssh/id_rsa.pub)"
```

- Create a mirror instance / local registry

```bash
# image: CentOS 8
#image_id="m-0xi73vgiftq4g73n6vpl"
# Fedora
image_id="fedora_34_1_x64_20G_alibase_20211028.vhd"
instance_name="mirror-registry2"
aliyun ecs CreateInstance \
  --InstanceType "ecs.g6.large" \
  --RegionId "${REGION}" \
  --Description "${instance_name}" \
  --HostName "${instance_name}" \
  --ImageId "${image_id}" \
  --InstanceName "${instance_name}" \
  --SecurityGroupId "${SG_ID}" \
  --VSwitchId "${VSW_A}" \
  --KeyPairName "$(whoami)" \
  --SystemDisk.Size "1024G"

IID=$(aliyun ecs DescribeInstances --InstanceName "${instance_name}"  |jq -r .Instances.Instance[].InstanceId)

aliyun ecs StartInstance --InstanceId $IID

aliyun vpc AllocateEipAddress \
  --RegionId "${REGION}" \
  --Name "${instance_name}" \
  --InternetChargeType PayByTraffic > out_inst.json
eip_inst_id=$(jq -r '.AllocationId' out_inst.json)
eip_inst_addr=$(jq -r '.EipAddress' out_inst.json)

aliyun ecs AssociateEipAddress \
  --RegionId "${REGION}" \
  --AllocationId ${eip_inst_id} \
  --InstanceId "${IID}"
```


#### Install the local registry with "mirror-registry" tool

> NOTE: this step is not working properly. Jump to use docker-registry tool

Reference:
 - https://docs.openshift.com/container-platform/4.9/installing/installing-mirroring-installation-images.html#mirror-registry
 - https://docs.openshift.com/container-platform/4.9/installing/installing_aws/installing-restricted-networks-aws-installer-provisioned.html

- Download the image-registry tool

- Install dependences

Fix Alibaba repos to use upstream (local repo is failing):

```bash
sed -i 's/^#mirror/mirror/' /etc/yum.repos.d/*.repo 
sed -i 's/^baseurl/#baseurl/' /etc/yum.repos.d/*.repo 
```

- install dependencies and mirror-registry
```
sudo dnf install podman.x86_64
sudo ./mirror-registry install -v
```

Download the OC cli:

```bash
wget https://openshift-release-artifacts.apps.ci.l2s4.p1.openshiftapps.com/4.10.0-rc.0/openshift-client-linux-4.10.0-rc.0.tar.gz
tar xvfz openshift-client-linux-4.10.0-rc.0.tar.gz
```

Export release image:
- from: https://openshift-release-artifacts.apps.ci.l2s4.p1.openshiftapps.com/4.10.0-rc.0/release.txt

```bash
export OCP_RELEASE="quay.io/openshift-release-dev/ocp-release@sha256:be7ff17230199b5c0ee9cd48a932ceb06145ced8fec1c7d31bfe2e1a36746830"
export OCP_RELEASE_TAG="$(echo ${OCP_RELEASE} | cut -d: -f2)"

#export OCP_LOCAL_RELEASE_BASE="${LOCAL_REGISTRY_IP}:8443/ocp/release"
export REPO="${LOCAL_REGISTRY_IP}:8443/ocp"
export OCP_LOCAL_RELEASE_BASE="${REPO}/release"
export OCP_LOCAL_RELEASE_IMAGE="${OCP_LOCAL_RELEASE}:latest"

export LOCAL_REGISTRY_PASS="<pass>"
```

Add the credentials to pull-secret.txt:

```bash
LOCAL_PASS=$(echo -n "init:<my-secret>" | base64 -w0)

# add ${OCP_LOCAL_RELEASE} to pull-secret:
"$OCP_LOCAL_RELEASE": {
  "auth": "${LOCAL_PASS}"
}
```

login to registry
```bash
podman login --authfile pull-secret.txt \
  -u init \
  -p ${LOCAL_REGISTRY_PASS} \
  ${LOCAL_REGISTRY_IP}:8443 \
  --tls-verify=false 
```

mirror the local release

```bash
./oc adm -a pull-secret.txt release mirror \
  --insecure=true \
  --from=${OCP_RELEASE} \
  --to=${OCP_LOCAL_RELEASE_BASE}
  | tee mirror.out
```


#### Install the local registry with "docker-registry" tool

Install docker registry:

```bash
export LOCAL_REGISTRY_IP="$(nmcli d show eth0 |grep ^IP4.ADDRESS |awk '{print$2}' |sed 's/\/.*//')"

CERT_PATH="/opt/registry/certs"
mkdir -p ${CERT_PATH}

CERT_KEY="${CERT_PATH}/server.key"
CERT_CRT="${CERT_PATH}/server.crt"

echo "Generating following cert files: "
echo " - key : ${CERT_KEY}"
echo " - cert: ${CERT_CRT}"

openssl genrsa -out ${CERT_KEY} 2048

openssl req -new -x509 -sha256 \
    -key ${CERT_KEY} \
    -out ${CERT_CRT} -days 3650


# httpasswd
sudo yum install httpd-tools -y
AUTH_PATH="/opt/registry/auth"
DATA_PATH="/opt/registry/data"
mkdir -p $AUTH_PATH
mkdir -p $DATA_PATH

USER_NAME_REGISTRY="user"
USER_PASS_REGISTRY="myp@ss"
htpasswd -c -B -b ${AUTH_PATH}/htpasswd ${USER_NAME_REGISTRY} ${USER_PASS_REGISTRY}
USER_ENC=$(echo -n "${USER_NAME_REGISTRY}:${USER_PASS_REGISTRY}" | base64 -w0)

podman run \
  --name docker-registry -p 5000:5000 \
  -v /opt/registry/data:/var/lib/registry:z \
  -v ${AUTH_PATH}:/auth \
  -e "REGISTRY_AUTH=htpasswd" \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  -v /opt/registry/certs:/certs:z \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/server.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/server.key \
  -d registry:2
```

Update the Pull secret with credentials
```bash
jq -r ".auths[\"${LOCAL_REGISTRY_IP}:5000\"]={\"auth\":\"$USER_ENC\"}" pull-secret.txt > pull-secret-new.txt
```

Test logging to the registry:
```bash
podman login --authfile pull-secret-new.txt -u ${USER_NAME_REGISTRY} -p ${USER_PASS_REGISTRY} --tls-verify=false ${LOCAL_REGISTRY_IP}:5000
```

Mirror to docker-registry:
```
./oc adm -a pull-secret-new.txt release mirror \
  --insecure=true \
  --from=${OCP_RELEASE} \
  --to="${LOCAL_REGISTRY_IP}:5000/ocp"
```

To use the new mirrored repository to install, add the following section to the install-config.yaml:
```yaml
imageContentSources:
- mirrors:
  - 10.0.13.85:5000/ocp
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - 10.0.13.85:5000/ocp
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev

```

> ToDo setup a proxy

## Run the installation

### create manifests

```bash
./openshift-install create manifests \
  --log-level debug --dir ${INSTALL_DIR}
```

### create RAM users for CCO

- Extract credential requests from the release

```bash
./oc adm release extract \
  -a "${PULL_SECRET}" \
  --credentials-requests \
  --cloud=alibabacloud \
  --to="${PWD}/cco-credrequests" \
  "${OCP_RELEASE}"

```

- Create the AlibabaCloud RAM Users for each component (CredentialRequest)

```bash
./ccoctl \
   alibabacloud \
   create-ram-users \
  --region ${ALIBABA_REGION_ID} \
  --name $(awk '/infrastructureName:/{print $2}' ${INSTALL_DIR}/manifests/cluster-infrastructure-02-config.yml) \
  --credentials-requests-dir ${PWD}/cco-credrequests \
  --output-dir ${PWD}/cco-manifests

cp -v ${PWD}/cco-manifests/manifests/* ${INSTALL_DIR}/manifests/
```

### create cluster

- Install the cluster
```bash
./openshift-install create cluster \
  --log-level debug --dir ${INSTALL_DIR}
```

- Check the installation

```bash
oc get nodes
oc get clusteroperators
oc get machines -n openshift-machine-api
oc get clusterversion
```

## Destroy the cluster

### Remove CCO user

Remove AlibabaCloud RAM users created by CCO.

- Get the cluster Id


```bash
# Change to yours
CLUSTER_ID="ocpte-85kdk"
```

- Remove RAM users

```bash
./ccoctl alibabacloud delete-ram-users \
  --name=${CLUSTER_ID} \
  --region=${REGION} 
```

### Destroy the cluster

```bash
./openshift-install destroy cluster \
  --log-level debug --dir ${INSTALL_DIR}
```

## References

- [openshift/installer config Schema](https://github.com/openshift/installer/blob/master/data/data/install.openshift.io_installconfigs.yaml#L1130)
