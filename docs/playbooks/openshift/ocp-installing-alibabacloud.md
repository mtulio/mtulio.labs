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
ZONE_ID="${REGION}a"
ZONE_CIDR="10.0.0.0/20"
aliyun vpc CreateVSwitch \
  --RegionId "${REGION}"\
  --VpcId "${VPC_ID}" \
  --CidrBlock "${ZONE_CIDR}"  \
  --ZoneId "${ZONE_ID}" \
  --Description "vSwitch for cluster ${CLUSTER_NAME}"\
  --VSwitchName "${CLUSTER_NAME}-vsw-a"

# B
ZONE_ID="${REGION}b"
ZONE_CIDR="10.0.16.0/20"
aliyun vpc CreateVSwitch \
  --RegionId "${REGION}"\
  --VpcId "${VPC_ID}" \
  --CidrBlock "${ZONE_CIDR}"  \
  --ZoneId "${ZONE_ID}" \
  --Description "vSwitch for cluster ${CLUSTER_NAME}"\
  --VSwitchName "${CLUSTER_NAME}-vsw-b"
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

- Create the NatGW and attach to VPC

```bash
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
  "${OPENSHIFT_INSTALL_RELEASE_IMAGE}"

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
oc get co
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
