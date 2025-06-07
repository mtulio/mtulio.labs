# WIP | OCP on AWS Wavelength Zones (Hands-on)


# Create release with PRs BYO VPC and MAPI AWS


## build with cluster-bot

- Build

~~~
build 4.15.0-ec.2,openshift/installer#7652,openshift/machine-api-provider-aws#78
~~~

- Create a custom release with cluster-bot

~~~sh
export PULL_SECRET_FILE=${HOME}/.openshift/pull-secret-latest.json
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="registry.build05.ci.openshift.org/ci-ln-y7i6b5b/release:latest"

oc adm release extract -a $PULL_SECRET_FILE --tools $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE
tar xfz openshift-install-*.tar.gz
~~~


## Build manually

- Build MAPI-AWS image

> https://github.com/openshift/machine-api-provider-aws/pull/78

~~~sh
git clone --recursive git@github.com:openshift/machine-api-provider-aws.git machine-api-provider-aws-pull-78
cd machine-api-provider-aws-pull-78

git fetch origin pull/78/head:pull-78
git switch pull-78

#make images
export MAPI_AWS_IMAGE=quay.io/mrbraga/machine-api-aws:pull-78
podman build -t $MAPI_AWS_IMAGE --authfile $PULL_SECRET_FILE .
podman push $MAPI_AWS_IMAGE
~~~

- Create custom release

~~~sh
OCP_RELEASE_BASE=quay.io/openshift-release-dev/ocp-release:4.15.0-ec.2-x86_64
OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=quay.io/mrbraga/openshift-release:4.15.0-ec.2-mapi-aws-pull-78

oc adm release new -n origin \
  --server https://api.ci.openshift.org \
  -a ${PULL_SECRET_FILE} \
  --from-release ${OCP_RELEASE_BASE} \
  --to-image "${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE}" \
    aws-machine-controllers=${MAPI_AWS_IMAGE}

# Export it
~~~

- Build the installer [PR 7652](https://github.com/openshift/installer/pull/7652)

~~~sh
export INSTALLER_BIN=$HOME/go/src/github.com/mtulio/installer/bin/openshift-install
~~~

# Create a cluster BYO VPC with subnet in public

## Create network

~~~sh

export CLUSTER_REGION=us-east-1
export AZ_NAME="us-east-1-wl1-tpa-wlz-1"
export CLUSTER_NAME=wlz-byovpc-02
export INSTALL_DIR=${PWD}/${CLUSTER_NAME}


export BASE_DOMAIN=devcluster.openshift.com
export SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

mkdir $INSTALL_DIR

# Download the latest CloudFormation templates
TEMPLATES_BASE=https://raw.githubusercontent.com/openshift/installer
TEMPLATES_VERSION=master
TEMPLATES_PATH=upi/aws/cloudformation

TEMPLATE_URL=${TEMPLATES_BASE}/${TEMPLATES_VERSION}/${TEMPLATES_PATH}
TEMPLATES=( "01_vpc.yaml" )
TEMPLATES+=( "01_vpc_01_carrier_gateway.yaml" )
TEMPLATES+=( "01_vpc_99_subnet.yaml" )

for TEMPLATE in "${TEMPLATES[@]}"; do
  echo "Updating ${TEMPLATE}"
  curl -sL "${TEMPLATE_URL}/${TEMPLATE}" > "${INSTALL_DIR}/${TEMPLATE}"
done

TEMPLATE_NAME_VPC="$INSTALL_DIR/01_vpc.yaml"
CIDR_VPC="10.0.0.0/16"
STACK_VPC=${CLUSTER_NAME}-vpc

aws cloudformation create-stack \
  --region ${CLUSTER_REGION} \
  --stack-name ${STACK_VPC} \
  --template-body file://$TEMPLATE_NAME_VPC \
  --parameters \
    ParameterKey=VpcCidr,ParameterValue="${CIDR_VPC}" \
    ParameterKey=AvailabilityZoneCount,ParameterValue=2 \
    ParameterKey=SubnetBits,ParameterValue=12

aws --region $CLUSTER_REGION cloudformation wait stack-create-complete --stack-name ${STACK_VPC}
aws --region $CLUSTER_REGION cloudformation describe-stacks --stack-name ${STACK_VPC}

export VPC_ID=$(aws --region $CLUSTER_REGION cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId").OutputValue' )

## Create WLZ Gateway
TEMPLATE_NAME_CARRIER_GW="${INSTALL_DIR}/01_vpc_01_carrier_gateway.yaml"

export STACK_CAGW=${CLUSTER_NAME}-cagw
aws cloudformation create-stack \
  --region ${CLUSTER_REGION} \
  --stack-name ${STACK_CAGW} \
  --template-body file://$TEMPLATE_NAME_CARRIER_GW \
  --parameters \
    ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
    ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}"

aws --region $CLUSTER_REGION cloudformation wait stack-create-complete --stack-name ${STACK_CAGW}
aws --region $CLUSTER_REGION cloudformation describe-stacks --stack-name ${STACK_CAGW}

AZ_SUFFIX=$(echo ${AZ_NAME/${CLUSTER_REGION}-/})

ZONE_GROUP_NAME=$(aws --region $CLUSTER_REGION ec2 describe-availability-zones \
  --filters Name=zone-name,Values=$AZ_NAME \
  | jq -r .AvailabilityZones[].GroupName)

aws --region $CLUSTER_REGION ec2 modify-availability-zone-group \
    --group-name "${ZONE_GROUP_NAME}" \
    --opt-in-status opted-in

export ROUTE_TABLE_PUB=$(aws --region $CLUSTER_REGION cloudformation describe-stacks \
  --stack-name ${STACK_CAGW} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PublicRouteTableId").OutputValue' )

#> Select the first route table from the list
export ROUTE_TABLE_PVT=$(aws --region $CLUSTER_REGION cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[]
    | select(.OutputKey=="PrivateRouteTableIds").OutputValue
    | split(",")[0] | split("=")[1]' \
)

SUBNET_CIDR_PUB="10.0.128.0/24"
SUBNET_CIDR_PVT="10.0.129.0/24"

cat <<EOF
CLUSTER_REGION=$CLUSTER_REGION
VPC_ID=$VPC_ID
AZ_NAME=$AZ_NAME
AZ_SUFFIX=$AZ_SUFFIX
ZONE_GROUP_NAME=$ZONE_GROUP_NAME
ROUTE_TABLE_PUB=$ROUTE_TABLE_PUB
ROUTE_TABLE_PVT=$ROUTE_TABLE_PVT
SUBNET_CIDR_PUB=$SUBNET_CIDR_PUB
SUBNET_CIDR_PVT=$SUBNET_CIDR_PVT
EOF

# Subnet
TEMPLATE_NAME_SUBNET="$INSTALL_DIR/01_vpc_99_subnet.yaml"

export STACK_SUBNET=${CLUSTER_NAME}-subnets-${AZ_SUFFIX}
aws cloudformation create-stack \
  --region ${CLUSTER_REGION} \
  --stack-name ${STACK_SUBNET} \
  --template-body file://$TEMPLATE_NAME_SUBNET \
  --parameters \
    ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
    ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}" \
    ParameterKey=ZoneName,ParameterValue="${AZ_NAME}" \
    ParameterKey=PublicRouteTableId,ParameterValue="${ROUTE_TABLE_PUB}" \
    ParameterKey=PublicSubnetCidr,ParameterValue="${SUBNET_CIDR_PUB}" \
    ParameterKey=PrivateRouteTableId,ParameterValue="${ROUTE_TABLE_PVT}" \
    ParameterKey=PrivateSubnetCidr,ParameterValue="${SUBNET_CIDR_PVT}"

aws --region $CLUSTER_REGION cloudformation wait stack-create-complete --stack-name ${STACK_SUBNET}
aws --region $CLUSTER_REGION cloudformation describe-stacks --stack-name ${STACK_SUBNET}


## Get the subnets
# Public Subnets from VPC Stack
mapfile -t SUBNETS < <(aws --region $CLUSTER_REGION cloudformation describe-stacks --stack-name "${STACK_VPC}" --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetIds'].OutputValue" --output text | tr ',' '\n')

# Private Subnets from VPC Stack
mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws --region $CLUSTER_REGION cloudformation describe-stacks   --stack-name "${STACK_VPC}" --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetIds'].OutputValue" --output text | tr ',' '\n')

echo "Regular zones: ${SUBNETS[@]}"

# Public Edge Subnet
#mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws --region $CLUSTER_REGION cloudformation describe-stacks   --stack-name "${STACK_SUBNET}" --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetId'].OutputValue" --output text | tr ',' '\n')

mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws --region $CLUSTER_REGION cloudformation describe-stacks   --stack-name "${STACK_SUBNET}" --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetId'].OutputValue" --output text | tr ',' '\n')

export SUBNET_ID_PUB_WL=$(aws --region $CLUSTER_REGION cloudformation describe-stacks   --stack-name "${STACK_SUBNET}" --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetId'].OutputValue" --output text)

echo "Zones with edge: ${SUBNETS[@]}"
echo "SUBNET_ID_PUB_WL=${SUBNET_ID_PUB_WL}"

~~~

## Create config

~~~sh
## Cluster config
cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: ${BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${CLUSTER_REGION}
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)
pullSecret: '$(cat ${PULL_SECRET_FILE} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

cp ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config.yaml.bkp

~~~

## Create manifest and check if public IP was assigned to the machine set

~~~sh
$INSTALLER_BIN version

$INSTALLER_BIN create manifests --dir $INSTALL_DIR

for MF in $INSTALL_DIR/openshift/*worker-machineset-*.yaml; do
  name=$(yq4 ea '.metadata.name' $MF)
  echo ">> machineset $name"
  echo "#>> Is public?: $(yq4 ea '.spec.template.spec.providerSpec.value.publicIp // "no"' $MF)"
  echo "zone: $(yq4 ea .spec.template.spec.providerSpec.value.placement.availabilityZone $MF)"
  echo "#>> Subnet:"
  yq4 ea .spec.template.spec.providerSpec.value.subnet $MF
done
~~~

## Create a cluster

~~~sh
$INSTALLER_BIN create cluster --dir $INSTALL_DIR --log-level=debug
~~~

# [optional] Creaete ALBO and deploy sample application


~~~sh
oc create namespace aws-load-balancer-operator
cat << EOF| oc create -f -
apiVersion: cloudcredential.openshift.io/v1
kind: CredentialsRequest
metadata:
  name: aws-load-balancer-operator
  namespace: openshift-cloud-credential-operator
spec:
  providerSpec:
    apiVersion: cloudcredential.openshift.io/v1
    kind: AWSProviderSpec
    statementEntries:
      - action:
          - ec2:DescribeSubnets
        effect: Allow
        resource: "*"
      - action:
          - ec2:CreateTags
          - ec2:DeleteTags
        effect: Allow
        resource: arn:aws:ec2:*:*:subnet/*
      - action:
          - ec2:DescribeVpcs
        effect: Allow
        resource: "*"
  secretRef:
    name: aws-load-balancer-operator
    namespace: aws-load-balancer-operator
  serviceAccountNames:
    - aws-load-balancer-operator-controller-manager
EOF

cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: aws-load-balancer-operator
  namespace: aws-load-balancer-operator
spec:
  targetNamespaces:
  - aws-load-balancer-operator
EOF

cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: aws-load-balancer-operator
  namespace: aws-load-balancer-operator
spec:
  channel: stable-v0
  installPlanApproval: Automatic 
  name: aws-load-balancer-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc get installplan -n aws-load-balancer-operator --for condition=Ready

oc wait installplan --for condition=A --timeout=30s; do

until  oc wait --for=jsonpath="{${CCM_STATUS_KEY}}"=${CCM_REPLICAS_COUNT} deployment.apps/aws-load-balancer-operator-controller-manager -n aws-load-balancer-operator --timeout=10m &> /dev/null
do
  echo_date "Waiting for minimum replicas avaialble..."
  sleep 10
done

oc get all -n aws-load-balancer-operator


## Create controller

cat <<EOF | oc create -f -
apiVersion: networking.olm.openshift.io/v1alpha1
kind: AWSLoadBalancerController 
metadata:
  name: cluster 
spec:
  subnetTagging: Auto 
  ingressClass: cloud 
  config:
    replicas: 2 
  enabledAddons: 
    - AWSWAFv2
EOF

oc get all -n aws-load-balancer-operator -l app.kubernetes.io/name=aws-load-balancer-operator

export app_name=wl-app
export app_namespace=wl-demo
export ingress_name=wl-app

cat << EOF | oc create -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: $app_namespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $app_name
  namespace: $app_namespace
spec:
  selector:
    matchLabels:
      app: $app_name
  replicas: 1
  template:
    metadata:
      labels:
        app: $app_name
        zone_group: $ZONE_GROUP_NAME
    spec:
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      nodeSelector:
        zone_group: $ZONE_GROUP_NAME
      tolerations:
      - key: "node-role.kubernetes.io/edge"
        operator: "Equal"
        value: ""
        effect: "NoSchedule"
      containers:
        - image: openshift/origin-node
          command:
           - "/bin/socat"
          args:
            - TCP4-LISTEN:8080,reuseaddr,fork
            - EXEC:'/bin/bash -c \"printf \\\"HTTP/1.0 200 OK\r\n\r\n\\\"; sed -e \\\"/^\r/q\\\"\"'
          imagePullPolicy: Always
          name: echoserver
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service 
metadata:
  name:  $app_name
  namespace: $app_namespace
spec:
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: NodePort
  selector:
    app: $app_name
EOF


cat << EOF | oc create -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $app_name
  namespace: $app_namespace
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: instance
    alb.ingress.kubernetes.io/subnets: ${SUBNET_ID_PUB_WL}
  labels:
    zone_group: $ZONE_GROUP_NAME
spec:
  ingressClassName: cloud
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: $app_name
                port:
                  number: 80
EOF


HOST=$(oc get ingress -n $app_namespace $app_name --template='{{(index .status.loadBalancer.ingress 0).hostname}}')
 
echo $HOST
 
curl $HOST

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