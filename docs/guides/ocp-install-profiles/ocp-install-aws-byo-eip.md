# OCP on AWS - Deploy a cluster using existing existing Elastic IPs

> Note: the CAPA have bugs to complete this guide. This guide is using the following version: github.com:mtulio/cluster-api-provider-aws.git @ spike-byo-eip

This guide shows how to create a cluster using custom Elastic IPs (Public IPs) that you pre-allocated to AWS Account.

Use this option when you are looking for more control of the public IPv4 ingressing and egressing for the cluster, helping you, for instance, to refine firewall rules to access your resources.

## Prerequisites

- The Elastic IPs must be allocated and not associated to any resource.
- Each Elastic IP allocation must have the correct tags by role to match the provisioner lookup (CAPA).

## Steps

- Generate the basic install-config.yaml to discover the zones:

```sh
INSTALLER=./openshift-install-devel
export RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:4.17.0-rc.0-x86_64

REGION=us-east-1
CLUSTER_BASE_DOMAIN=devcluster.openshift.com
CLUSTER_NAME=byoeip

INSTALL_DIR=./install-dir-${CLUSTER_NAME}
mkdir -p ${INSTALL_DIR}

cat << EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: ${CLUSTER_BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
platform:
  aws:
    region: ${REGION}
pullSecret: '$(cat ${PULL_SECRET_FILE})'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
EOF

${INSTALLER} create manifests --dir=${INSTALL_DIR}
```

- Discover the total of zones the cluster will be deployed, if none is defined in the original install-config.yaml:

~~~sh
ZONE_COUNT=$(yq ea '.spec.network.subnets[] | [select(.isPublic==true).availabilityZone] | length' ${INSTALL_DIR}/cluster-api/02_infra-cluster.yaml)
~~~

- Discover the InfraID:

```sh
CLUSTER_ID=$(yq ea .status.infrastructureName ${INSTALL_DIR}/manifests/cluster-infrastructure-02-config.yml)

# Create cluster tags (must have the 'shared' value to be unmanaged)
CLUSTER_TAGS="{Key=kubernetes.io/cluster/${CLUSTER_ID},Value=shared}"
CLUSTER_TAGS+=",{Key=sigs.k8s.io/cluster-api-provider-aws/cluster/${CLUSTER_ID},Value=shared}"
```

- Allocate addresses for `NatGateways` (role==common) setting the cluster api tags:

```sh
# 'common' role is an standard for Cluster API AWS for EIPs when
# creating Nat Gateways for private subnets.
TAG_ROLE=common

TAGS="{Key=Name,Value=${CLUSTER_ID}-eip-${TAG_ROLE}}"
TAGS+=",${CLUSTER_TAGS}"

# Cluster API will look up for the role and assign to the resource
TAGS+=",{Key=sigs.k8s.io/cluster-api-provider-aws/role,Value=${TAG_ROLE}}"

# Allocate the addresses
for EIP_ID in $(seq 1 ${ZONE_COUNT}); do
  aws --region ${REGION} ec2 allocate-address \
    --domain "vpc" \
    --tag-specifications "ResourceType=elastic-ip,Tags=[${TAGS}]" \
    | tee -a ${INSTALL_DIR}/eips-${TAG_ROLE}.txt
done
```

- Allocate addresses for `NatGateways` (role==common) setting the cluster api tags:

```sh
# 'lb-apiserver' role is an standard match for Cluster API AWS for EIPs when
# creating Public Load Balancer for API.
TAG_ROLE=lb-apiserver

TAGS="{Key=Name,Value=${CLUSTER_ID}-eip-${TAG_ROLE}}"
TAGS+=",${CLUSTER_TAGS}"

# Cluster API will look up for the role and assign to the resource
TAGS+=",{Key=sigs.k8s.io/cluster-api-provider-aws/role,Value=${TAG_ROLE}}"

# Allocate the addresses
for EIP_ID in $(seq 1 ${ZONE_COUNT}); do
  aws --region ${REGION} ec2 allocate-address \
    --domain "vpc" \
    --tag-specifications "ResourceType=elastic-ip,Tags=[${TAGS}]" \
    | tee -a ${INSTALL_DIR}/eips-${TAG_ROLE}.txt
done
```

- Allocate addresses for `Machines` (role==ec2-custom) setting the cluster api tags:

```sh
# 'ec2-custom' role is an standard match for Cluster API AWS for EIPs when
# creating machines in Public subnets.
TAG_ROLE=ec2-custom

TAGS="{Key=Name,Value=${CLUSTER_ID}-eip-${TAG_ROLE}}"
TAGS+=",${CLUSTER_TAGS}"

# Cluster API will look up for the role and assign to the resource
TAGS+=",{Key=sigs.k8s.io/cluster-api-provider-aws/role,Value=${TAG_ROLE}}"

# Allocate the addresses
aws --region ${REGION} ec2 allocate-address \
  --domain "vpc" \
  --tag-specifications "ResourceType=elastic-ip,Tags=[${TAGS}]" \
  | tee -a ${INSTALL_DIR}/eips-${TAG_ROLE}.txt
```

- Create the cluster

```sh
${INSTALLER} create cluster --dir=${INSTALL_DIR} --log-level=debug
```

<!-- ### Reviewing the EIPs

Checking if the cluster has been created re-using the pre-allocated EIPs:

- Check the Public IPs for Nat Gateway:

```sh
$ jq -r .PublicIp ${INSTALL_DIR}/eips-common.txt | sort -n
34.194.161.249
44.218.180.88
44.222.26.11
52.44.237.214
54.144.209.129
54.236.196.217

$ aws ec2 describe-nat-gateways --filter Name=tag-key,Values=kubernetes.io/cluster/${CLUSTER_ID} | jq -r .NatGateways[].NatGatewayAddresses[].PublicIp | sort -n
34.194.161.249
44.218.180.88
44.222.26.11
52.44.237.214
54.144.209.129
54.236.196.217
```

- Check the Addresses for API's NLB:

> BAH! Bug! CAPA is not assigning BYO EIPs

```sh
$ jq -r .PublicIp ${INSTALL_DIR}/eips-lb-apiserver.txt | sort -n
3.233.6.197
3.91.167.197
34.198.58.67
44.218.195.77
54.156.68.110
54.210.212.77

$ dig +short api.ocp-byoeip.${CLUSTER_BASE_DOMAIN} | sort -n
23.23.33.250
34.206.145.141
35.172.27.105
44.216.208.39
54.225.119.195
100.29.105.247
``` -->

<!-- ### Caveats

TBD:
- Do we need to store the EIP allocations, or set custom tags, to the BYO EIPs? (example setting `openshift_creationDate` tag). If so, the install-config.yaml entry must be added
- What about the EIP for bootstrap? Is it required to support in CORS-2603?
 -->
