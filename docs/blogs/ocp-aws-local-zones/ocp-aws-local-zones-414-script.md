# Script for blog: Extending Red Hat OpenShift Container Platform to AWS Local Zones (4.14+)

> This document will not be published, and can be skipped in the review process if you want. =]

Hands-on script to deploy the entire environment described in the blog post.

Just copy and paste it! =)

> Note: keep attention in the details, outputs of commands. The steps are not fully safe checking/waiting resources to be created. You must double check it, some resources like EC2 could take longer preventing pods/workloads to be scheduled leading failures in variables discovery, like URL for the router while the service is not created.

## Prerequisites

- AWS CLI installed
- AWS credentials exported with a user with permissions to create AWS cluster
- Optionally, to measure the benchmark: Digital Ocean account and token created
- Red Hat pull secret saved in the path `$PULL_SECRET_FILE`

## Steps

- Extract the openshift clients

```bash
PULL_SECRET_FILE="$HOME/.openshift/pull-secret-latest.json"
oc adm release extract --tools quay.io/openshift-release-dev/ocp-release:4.14.0-ec.4-x86_64 -a $PULL_SECRET_FILE
tar xfz openshift-install-linux-4.14.0-ec.4.tar.gz
tar xfz openshift-client-linux-4.14.0-ec.4.tar.gz
```

- Create the Cluster

```bash
export CLUSTER_NAME=demo-lz
export CLUSTER_BASEDOMAIN="devcluster.openshift.com"
export PULL_SECRET_PATH="$HOME/.openshift/pull-secret-latest.json"
export SSH_KEYS="$(cat ~/.ssh/id_rsa.pub)"
export AWS_REGION=us-east-1

export LOCAL_ZONE_GROUP_NYC="${AWS_REGION}-nyc-1"
export LOCAL_ZONE_NAME_NYC="${LOCAL_ZONE_GROUP_NYC}a"

# enable zone group
aws ec2 modify-availability-zone-group \
    --group-name "${LOCAL_ZONE_GROUP_NYC}" \
    --opt-in-status opted-in

# Local Zone takes some time to be enabled (when not opted-in)
sleep 60

# Create install-config
cat <<EOF > ${PWD}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: "${CLUSTER_BASEDOMAIN}"
metadata:
  name: "${CLUSTER_NAME}"
compute:
- name: edge
  platform:
    aws:
      zones:
      - ${LOCAL_ZONE_NAME_NYC}
platform:
  aws:
    region: ${AWS_REGION}
pullSecret: '$(cat ${PULL_SECRET_PATH} | awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  ${SSH_KEYS}

EOF

./openshift-install create cluster --log-level=debug

export KUBECONFIG=$PWD/auth/kubeconfig
./oc get nodes -l node-role.kubernetes.io/edge
./oc get machineset -n openshift-machine-api
./oc get machine -n openshift-machine-api
```

- Extend the cluster


```bash
export LOCAL_ZONE_CIDR_BUE="10.0.208.0/24"
export LOCAL_ZONE_GROUP_BUE="${AWS_REGION}-bue-1"
export LOCAL_ZONE_NAME_BUE="${LOCAL_ZONE_GROUP_BUE}a"
export SUBNET_NAME_BUE="${INFRA_ID}-public-${LOCAL_ZONE_NAME_BUE}"

export PARENT_ZONE_NAME_BUE="$(aws ec2 describe-availability-zones \
    --filters Name=zone-name,Values=${LOCAL_ZONE_NAME_BUE} \
    --all-availability-zones \
    --query AvailabilityZones[].ParentZoneName --output text)"

aws ec2 describe-subnets \
    --filters Name=vpc-id,Values=$VPC_ID \
    --query 'sort_by(Subnets, &Tags[?Key==`Name`].Value|[0])[].{SubnetName: Tags[?Key==`Name`].Value|[0], CIDR: CidrBlock}'

export INFRA_ID="$(./oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')"

export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${INFRA_ID}-vpc" --query Vpcs[].VpcId --output text)

export VPC_RTB_PUB=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=${INFRA_ID}-public" --query RouteTables[].RouteTableId --output text)

# enable zone group
aws ec2 modify-availability-zone-group \
    --group-name "${LOCAL_ZONE_GROUP_BUE}" \
    --opt-in-status opted-in

# Local Zone takes some time to be enabled (when not opted-in)
sleep 60

export STACK_LZ=${INFRA_ID}-${LOCAL_ZONE_NAME_BUE}
aws cloudformation create-stack --stack-name ${STACK_LZ} \
  --template-body file://template-lz.yaml \
  --parameters \
      ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
      ParameterKey=PublicRouteTableId,ParameterValue="${VPC_RTB_PUB}" \
      ParameterKey=ZoneName,ParameterValue="${LOCAL_ZONE_NAME_BUE}" \
      ParameterKey=SubnetName,ParameterValue="${SUBNET_NAME_BUE}" \
      ParameterKey=PublicSubnetCidr,ParameterValue="${LOCAL_ZONE_CIDR_BUE}" &&\
  aws cloudformation wait stack-create-complete --stack-name ${STACK_LZ}

aws cloudformation describe-stacks --stack-name ${STACK_LZ}

export SUBNET_ID_BUE=$(aws cloudformation describe-stacks --stack-name "${STACK_LZ}" \
  | jq -r .Stacks[0].Outputs[0].OutputValue)

SG_NAME_INGRESS=${INFRA_ID}-localzone-ingress
SG_ID_INGRESS=$(aws ec2 create-security-group \
    --group-name ${SG_NAME_INGRESS} \
    --description "${SG_NAME_INGRESS}" \
    --vpc-id ${VPC_ID} | jq -r .GroupId)

aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID_INGRESS \
    --protocol tcp \
    --port 80 \
    --cidr "0.0.0.0/0"

yq_version=v4.34.2
yq_bin_arch=yq_linux_amd64
wget https://github.com/mikefarah/yq/releases/download/${yq_version}/${yq_bin_arch} \
  -O ./yq && chmod +x ./yq

aws ec2 describe-instance-type-offerings --region ${AWS_REGION} \
    --location-type availability-zone \
    --filters Name=location,Values=${LOCAL_ZONE_NAME_BUE} \
    --query 'InstanceTypeOfferings[*].InstanceType' --output text

export INSTANCE_TYPE_BUE=m5.2xlarge

export BASE_MACHINESET_NYC=$(oc get machineset -n openshift-machine-api -o jsonpath='{range .items[*].metadata}{.name}{"\n"}{end}' | grep nyc-1)

oc get machineset -n openshift-machine-api ${BASE_MACHINESET_NYC} -o yaml \
  | sed -s "s/nyc-1/bue-1/g" > machineset-lz-bue-1a.yaml

KEYS=(.metadata.annotations)
KEYS+=(.metadata.uid)
KEYS+=(.metadata.creationTimestamp)
KEYS+=(.metadata.resourceVersion)
KEYS+=(.metadata.generation)
KEYS+=(.spec.template.spec.providerSpec.value.subnet)
KEYS+=(.spec.template.spec.providerSpec.value.securityGroups)
KEYS+=(.status)
for KEY in ${KEYS[*]}; do
    ./yq -i "del($KEY)" machineset-lz-bue-1a.yaml
done

cat <<EOF > machineset-lz-bue-1a.patch.yaml
spec:
  replicas: 1
  template:
    spec:
      metadata:
        labels:
          machine.openshift.io/parent-zone-name: ${PARENT_ZONE_NAME_BUE}
      providerSpec:
        value:
          instanceType: ${INSTANCE_TYPE_BUE}
          publicIP: yes
          subnet:
            filters:
              - name: tag:Name
                values:
                  - ${SUBNET_NAME_BUE}
          securityGroups:
            - filters:
              - name: "tag:Name"
                values:
                  - ${INFRA_ID}-worker-sg
                  - ${SG_NAME_INGRESS}
EOF

./yq -i '. *= load("machineset-lz-bue-1a.patch.yaml")' machineset-lz-bue-1a.yaml

./oc create -f machineset-lz-bue-1a.yaml

./oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=edge 
```

- Create Deployment

```bash
export APPS_NAMESPACE="localzone-apps"
./oc create namespace ${APPS_NAMESPACE}

function create_deployment() {
    local zone_group=$1; shift
    local app_name=$1; shift
    local set_toleration=${1:-''}
    local tolerations=''
    
    if [[ $set_toleration == "yes" ]]; then
        tolerations='
      tolerations:
      - key: "node-role.kubernetes.io/edge"
        operator: "Equal"
        value: ""
        effect: "NoSchedule"'
    fi
    
    cat << EOF | oc create -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${app_name}
  namespace: ${APPS_NAMESPACE}
spec:
  selector:
    matchLabels:
      app: ${app_name}
  replicas: 1
  template:
    metadata:
      labels:
        app: ${app_name}
        zoneGroup: ${zone_group}
    spec:
      nodeSelector:
        machine.openshift.io/zone-group: ${zone_group}
${tolerations}
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
EOF
}

# App running in a node in New York
create_deployment "${AWS_REGION}-nyc-1" "app-nyc-1" "yes"

# App running in a node in Buenos Aires
create_deployment "${AWS_REGION}-bue-1" "app-bue-1" "yes"

NODE_NAME=$(./oc get nodes -l node-role.kubernetes.io/worker='',topology.kubernetes.io/zone=${AWS_REGION}a \
  -o jsonpath='{.items[0].metadata.name}')

./oc label node ${NODE_NAME} machine.openshift.io/zone-group=${AWS_REGION}

# Deploy a running in a node in the regular zones
create_deployment "${AWS_REGION}" "app-default"

./oc get pods -o wide -n $APPS_NAMESPACE

./oc get pods --show-labels -n $APPS_NAMESPACE
```

- Create ingress

```bash
cat << EOF | oc create -f -
apiVersion: v1
kind: Service 
metadata:
  name: app-default
  namespace: ${APPS_NAMESPACE}
spec:
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: NodePort
  selector:
    app: app-default
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: app-default
  namespace: ${APPS_NAMESPACE}
spec:
  port:
    targetPort: 8080 
  to:
    kind: Service
    name: app-default
EOF

APP_HOST_AZ="$(oc get -n ${APPS_NAMESPACE} route.route.openshift.io/app-default -o jsonpath='{.status.ingress[0].host}')"
```

### Install ALBO


```bash
# Create the Credentials for the Operator:
ALBO_NS=aws-load-balancer-operator
oc create namespace $ALBO_NS

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

# Install the Operator from OLM:
cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: $ALBO_NS
  namespace: $ALBO_NS
spec:
  targetNamespaces:
  - $ALBO_NS
EOF

# Create the subscription:
cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: $ALBO_NS
  namespace: $ALBO_NS
spec:
  channel: stable-v0
  installPlanApproval: Automatic 
  name: $ALBO_NS
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc get installplan -n $ALBO_NS
oc get all -n $ALBO_NS
```

- Wait the resources to be created, then create the controller:

```bash
# Create cluster ALBO controller
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

# Wait for the pod becamig running
oc get pods -w -n $ALBO_NS -l app.kubernetes.io/name=aws-load-balancer-operator
```


### Ingress for NYC (New York) Local Zone app

- Deploy App in NYC using ALB as ingress

```bash
SUBNET_NAME_NYC="${INFRA_ID}-public-${LOCAL_ZONE_NAME_NYC}"

SUBNET_ID_NYC=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=$VPC_ID \
  --query "Subnets[].{Name: Tags[?Key==\`Name\`].Value|[0], ID: SubnetId} | [?Name==\`${SUBNET_NAME_NYC}\`].ID" \
  --output text)

cat << EOF | oc create -f -
apiVersion: v1
kind: Service 
metadata:
  name: app-nyc-1
  namespace: ${APPS_NAMESPACE}
spec:
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: NodePort
  selector:
    app: app-nyc-1
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-lz-nyc-1
  namespace: ${APPS_NAMESPACE}
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: instance
    alb.ingress.kubernetes.io/subnets: ${SUBNET_ID_NYC}
  labels:
    zoneGroup: us-east-1-nyc-1
spec:
  ingressClassName: cloud
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-nyc-1
                port:
                  number: 80
EOF

sleep 30

APP_HOST_NYC=$(./oc get ingress -n ${APPS_NAMESPACE} ingress-lz-nyc-1 \
  --template='{{(index .status.loadBalancer.ingress 0).hostname}}')

while ! curl $APP_HOST_NYC; do sleep 5; done
```

### Ingress for BUE (Buenos Aires) Local Zone app


```bash
# Create a sharded ingressController
cat << EOF | ./oc create -f -
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: ingress-lz-bue-1
  namespace: openshift-ingress-operator
  labels:
    zoneGroup: ${LOCAL_ZONE_GROUP_BUE}
spec:
  endpointPublishingStrategy:
    type: HostNetwork
  replicas: 1
  domain: apps-bue1.${CLUSTER_NAME}.${CLUSTER_BASEDOMAIN}
  nodePlacement:
    nodeSelector:
      matchLabels:
        machine.openshift.io/zone-group: ${LOCAL_ZONE_GROUP_BUE}
    tolerations:
      - key: "node-role.kubernetes.io/edge"
        operator: "Equal"
        value: ""
        effect: "NoSchedule"
  routeSelector:
    matchLabels:
      type: sharded
EOF

# Create the service and the route:
cat << EOF | ./oc create -f -
apiVersion: v1
kind: Service 
metadata:
  name: app-bue-1
  namespace: ${APPS_NAMESPACE}
  labels:
    zoneGroup: ${LOCAL_ZONE_GROUP_BUE}
    app: app-bue-1
spec:
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: NodePort
  selector:
    app: app-bue-1
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: app-bue-1
  namespace: ${APPS_NAMESPACE}
  labels:
    type: sharded
spec:
  host: app-bue-1.apps-bue1.${CLUSTER_NAME}.${CLUSTER_BASEDOMAIN}
  port:
    targetPort: 8080 
  to:
    kind: Service
    name: app-bue-1
EOF

APP_HOST_BUE="$(oc get route.route.openshift.io/app-bue-1 \
  -n ${APPS_NAMESPACE} -o jsonpath='{.status.ingress[0].host}')"

IP_HOST_BUE="$(oc get nodes -l topology.kubernetes.io/zone=us-east-1-bue-1a -o json | jq -r '.items[].status.addresses[] | select (.type=="ExternalIP").address')"

while ! curl -H "Host: $APP_HOST_BUE" http://$IP_HOST_BUE; do sleep 5; done

```

## Benchmark the applications

- Generate the test script:

```bash
# Create the script
cat <<EOF > curl.sh
#!/usr/bin/env bash
echo "# Client Location:"
curl -s http://ip-api.com/json/\$(curl -s ifconfig.me) |jq -cr '[.city, .countryCode]'

run_curl() {
  echo -e "time_namelookup\t time_connect \t time_starttransfer \t time_total"
  for idx in \$(seq 1 5); do
    curl -sw "%{time_namelookup} \t %{time_connect} \t %{time_starttransfer} \t\t %{time_total}\n" \
    -o /dev/null -H "Host: \$1" \${2:-\$1}
  done
}

echo -e "\n# Collecting request times to server running in AZs/Regular zones \n# [endpoint ${APP_HOST_AZ}]"
run_curl ${APP_HOST_AZ}

echo -e "\n# Collecting request times to server running in Local Zone NYC \n# [endpoint ${APP_HOST_NYC}]"
run_curl ${APP_HOST_NYC}

echo -e "\n# Collecting request times to server running in Local Zone BUE \n# [endpoint ${APP_HOST_BUE}]"
run_curl ${APP_HOST_BUE} ${IP_HOST_BUE}
EOF

```

- Provision the external clients in NYC and UK using DigitalOcean Droplets, and test the endpoints:

```bash

# setup the external clients
export DIGITALOCEAN_ACCESS_TOKEN=$MRBRAGA_DO_API_TOKEN
doctl compute ssh-key create my-key --public-key "$(cat ~/.ssh/id_rsa.pub)"
key_id=$(doctl compute ssh-key list | grep my-key | cut -f1 -d ' ')

function create_droplet() {
  region=$1; shift
  name=$1;
  doctl compute droplet create \
  --image fedora-38-x64 \
  --size s-1vcpu-1gb \
  --region $region \
  --ssh-keys ${key_id} \
  --tag-name $name $name

  echo "Waiting for droplet is active..."
  while test "$(doctl compute droplet list --tag-name $name --no-header --format=Status)" != "active"; do sleep 5; done
  doctl compute droplet list --tag-name $name

  client_ip=$(doctl compute droplet list --tag-name $name -o json | jq -r '.[].networks.v4[] | select (.type=="public").ip_address')
  export DROPLET_IP=$client_ip

  echo "Waiting for SSH is UP in $client_ip..."
  while ! ssh -o StrictHostKeyChecking=no root@$client_ip "echo ssh up"; do sleep 5; done
  scp -o StrictHostKeyChecking=no curl.sh root@$client_ip:~/
}

## Create NYC client
export CLIENT_NAME_NYC=demo-localzones-test-nyc
create_droplet nyc3 $CLIENT_NAME_NYC
export CLIENT_IP_NYC=$DROPLET_IP

## Create UK client
export CLIENT_NAME_UK=demo-localzones-test-uk
create_droplet lon1 $CLIENT_NAME_UK
export CLIENT_IP_UK=$DROPLET_IP

# Run tests locally and remote
bash curl.sh
ssh -o StrictHostKeyChecking=no root@$CLIENT_IP_NYC "bash curl.sh"
ssh -o StrictHostKeyChecking=no root@$CLIENT_IP_UK "bash curl.sh"
```

- Destroy the clients:

```bash
# Destroy the droplets
doctl compute droplet delete $CLIENT_NAME_NYC -f
doctl compute droplet delete $CLIENT_NAME_UK -f
```