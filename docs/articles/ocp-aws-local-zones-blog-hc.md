# OCP on AWS Local Zones - HC Blog - hands-on steps


## Network

- Create the Network Stack: VPC and Local Zone subnet

```bash
export CLUSTER_REGION=us-east-1
export CLUSTER_NAME=ocp-lz5

export STACK_VPC=${CLUSTER_NAME}-vpc
aws cloudformation create-stack --stack-name ${STACK_VPC} \
     --template-body file://template-vpc.yaml \
     --parameters \
        ParameterKey=ClusterName,ParameterValue=${CLUSTER_NAME} \
        ParameterKey=VpcCidr,ParameterValue="10.0.0.0/16" \
        ParameterKey=AvailabilityZoneCount,ParameterValue=3 \
        ParameterKey=SubnetBits,ParameterValue=12

aws cloudformation wait stack-create-complete --stack-name ${STACK_VPC}
aws cloudformation describe-stacks --stack-name ${STACK_VPC}

# Choosing randomly the AZ
AZ_NAME=$(aws --region $CLUSTER_REGION ec2 describe-availability-zones \
  --filters Name=opt-in-status,Values=opted-in Name=zone-type,Values=local-zone \
  | jq -r .AvailabilityZones[].ZoneName | shuf |head -n1)

AZ_SUFFIX=$(echo ${AZ_NAME/${CLUSTER_REGION}-/})

AZ_GROUP=$(aws --region $CLUSTER_REGION ec2 describe-availability-zones \
  --filters Name=zone-name,Values=$AZ_NAME \
  | jq -r .AvailabilityZones[].GroupName)

export STACK_LZ=${CLUSTER_NAME}-lz-${AZ_SUFFIX}
export ZONE_GROUP_NAME=${AZ_GROUP}
export VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId").OutputValue' )

export VPC_RTB_PUB=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PublicRouteTableId").OutputValue' )

aws ec2 modify-availability-zone-group \
    --group-name "${ZONE_GROUP_NAME}" \
    --opt-in-status opted-in

aws cloudformation create-stack --stack-name ${STACK_LZ} \
     --template-body file://template-lz.yaml \
     --parameters \
        ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}" \
        ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
        ParameterKey=PublicRouteTableId,ParameterValue="${VPC_RTB_PUB}" \
        ParameterKey=LocalZoneName,ParameterValue="${ZONE_GROUP_NAME}a" \
        ParameterKey=LocalZoneNameShort,ParameterValue="${AZ_SUFFIX}" \
        ParameterKey=PublicSubnetCidr,ParameterValue="10.0.128.0/20"

aws cloudformation wait stack-create-complete --stack-name ${STACK_LZ}
aws cloudformation describe-stacks --stack-name ${STACK_LZ}

mapfile -t SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[0].OutputValue' | tr ',' '\n')

mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[1].OutputValue' | tr ',' '\n')

# get the Local Zone subnetID
export SUBNET_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_LZ}" \
  | jq -r .Stacks[0].Outputs[0].OutputValue)

```

- Local Zones implementation, phase-1, only:

> Phase-1 means the installer should discovery the Local Zone subnet by it's ID, parse it and automatically create the Machine Sets for those zones

```
echo ${SUBNETS[*]}
SUBNETS+=(${SUBNET_ID})
echo ${SUBNETS[*]}
```


## Install-config

- create the install-config

```bash
export BASE_DOMAIN=devcluster.openshift.com
export SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

INSTALL_DIR=${CLUSTER_NAME}-1
mkdir $INSTALL_DIR

cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: ${BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
networking:
  clusterNetwork:
  - cidr: 10.132.0.0/14
    hostPrefix: 23
platform:
  aws:
    region: ${CLUSTER_REGION}
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

```


### Create manifests


```bash
# Installer version/path
export INSTALLER=./openshift-install
export RELEASE="quay.io/openshift-release-dev/ocp-release:4.13.0-ec.3-x86_64"

cp $INSTALL_DIR/install-config.yaml $INSTALL_DIR/install-config.yaml-bkp

# Process the manifests

OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="$RELEASE" \
  $INSTALLER create manifests --dir $INSTALL_DIR

# Review if MTU patch has been created
ls -ls $INSTALL_DIR/manifests/cluster-network-*
cat $INSTALL_DIR/manifests/cluster-network-03-config.yml

# Review if MachineSet for Local Zone has been created
ls -la $INSTALL_DIR/openshift/99_openshift-cluster-api_worker-machineset*
cat $INSTALL_DIR/openshift/99_openshift-cluster-api_worker-machineset-3.yaml

```

- Phase-0 only, manual patch for MTU

```bash
cat <<EOF > $INSTALL_DIR/manifests/cluster-network-03-config.yml
apiVersion: operator.openshift.io/v1
kind: Network
metadata:
  name: cluster
spec:
  defaultNetwork:
    ovnKubernetesConfig:
      mtu: 1200
EOF
cat $INSTALL_DIR/manifests/cluster-network-03-config.yml
```

- Create the cluster

```bash
OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="$RELEASE" \
  $INSTALLER create cluster --dir $INSTALL_DIR --log-level=debug
```

## Setup the AWS LB Operator

### ALB Operator prerequisites

- The ALB Operator requires the Kubernetes Cluster tag on the VPC:

```
$ oc logs pod/aws-load-balancer-operator-controller-manager-56664699b4-kjdd4 -n aws-load-balancer-operator
I0207 20:32:30.393782       1 request.go:682] Waited for 1.0400816s due to client-side throttling, not priority and fairness, request: GET:https://172.30.0.1:443/apis/ingress.operator.openshift.io/v1?timeout=32s
1.6758019517970793e+09	INFO	controller-runtime.metrics	Metrics server is starting to listen	{"addr": "127.0.0.1:8080"}
1.6758019518810503e+09	ERROR	setup	failed to get VPC ID	{"error": "no VPC with tag \"kubernetes.io/cluster/ocp-lz-2nnns\" found"}
main.main
	/remote-source/workspace/app/main.go:133
runtime.main
	/usr/lib/golang/src/runtime/proc.go:250

```

Tag the VPC

```bash
CLUSTER_ID=$(oc get infrastructures cluster -o jsonpath='{.status.infrastructureName}')
aws ec2 create-tags --resources ${VPC_ID} \
  --tags Key="kubernetes.io/cluster/${CLUSTER_ID}",Value="shared" \
  --region ${CLUSTER_REGION}
```

### Install the ALB Operator

> [Installing ALB Operator](https://docs.openshift.com/container-platform/4.12/networking/aws_load_balancer_operator/install-aws-load-balancer-operator.html)

> [Understanding the AWS Load Balancer Operator](https://docs.openshift.com/container-platform/4.12/networking/aws_load_balancer_operator/understanding-aws-load-balancer-operator.html)

> [Installing from OperatorHub using the CLI](https://docs.openshift.com/container-platform/4.10/operators/admin/olm-adding-operators-to-cluster.html#olm-installing-operator-from-operatorhub-using-cli_olm-adding-operators-to-a-cluster)

- Create the Credentials for the Operator

```bash
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
```

- Install the Operator from OLM

```bash
# Create the Operator Group
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
```

- Create the subscription

```bash
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
```

Check if the install plan has been automatic approved:

```bash
$ oc get installplan -n aws-load-balancer-operator
NAME            CSV                                 APPROVAL    APPROVED
install-qlsxz   aws-load-balancer-operator.v0.2.0   Automatic   true
install-x7vwn   aws-load-balancer-operator.v0.2.0   Automatic   true
```

Check if the operator has been created correctly:

```bash
$ oc get all -n aws-load-balancer-operator
NAME                                                                 READY   STATUS    RESTARTS   AGE
pod/aws-load-balancer-operator-controller-manager-56664699b4-j77js   2/2     Running   0          100s

NAME                                                                    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/aws-load-balancer-operator-controller-manager-metrics-service   ClusterIP   172.30.57.143   <none>        8443/TCP   12m

NAME                                                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/aws-load-balancer-operator-controller-manager   1/1     1            1           12m

NAME                                                                       DESIRED   CURRENT   READY   AGE
replicaset.apps/aws-load-balancer-operator-controller-manager-56664699b4   1         1         1       12m

```

### Create the ALB Controller

> [Creating an instance of AWS Load Balancer Controller](https://docs.openshift.com/container-platform/4.12/networking/aws_load_balancer_operator/create-instance-aws-load-balancer-controller.html)

```bash
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
```

Check if the controller was installed

```bash
$ oc get all -n aws-load-balancer-operator -l app.kubernetes.io/name=aws-load-balancer-operator
NAME                                                        READY   STATUS    RESTARTS   AGE
pod/aws-load-balancer-controller-cluster-67b6dd6974-6r6tp   1/1     Running   0          43s
pod/aws-load-balancer-controller-cluster-67b6dd6974-vw5vw   1/1     Running   0          43s

NAME                                                              DESIRED   CURRENT   READY   AGE
replicaset.apps/aws-load-balancer-controller-cluster-67b6dd6974   2         2         2       44s

```


## Setup the Sample APP on AWS Local Zones

- Deploy the application
```bash
cat << EOF | oc create -f -
apiVersion: v1
kind: Namespace
metadata:
  name: lz-apps
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lz-app-nyc-1
  namespace: lz-apps
spec:
  selector:
    matchLabels:
      app: lz-app-nyc-1
  replicas: 1
  template:
    metadata:
      labels:
        app: lz-app-nyc-1
        zone_group: us-east-1-nyc-1
    spec:
      nodeSelector:
        zone_group: us-east-1-nyc-1
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
  name:  lz-app-nyc-1 
  namespace: lz-apps
spec:
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: NodePort
  selector:
    app: lz-app-nyc-1
EOF
```

- create the ingress

```bash
cat << EOF | oc create -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-lz-nyc-1
  namespace: lz-apps
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: instance
    alb.ingress.kubernetes.io/subnets: ${SUBNET_ID}
  labels:
    zone_group: us-east-1-nyc-1
spec:
  ingressClassName: cloud
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: lz-app-nyc-1
                port:
                  number: 80
EOF
```

- Call the endpoint

```bash
$ HOST=$(oc get ingress -n lz-apps ingress-lz-nyc-1 --template='{{(index .status.loadBalancer.ingress 0).hostname}}')
$ $ echo $HOST
k8s-lzapps-ingressl-49a869b572-66443804.us-east-1.elb.amazonaws.com

$ curl $HOST
GET / HTTP/1.1
X-Forwarded-For: 179.181.81.124
X-Forwarded-Proto: http
X-Forwarded-Port: 80
Host: k8s-lzapps-ingressl-13226f2551-de.us-east-1.elb.amazonaws.com
X-Amzn-Trace-Id: Root=1-63e18147-1532a244542b04bc75ffd473
User-Agent: curl/7.61.1
Accept: */*

```

- Call from different locations

```bash
export HOST=k8s-lzapps-ingressl-49a869b572-66443804.us-east-1.elb.amazonaws.com

# [1] NYC (outside AWS backbone)
$ curl -s http://ip-api.com/json/$(curl -s ifconfig.me) |jq -r '[.city, .countryCode]'
[
  "North Bergen",
  "US"
]
$ curl -sw "%{time_namelookup}   %{time_connect}     %{time_starttransfer}    %{time_total}\n" -o /dev/null $HOST
0.001452   0.004079     0.008914    0.009830

# [2] Within the Region (master nodes)
$ oc debug node/$(oc get nodes -l node-role.kubernetes.io/master -o jsonpath={'.items[0].metadata.name'}) -- chroot /host /bin/bash -c "\
hostname; \
curl -s http://ip-api.com/json/\$(curl -s ifconfig.me) |jq -r '[.city, .countryCode]';\
curl -sw \"%{time_namelookup}   %{time_connect}     %{time_starttransfer}    %{time_total}\\n\" -o /dev/null $HOST"
ip-10-0-54-118
[
  "Ashburn",
  "US"
]
0.002068   0.010196     0.019962    0.020985

# [3] London (outside AWS backbone)
$ curl -s http://ip-api.com/json/$(curl -s ifconfig.me) |jq -r '[.city, .countryCode]'
[
  "London",
  "GB"
]
$ curl -sw "%{time_namelookup}   %{time_connect}     %{time_starttransfer}    %{time_total}\n" -o /dev/null $HOST
0.003332   0.099921     0.197535    0.198802

# [4] Brazil
$ curl -s http://ip-api.com/json/$(curl -s ifconfig.me) |jq -r '[.city, .countryCode]'
[
  "Florianópolis",
  "BR"
]
$ curl -sw "%{time_namelookup}   %{time_connect}     %{time_starttransfer}    %{time_total}\n" -o /dev/null $HOST
0.022869   0.187408     0.355456    0.356435
```

| Server / Client | [1]NYC/US | [2]AWS Region/use1 | [3]London/UK | [4]Brazil | 
| --  | -- | -- | -- | -- |
| us-east-1-nyc-1a |   0.004079 | 0.010196 | 0.099921 | 0.187408 |
