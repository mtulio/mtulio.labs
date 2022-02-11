# (DRAFT) Install OpenShift in AlibabaCloud in an restricted network

> This article was not validated (WIP) due the limitation when installing in restricted network reported in this BZ: https://bugzilla.redhat.com/show_bug.cgi?id=2046226

This article describes how to create a VPC and VSwitchs to install 
OpenShift Countainer Platform in Alibaba Cloud (`alibabacloud`) provider using IPI
with network customizations.

---
## Setup

See [the setup section](./ocp-installing-alibabacloud.md#setup)
___
## Create the install config

See [the Create install config section](./ocp-installing-alibabacloud.md#create-the-install-config)

___
## Customize the configuration

This section will describe how to customize the OpenShift installation
on AlibabaCloud creating the resources and updating the proper configuration
on installer configuration.

---
### Customization: Restricted network

> Note: that topic is not complete

Dependencies:

- crete VPC with NatGW

Steps:

- Create SG

~~~bash
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
~~~

- create key par

~~~bash
aliyun ecs ImportKeyPair \
  --RegionId "${REGION}" \
  --KeyPairName "$(whoami)" \
  --PublicKeyBody "$(cat ${HOME}/.ssh/id_rsa.pub)"
~~~

- Create a mirror instance / local registry

~~~bash
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
~~~

---
#### Install the local registry with "mirror-registry" tool

> NOTE: this step is not working properly. Jump to use docker-registry tool

Reference:
 - https://docs.openshift.com/container-platform/4.9/installing/installing-mirroring-installation-images.html#mirror-registry
 - https://docs.openshift.com/container-platform/4.9/installing/installing_aws/installing-restricted-networks-aws-installer-provisioned.html

- Download the image-registry tool

- Install dependences

Fix Alibaba repos to use upstream (local repo is failing):

~~~bash
sed -i 's/^#mirror/mirror/' /etc/yum.repos.d/*.repo 
sed -i 's/^baseurl/#baseurl/' /etc/yum.repos.d/*.repo 
~~~

- install dependencies and mirror-registry
~~~
sudo dnf install podman.x86_64
sudo ./mirror-registry install -v
~~~

Download the OC cli:

~~~bash
wget https://openshift-release-artifacts.apps.ci.l2s4.p1.openshiftapps.com/4.10.0-rc.0/openshift-client-linux-4.10.0-rc.0.tar.gz
tar xvfz openshift-client-linux-4.10.0-rc.0.tar.gz
~~~

Export release image:
- from: https://openshift-release-artifacts.apps.ci.l2s4.p1.openshiftapps.com/4.10.0-rc.0/release.txt

~~~bash
export OCP_RELEASE="quay.io/openshift-release-dev/ocp-release@sha256:be7ff17230199b5c0ee9cd48a932ceb06145ced8fec1c7d31bfe2e1a36746830"
export OCP_RELEASE_TAG="$(echo ${OCP_RELEASE} | cut -d: -f2)"

#export OCP_LOCAL_RELEASE_BASE="${LOCAL_REGISTRY_IP}:8443/ocp/release"
export REPO="${LOCAL_REGISTRY_IP}:8443/ocp"
export OCP_LOCAL_RELEASE_BASE="${REPO}/release"
export OCP_LOCAL_RELEASE_IMAGE="${OCP_LOCAL_RELEASE}:latest"

export LOCAL_REGISTRY_PASS="<pass>"
~~~

Add the credentials to pull-secret.txt:

~~~bash
LOCAL_PASS=$(echo -n "init:<my-secret>" | base64 -w0)

# add ${OCP_LOCAL_RELEASE} to pull-secret:
"$OCP_LOCAL_RELEASE": {
  "auth": "${LOCAL_PASS}"
}
~~~

login to registry
~~~bash
podman login --authfile pull-secret.txt \
  -u init \
  -p ${LOCAL_REGISTRY_PASS} \
  ${LOCAL_REGISTRY_IP}:8443 \
  --tls-verify=false 
~~~

mirror the local release

~~~bash
./oc adm -a pull-secret.txt release mirror \
  --insecure=true \
  --from=${OCP_RELEASE} \
  --to=${OCP_LOCAL_RELEASE_BASE}
  | tee mirror.out
~~~

---
#### Install the local registry with "docker-registry" tool

Install docker registry:

~~~bash
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
~~~

Update the Pull secret with credentials
~~~bash
jq -r ".auths[\"${LOCAL_REGISTRY_IP}:5000\"]={\"auth\":\"$USER_ENC\"}" pull-secret.txt > pull-secret-new.txt
~~~

Test logging to the registry:
~~~bash
podman login --authfile pull-secret-new.txt -u ${USER_NAME_REGISTRY} -p ${USER_PASS_REGISTRY} --tls-verify=false ${LOCAL_REGISTRY_IP}:5000
~~~

Mirror to docker-registry:
~~~
./oc adm -a pull-secret-new.txt release mirror \
  --insecure=true \
  --from=${OCP_RELEASE} \
  --to="${LOCAL_REGISTRY_IP}:5000/ocp"
~~~

To use the new mirrored repository to install, add the following section to the install-config.yaml:
~~~yaml
imageContentSources:
- mirrors:
  - 10.0.13.85:5000/ocp
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - 10.0.13.85:5000/ocp
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev

~~~

> ToDo setup a proxy

___
## Run the installation

See [the "Run the installation"](./ocp-installing-alibabacloud.md#run-the-installation)
