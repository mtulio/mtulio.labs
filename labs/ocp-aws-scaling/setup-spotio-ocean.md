# Kubernetes Scaling Lab | Setup Ocean by Spot.io

- instances (choose one):

```sh
INSTANCES_ALL=$(jq -rc deploy-spotio/templates/instances.json)

# Only instances with 4+ vCPU
INSTANCES_WL_XPLUS=$(jq -rc '[.[] | select(. | contains(".large") | not)]' deploy-spotio/templates/instances.json)

# Instances White List
export COMPUTE_INSTANCE_TYPES_WHITELIST=$INSTANCES_WL_XPLUS
```

- Discover environment/cluster info and export it:

```sh
# Define and export the vars: SPOT_TOKEN and SPOT_ACCOUNT_ID
source .env

export INFRA_ID=$(oc get infrastructure cluster \
  -o jsonpath='{.status.infrastructureName}')
export CLUSTER_NAME=$INFRA_ID

# Discovery and export
export CLUSTER_REGION=$(oc get infrastructure cluster \
  -o jsonpath='{.status.platformStatus.aws.region}')

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

export IMAGE_ID=$(oc get machineset -n openshift-machine-api \
  -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}')

export USER_DATA=$(oc get secret \
  -n openshift-machine-api \
  $(oc get machineset -n openshift-machine-api \
    -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.userDataSecret.name'}) \
  -o jsonpath='{.data.userData}')

export SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filter Name=tag:Name,Values=$(oc get machineset -n openshift-machine-api \
    -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.securityGroups[0].filters[0].values[0]}') \
  --query 'SecurityGroups[].GroupId' --output text)

export INSTANCE_PROFILE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:instance-profile/${INFRA_ID}-worker-profile"

export KEY_PAR_NAME="openshift-dev"
export TAG_KEY_KUBE="kubernetes.io/cluster/$INFRA_ID"
export TAG_NAME="$INFRA_ID-worker-spotio"

function get_subnet_ids() {
  aws ec2 describe-subnets \
    --filter Name=tag-key,Values="kubernetes.io/cluster/${INFRA_ID}" \
    --query 'Subnets[]' \
    | jq  '.[] | [{id: .SubnetId, tags: .Tags[]|select(.Value | contains("private")).Value }][0].id | select( . != null )' \
    | jq -cs .
}
export SUBNETS=$(get_subnet_ids)

# Review vars have values
cat <<EOF
SPOT_TOKEN=$SPOT_TOKEN
SPOT_ACCOUNT_ID=$SPOT_ACCOUNT_ID
INFRA_ID=$INFRA_ID
CLUSTER_NAME=$CLUSTER_NAME
COMPUTE_INSTANCE_TYPES_WHITELIST=$COMPUTE_INSTANCE_TYPES_WHITELIST
INFRA_ID=$INFRA_ID
CLUSTER_REGION=$CLUSTER_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
IMAGE_ID=$IMAGE_ID
USER_DATA=$USER_DATA
SECURITY_GROUP_ID=$SECURITY_GROUP_ID
INSTANCE_PROFILE_ARN=$INSTANCE_PROFILE_ARN
KEY_PAR_NAME=$KEY_PAR_NAME
TAG_KEY_KUBE=$TAG_KEY_KUBE
TAG_NAME=$TAG_NAME
SUBNETS=$SUBNETS
EOF
```

- Create the cluster configuration

```sh
envsubst < deploy-spotio/templates/cluster.template > deploy-spotio/data/cluster.json
```

> Review if `deploy-spotio/data/cluster.json` has been rendered correctly: jq . deploy-spotio/data/cluster.json 

- Crate the cluster in SaaS

```sh
curl -H "Authorization: bearer ${SPOT_TOKEN}"\
    -d @deploy-spotio/data/cluster.json \
    -H "Content-Type: application/json" \
    "https://api.spotinst.io/ocean/aws/k8s/cluster?accountId=${SPOT_ACCOUNT_ID}"
```

- Deploy the Ocean controller

```sh
cat << EOF > deploy-spotio/config.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: spotio
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: spotinst-kubernetes-cluster-controller-config
  namespace: spotio
data:
  spotinst.cluster-identifier: "${CLUSTER_NAME}"
  disable-auto-update: "true"
  enable-csr-approval: "true"
---
apiVersion: v1
kind: Secret
metadata:
  name: spotinst-kubernetes-cluster-controller
  namespace: spotio
type: Opaque
data:
  token: "$(echo -ne ${SPOT_TOKEN} | base64 --wrap=0)"
  account: "$(echo -ne ${SPOT_ACCOUNT_ID} | base64 --wrap=0)"
EOF

oc apply -k deploy-spotio/
```

## Delete

- Delete controller

```sh
oc delete ns spotio
```

- Get Ocean Spot

```sh
SPOT_OCEAN_CLUSTER_ID=$(curl -s -H "Authorization: bearer ${SPOT_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://api.spotinst.io/ocean/aws/k8s/cluster?accountId=${SPOT_ACCOUNT_ID}" \
  | jq -r ".response.items[] | select(.name==\"$CLUSTER_NAME\").id")
```

- Delete the cluster in Spot.io

> https://docs.spot.io/api/

```sh
curl -X DELETE -H "Authorization: bearer ${SPOT_TOKEN}"\
    "https://api.spotinst.io/ocean/aws/k8s/cluster/${SPOT_OCEAN_CLUSTER_ID}?accountId=${SPOT_ACCOUNT_ID}&oceanClusterId=${SPOT_OCEAN_CLUSTER_ID}"
```