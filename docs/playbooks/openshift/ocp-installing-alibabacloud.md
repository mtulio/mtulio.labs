# Install OpenShift in AlibabaCloud in an existing VPC

## Overview

This article describes the steps to create the network resources (VPC and VSwitchs) to install OpenShift Container Platform 4.10+ in Alibaba Cloud (`alibabacloud`) provider using IPI.

---
## Requirements

You must have:

- A valid AlibabaCloud account with a RAM User with valid Access Keys exported to [`~/.alibabacloud/credentials`](https://www.alibabacloud.com/help/en/doc-detail/311667.htm#h2-sls-mfm-3p3)
- A valid OpenShift cloud credentials ('pull-secret')

The following packages must be installed:

- [AliCloud CLI (aliyun)](https://github.com/aliyun/aliyun-cli#installation)
- OpenShift Installer (openshift-installer)
- OpenShift client (oc)
- OpenShift Cloud Credential Operator Utility (ccoctl)
- [jq](https://stedolan.github.io/jq/download/)
- [yq](https://github.com/mikefarah/yq)

The steps described in this document was tested on the following versions:

~~~bash
$ ./openshift-install version
./openshift-install 4.10.0-rc.0

$ ./oc version
Client Version: 4.10.0-rc.0
Kubernetes Version: v1.22.3+fdba464

$ aliyun version
3.0.99

$ jq --version
jq-1.5

$ yq --version
yq 2.12.0
~~~

### Environment variables

The following environment variables must be set:

- `CLUSTER_NAME`: cluster name used when creating the install-config. It will be used to prefix resource names
- `REGION` : AlibabaCloud region to setup resources. Should be the same used on install-config.
- `PULL_SECRET`: path to credentials downloaded from Cloud Console.
- `INSTALL_DIR`: installation directory
- `OCP_RELEASE`: OCP Release to be used. Example: `quay.io/openshift-release-dev/ocp-release:4.10.0-rc.0-x86_64`

___
## Create the install config

- Create the base install-config

~~~bash
./openshift-install \
  create install-config --dir ${INSTALL_DIR}
~~~

- Copy the base config to be customized

~~~bash
cp ${INSTALL_DIR}/install-config.yaml ${PWD}/install-config-base.yaml
~~~

___
## Customize the configuration

Steps customize the OpenShift installation on AlibabaCloud creating the network resources, then updating the proper configuration on installer config.

There are two network customizations described in this section:

- Create a custom VPC
- Create a custom VPC and VSwtiches

### Network customization: using existing VPC

Steps to create a custom VPC using AlibabaCloud utility (aliyun), to be used on OpenShift installer.

Installer option: `platform.alibabacloud.vpcID`

- Set the env vars:

~~~bash
VPC_NAME="${CLUSTER_NAME}-vpc"
VPC_CIDR_BLOCK="10.0.0.0/16"
~~~

- Create the VPC

~~~bash
aliyun vpc CreateVpc \
    --RegionId "${REGION}" \
    --CidrBlock "${VPC_CIDR_BLOCK}" \
    --Description "OpenShift Cluster VPC" \
    --VpcName "${VPC_NAME}"
~~~

- Get the VPC_ID

~~~bash
VPC_ID="$(aliyun vpc DescribeVpcs \
    --RegionId "${REGION}" \
    --VpcName ${VPC_NAME} \
    |jq -r '.Vpcs.Vpc[].VpcId')"
echo ${VPC_ID}
~~~

- Update the installer-config with VPC_ID

Update the config:

~~~bash
yq -y --in-place \
  ".platform.alibabacloud.vpcID=\"${VPC_ID}\"" \
  ${INSTALL_DIR}/install-config.yaml
~~~

Check the change:

~~~bash
yq .platform.alibabacloud.vpcID ${INSTALL_DIR}/install-config.yaml
~~~

At this point, the VPC was created and the install-config is updated. The VSwitch creation is not required, you can move to section ["Run the installation"](#run-the-installation) if the goal is not to customize the VSwitches, then the installer will create the required network assets automatically.

### Network customization: using existing VSwitch

Steps to create the custom VSwitchs into two Availability Zones in AlibabaCloud using the cli `aliyun`.

Installer option: `platform.alibabacloud.vswitchIDs`

- Create the VPC: the section above is required to continue (section above)

- Create the vSwitchs on zones A and B

Zone A:

~~~bash
VSW_A_ZONE="${REGION}a"
VSW_A_CIDR="10.0.0.0/20"
VSW_A_NAME="${CLUSTER_NAME}-vsw-a"

aliyun vpc CreateVSwitch \
  --RegionId "${REGION}"\
  --VpcId "${VPC_ID}" \
  --CidrBlock "${VSW_A_CIDR}"  \
  --ZoneId "${VSW_A_ZONE}" \
  --Description "vSwitch for cluster ${CLUSTER_NAME}"\
  --VSwitchName "${VSW_A_NAME}"
~~~

Zone B:

~~~bash
VSW_B_ZONE="${REGION}b"
VSW_B_CIDR="10.0.16.0/20"
VSW_B_NAME="${CLUSTER_NAME}-vsw-b"

aliyun vpc CreateVSwitch \
  --RegionId "${REGION}"\
  --VpcId "${VPC_ID}" \
  --CidrBlock "${VSW_B_CIDR}"  \
  --ZoneId "${VSW_B_ZONE}" \
  --Description "vSwitch for cluster ${CLUSTER_NAME}"\
  --VSwitchName "${VSW_B_NAME}"
~~~

- Get the vSwitches IDs

~~~bash
VSW_A_ID=$(aliyun vpc DescribeVSwitches \
  --RegionId "${REGION}"\
  --VSwitchName "${CLUSTER_NAME}-vsw-a" \
  | jq -r .VSwitches.VSwitch[].VSwitchId
)
VSW_B_ID=$(aliyun vpc DescribeVSwitches \
  --RegionId "${REGION}"\
  --VSwitchName "${CLUSTER_NAME}-vsw-b" \
  | jq -r .VSwitches.VSwitch[].VSwitchId
)

echo "${VSW_A} ${VSW_B}"
~~~

- Create EIP for NatGW

~~~bash
OUT="out-eip-natgw.json"
aliyun vpc AllocateEipAddress \
  --RegionId "${REGION}" \
  --Name "natgw" \
  --InternetChargeType PayByTraffic > ${OUT}

NATGW_EIP_ID=$(jq -r '.AllocationId' ${OUT})
NATGW_EIP_ADDR=$(jq -r '.EipAddress' ${OUT})
~~~

- Create the Nat Gateway

~~~bash
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
  --VSwitchId ${VSW_A_ID} \
  --Description "NatGW for VPC ${VPC_NAME}"
~~~

- Get Nat Gateway resources identifiers

Nat Gateway ID:

~~~bash
NATGW_ID=$(aliyun ecs DescribeNatGateways \
  --RegionId "${REGION}" \
  --VpcId "${VPC_ID}" |jq -r .NatGateways.NatGateway[].NatGatewayId
)

echo "${NATGW_ID}"
~~~

Get the SNAT Table ID:

~~~bash
NATGW_SNAT_TB_ID="$(aliyun vpc GetNatGatewayAttribute \
    --NatGatewayId $NATGW_ID |jq -r .SnatTable.SnatTableId
)"
~~~

- Associate EIP to the Nat Gateway

> You may need to wait for the Nat Gateway to finish the creation, otherwise, the following error message will be raised:
> `NatGateway [$NATGW_ID] status is invalid.`

~~~bash
aliyun vpc AssociateEipAddress \
  --RegionId "${REGION}" \
  --AllocationId ${NATGW_EIP_ID} \
  --InstanceType 'Nat' \
  --InstanceId "${NATGW_ID}"
~~~

- Associate SNAT entries for each VSwitch

~~~bash
aliyun vpc CreateSnatEntry \
  --RegionId "${REGION}" \
  --SnatIp ${NATGW_EIP_ADDR} \
  --SnatTableId ${NATGW_SNAT_TB_ID} \
  --SnatEntryName "SNAT-VSW-A" \
  --SourceVSwitchId "${VSW_A_ID}"

aliyun vpc CreateSnatEntry \
  --RegionId "${REGION}" \
  --SnatIp ${NATGW_EIP_ADDR} \
  --SnatTableId ${NATGW_SNAT_TB_ID} \
  --SnatEntryName "SNAT-VSW-B" \
  --SourceVSwitchId "${VSW_B_ID}"
~~~


- Update the installer-config with VPC_ID

Update the config:

~~~bash
yq -y --in-place \
  ".platform.alibabacloud.vpcID=\"${VPC_ID}\"" \
  ${INSTALL_DIR}/install-config.yaml
yq -y --in-place \
  ".platform.alibabacloud.vswitchIDs=[\"${VSW_A_ID}\",\"${VSW_B_ID}\"]" \
  ${INSTALL_DIR}/install-config.yaml
~~~

Check it:

~~~bash
yq .platform.alibabacloud ${INSTALL_DIR}/install-config.yaml
~~~

___
## Run the installation

### Create manifests

~~~bash
./openshift-install create manifests \
  --log-level debug --dir ${INSTALL_DIR}
~~~

### Create RAM users for CCO

To setup CCO in manual mode, the Resource Access Management (RAM) Users need to be created and each Access Key ID will be created for each OpenShift component needs to interact with Cloud Provider.

Those steps extract CredentialRequests from the release and process each one creating the required policy for each RAM User.

- Extract credential requests from the release

~~~bash
./oc adm release extract \
  -a "${PULL_SECRET}" \
  --credentials-requests \
  --cloud=alibabacloud \
  --to="${PWD}/cco-credrequests" \
  "${OCP_RELEASE}"
~~~

- Create the AlibabaCloud RAM Users for each component (CredentialRequest)

~~~bash
./ccoctl \
   alibabacloud \
   create-ram-users \
  --region ${REGION} \
  --name $(awk '/infrastructureName:/{print $2}' ${INSTALL_DIR}/manifests/cluster-infrastructure-02-config.yml) \
  --credentials-requests-dir ${PWD}/cco-credrequests \
  --output-dir ${PWD}/cco-manifests

cp -v ${PWD}/cco-manifests/manifests/* ${INSTALL_DIR}/manifests/
~~~

### Create cluster

- Install the cluster:

~~~bash
./openshift-install create cluster \
  --log-level debug --dir ${INSTALL_DIR}
~~~

- Check the installation:

~~~bash
oc get nodes
oc get clusteroperators
oc get machines -n openshift-machine-api
oc get clusterversion
~~~

## Destroy the cluster

### Remove CCO user

Remove AlibabaCloud RAM users created by CCO.

- Remove RAM users:

~~~bash
./ccoctl alibabacloud delete-ram-users \
  --name=${CLUSTER_NAME} \
  --region=${REGION} 
~~~

### Destroy the cluster

~~~bash
./openshift-install destroy cluster \
  --log-level debug --dir ${INSTALL_DIR}
~~~

## References

- [openshift/installer config Schema](https://github.com/openshift/installer/blob/master/data/data/install.openshift.io_installconfigs.yaml#L1130)
