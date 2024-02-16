# Installing OpenShift on AWS extending to AWS Outposts in Day-2

Lab steps to install an OpenShift cluster on AWS, extending compute nodes to AWS Outposts as a day-2 operations.

## Install OpenShift

- Export the AWS credentials

```sh
export AWS_PROFILE=outposts
```

- Install OpenShift cluster

```sh
VERSION="4.15.0-rc.7"
PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64
CLUSTER_NAME=otp-01
INSTALL_DIR=${HOME}/openshift-labs/$CLUSTER_NAME
CLUSTER_BASE_DOMAIN=outpost-dev.devcluster.openshift.com
SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub
REGION=us-east-1
AWS_REGION=$REGION

mkdir -p $INSTALL_DIR && cd $INSTALL_DIR

oc adm release extract \
    --tools quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64 \
    -a ${PULL_SECRET_FILE}

tar xvfz openshift-client-linux-${VERSION}.tar.gz
tar xvfz openshift-install-linux-${VERSION}.tar.gz

echo "> Creating install-config.yaml"
# Create a single-AZ install config
mkdir -p ${INSTALL_DIR}
cat <<EOF | envsubst > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${CLUSTER_BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${REGION}
    propagateUserTags: true
    userTags:
      cluster_name: $CLUSTER_NAME
      Environment: cluster
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

echo ">> install-config.yaml created: "
cp -v ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config.yaml-bkp

./openshift-install create cluster --dir $INSTALL_DIR --log-level=debug

export KUBECONFIG=$PWD/auth/kubeconfig
```

## Create an AWS Outposts subnets

This steps modify existing CloudFormation template available in the installer repository to create VPC subnets, specially in Wavelength or Local Zones.

The template is modifyed to receive the parameter to support AWS Outpost instance ARN.

### Prerequisites

Create Cloudformation template:

> TODO: download from Installer when the field `OutpostArn` is available from [UPI Templates for subnet](https://raw.githubusercontent.com/openshift/installer/master/upi/aws/cloudformation/01_vpc_99_subnet.yaml)


```sh
TEMPLATE_NAME=./cfn-subnet.yaml
cat <<EOF > ${TEMPLATE_NAME}
AWSTemplateFormatVersion: 2010-09-09
Description: Template for Best Practice Subnets (Public and Private)

Parameters:
  VpcId:
    Description: VPC ID which the subnets will be part.
    Type: String
    AllowedPattern: ^(?:(?:vpc)(?:-[a-zA-Z0-9]+)?\b|(?:[0-9]{1,3}\.){3}[0-9]{1,3})$
    ConstraintDescription: VPC ID must be with valid name, starting with vpc-.*.
  ClusterName:
    Description: Cluster Name or Prefix name to prepend the tag Name for each subnet.
    Type: String
    AllowedPattern: ".+"
    ConstraintDescription: ClusterName parameter must be specified.
  ZoneName:
    Description: Zone Name to create the subnets (Example us-west-2-lax-1a).
    Type: String
    AllowedPattern: ".+"
    ConstraintDescription: ZoneName parameter must be specified.
  PublicRouteTableId:
    Description: Public Route Table ID to associate the public subnet.
    Type: String
    AllowedPattern: ".+"
    ConstraintDescription: PublicRouteTableId parameter must be specified.
  PublicSubnetCidr:
    # yamllint disable-line rule:line-length
    AllowedPattern: ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(1[6-9]|2[0-4]))$
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/16-24.
    Default: 10.0.128.0/20
    Description: CIDR block for Public Subnet
    Type: String
  PrivateRouteTableId:
    Description: Public Route Table ID to associate the Local Zone subnet
    Type: String
    AllowedPattern: ".+"
    ConstraintDescription: PublicRouteTableId parameter must be specified.
  PrivateSubnetCidr:
    # yamllint disable-line rule:line-length
    AllowedPattern: ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(1[6-9]|2[0-4]))$
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/16-24.
    Default: 10.0.128.0/20
    Description: CIDR block for Public Subnet
    Type: String
  PrivateSubnetLabel:
    Default: "private"
    Description: Subnet label to be added when building the subnet name.
    Type: String
  PublicSubnetLabel:
    Default: "public"
    Description: Subnet label to be added when building the subnet name.
    Type: String
  OutpostArn:
    Default: ""
    Description: OutpostArn when creating subnets on AWS Outpost
    Type: String

Conditions:
  OutpostEnabled: !Not [!Equals [!Ref "OutpostArn", ""]]

Resources:
  PublicSubnet:
    Type: "AWS::EC2::Subnet"
    Properties:
      VpcId: !Ref VpcId
      CidrBlock: !Ref PublicSubnetCidr
      AvailabilityZone: !Ref ZoneName
      OutpostArn: !If [ OutpostEnabled, !Ref OutpostArn, !Ref "AWS::NoValue"]
      Tags:
      - Key: Name
        Value: !Join ['-', [ !Ref ClusterName, !Ref PublicSubnetLabel, !Ref ZoneName]]
      # workaround to prevent CCM of using this subnet
      - Key: kubernetes.io/cluster/unmanaged
        Value: true

  PublicSubnetRouteTableAssociation:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Properties:
      SubnetId: !Ref PublicSubnet
      RouteTableId: !Ref PublicRouteTableId

  PrivateSubnet:
    Type: "AWS::EC2::Subnet"
    Properties:
      VpcId: !Ref VpcId
      CidrBlock: !Ref PrivateSubnetCidr
      AvailabilityZone: !Ref ZoneName
      OutpostArn: !If [ OutpostEnabled, !Ref OutpostArn, !Ref "AWS::NoValue"]
      Tags:
      - Key: Name
        Value: !Join ['-', [!Ref ClusterName, !Ref PrivateSubnetLabel, !Ref ZoneName]]
      # workaround to prevent CCM of using this subnet
      - Key: kubernetes.io/cluster/unmanaged
        Value: true

  PrivateSubnetRouteTableAssociation:
    Type: "AWS::EC2::SubnetRouteTableAssociation"
    Properties:
      SubnetId: !Ref PrivateSubnet
      RouteTableId: !Ref PrivateRouteTableId

Outputs:
  PublicSubnetId:
    Description: Subnet ID of the public subnets.
    Value:
      !Join ["", [!Ref PublicSubnet]]

  PrivateSubnetId:
    Description: Subnet ID of the private subnets.
    Value:
      !Join ["", [!Ref PrivateSubnet]]
EOF
```

### Steps

- Export the variables discovered from Outposts' Rack/instance

```sh
export OutpostId=$(aws outposts list-outposts --query  "Outposts[].OutpostId" --output text)
export OutpostArn=$(aws outposts list-outposts --query  "Outposts[].OutpostArn" --output text)
export OutpostAvailabilityZone=$(aws outposts list-outposts --query  "Outposts[].AvailabilityZone" --output text)
```

- Export required variables to create subnets:

```sh
CLUSTER_ID=$(oc get infrastructures cluster -o jsonpath='{.status.infrastructureName}')
MACHINESET_NAME=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.name}')
MACHINESET_SUBNET_NAME=$(oc get machineset -n openshift-machine-api $MACHINESET_NAME -o json | jq -r '.spec.template.spec.providerSpec.value.subnet.filters[0].values[0]')

VpcId=$(aws ec2 describe-subnets --region $AWS_REGION --filters Name=tag:Name,Values=$MACHINESET_SUBNET_NAME --query 'Subnets[].VpcId' --output text)

ClusterName=$CLUSTER_ID

PublicRouteTableId=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VpcId \
    | jq -r '.RouteTables[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .RouteTableId }]' \
    | jq -r '.[]  | select(.Name | contains("public")).Id')
PrivateRouteTableId=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VpcId \
    | jq -r '.RouteTables[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .RouteTableId }]' \
    | jq -r ".[]  | select(.Name | contains(\"${OutpostAvailabilityZone}\")).Id")

# 1. When the last subnet CIDR is 10.0.192.0/20, it will return 208 (207+1, where 207 is the last 3rd octect of the network)
# 2. Create /24 subnets
NextFree3rdOctectIP=$(echo "$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VpcId \
    | jq  -r ".Subnets[].CidrBlock" |sort -t . -k 3,3n -k 4,4n | tail -n1 \
    | xargs ipcalc  | grep ^HostMax | awk '{print$2}' | awk -F'.' '{print$3}'\
    ) + 1" | bc)
PublicSubnetCidr="10.0.${NextFree3rdOctectIP}.0/24"

NextFree3rdOctectIP=$(( NextFree3rdOctectIP + 1 ))
PrivateSubnetCidr="10.0.${NextFree3rdOctectIP}.0/24"
```

- Create the subnet:

```sh
STACK_NAME=${CLUSTER_ID}-subnets-outpost-v1
aws cloudformation create-stack --stack-name $STACK_NAME \
    --region ${AWS_REGION} \
    --template-body file://${TEMPLATE_NAME} \
    --parameters \
        ParameterKey=VpcId,ParameterValue="${VpcId}" \
        ParameterKey=ClusterName,ParameterValue="${ClusterName}" \
        ParameterKey=ZoneName,ParameterValue="${OutpostAvailabilityZone}" \
        ParameterKey=PublicRouteTableId,ParameterValue="${PublicRouteTableId}" \
        ParameterKey=PublicSubnetCidr,ParameterValue="${PublicSubnetCidr}" \
        ParameterKey=PrivateRouteTableId,ParameterValue="${PrivateRouteTableId}" \
        ParameterKey=PrivateSubnetCidr,ParameterValue="${PrivateSubnetCidr}" \
        ParameterKey=OutpostArn,ParameterValue="${OutpostArn}" \
        ParameterKey=PrivateSubnetLabel,ParameterValue="private-outpost" \
        ParameterKey=PublicSubnetLabel,ParameterValue="public-outpost"
```

- List the subnets in Outpost:

```sh
aws ec2 describe-subnets --filters Name=outpost-arn,Values=${OutpostArn} Name=vpc-id,Values=$VpcId
```

- Export the subnets according to your needs:

> TODO get from CloudFormation template instead of discoverying

```sh
OutpostPublicSubnetId=$(aws ec2 describe-subnets --filters Name=outpost-arn,Values=${OutpostArn} Name=vpc-id,Values=$VpcId | jq -r '.Subnets[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .SubnetId }]'  | jq -r '.[] | select(.Name | contains("public")).Id')

OutpostPrivateSubnetId=$(aws ec2 describe-subnets --filters Name=outpost-arn,Values=${OutpostArn} Name=vpc-id,Values=$VpcId | jq -r '.Subnets[] | [{"Name": .Tags[]|select(.Key=="Name").Value, "Id": .SubnetId }]'  | jq -r '.[] | select(.Name | contains("private")).Id')
```

## Create Machine set manifest

- Export required variables:

```sh
# Choose from $ aws outposts get-outpost-instance-types
OutpostInstanceType=m5.xlarge
```

- Create machine set patch:

```sh
cat << EOF > ./outpost-machineset-patch.yaml
metadata:
  annotations: {}
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
    location: outpost
  name: ${CLUSTER_ID}-outposts-${OutpostAvailabilityZone}
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-outpost-${OutpostAvailabilityZone}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: outpost
        machine.openshift.io/cluster-api-machine-type: outpost
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-outpost-${OutpostAvailabilityZone}
        location: outpost
    spec:
      metadata:
        labels:
          node-role.kubernetes.io/outpost: ""
          location: outpost
      providerSpec:
        value:
          blockDevices:
            - ebs:
                volumeSize: 120
                volumeType: gp2
          instanceType: ${OutpostInstanceType}
          placement:
            availabilityZone: ${OutpostAvailabilityZone}
            region: ${AWS_REGION}
          subnet:
            id: ${OutpostPrivateSubnetId}
      taints: 
        - key: node-role.kubernetes.io/outpost
          effect: NoSchedule
EOF
```

- Retrieve Machine set and merge into yours

```sh
oc get machineset -n openshift-machine-api $(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.name}') -o yaml \
    | yq4 'del(
        .status,
        .metadata.uid,
        .spec.template.spec.providerSpec.value.subnet,
        .spec.template.metadata.labels,
        .metadata.annotations)' \
    > ./outpost-tpl-00.yaml

yq3 merge ./outpost-machineset-patch.yaml ./outpost-tpl-00.yaml > ./outpost-machineset.yaml
```

- Apply the Machine set

```
oc create -f ./outpost-machineset.yaml
```

Example output

```
$ oc get nodes -l node-role.kubernetes.io/outpost
NAME                         STATUS   ROLES            AGE   VERSION
ip-10-0-209-9.ec2.internal   Ready    outpost,worker   12h   v1.28.6+f1618d5


$ $ oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=outpost
NAME                                    PHASE     TYPE        REGION      ZONE         AGE
otp-00-n89jb-outpost-us-east-1a-zs5ps   Running   m5.xlarge   us-east-1   us-east-1a   12h


$ oc get machineset -n openshift-machine-api -l location=outpost
NAME                              DESIRED   CURRENT   READY   AVAILABLE   AGE   LABELS
otp-00-n89jb-outpost-us-east-1a   1         1         1       1           12h   machine.openshift.io/cluster-api-cluster=otp-00-n89jb
```

## Changing cluster network MTU 

The correct cluster network MTU is required for correctly operation of cluster network.

The steps below adjust the MTU based in the supported information from AWS: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/network_mtu.html

> Currently the supported value is: 1300

- check current value for cluster network MTU:

```sh
$ oc get network.config cluster -o yaml | yq4 ea .status
clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
clusterNetworkMTU: 8901
networkType: OVNKubernetes
serviceNetwork:
  - 172.30.0.0/16
```

- check current value for host network MTU:

```sh
NODE_NAME=$(oc get nodes -l node-role.kubernetes.io/outpost='' -o jsonpath={.items[0].metadata.name})
# Hardware MTU
oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "ip address show | grep -E '^(.*): ens'" 2>/dev/null
# CN MTU
oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "ip address show | grep -E '^(.*): br-int'" 2>/dev/null
```

Example output:

```sh
2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq master ovs-system state UP group default qlen 1000
```

- Patch

```sh
OVERLAY_TO=1200
OVERLAY_FROM=$(oc get network.config cluster -o jsonpath='{.status.clusterNetworkMTU}')
MACHINE_TO=$(oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "ip address show | grep -E '^([0-9]): ens'" 2>/dev/null | awk -F'mtu ' '{print$2}' | cut -d ' ' -f1)

oc patch Network.operator.openshift.io cluster --type=merge --patch \
  "{\"spec\": { \"migration\": { \"mtu\": { \"network\": { \"from\": $OVERLAY_FROM, \"to\": ${OVERLAY_TO} } , \"machine\": { \"to\" : $MACHINE_TO } } } } }"
```

- Check if the value has been updated

```yaml
$  oc get network.config cluster -o yaml | yq4 ea .status
clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
clusterNetworkMTU: 1200
migration:
  mtu:
    machine:
      to: 9001
    network:
      from: 8901
      to: 1200
networkType: OVNKubernetes
serviceNetwork:
  - 172.30.0.0/16
```

- Follow the progress
    - MachineConfigPool must be progressing:
    - Nodes will be restarted
    - Nodes must have correct MTU for overlay interface

```sh
# Wait until updating == true
oc get mcp -w

# View the nodes rebooting (or use the function check_node_mcp)
oc get nodes -w

function check_node_mcp() {
    MCP_WORKER=$(oc get mcp worker -o jsonpath='{.spec.configuration.name}')
    MCP_MASTER=$(oc get mcp master -o jsonpath='{.spec.configuration.name}')
    echo -e "\n$(date) Checking if nodes has desired config: master[${MCP_MASTER}] worker[${MCP_WORKER}]"
    for NODE in $(oc get nodes -o jsonpath='{.items[*].metadata.name}');
    do
        MCP_NODE=$(oc get node ${NODE} -o json | jq -r '.metadata.annotations["machineconfiguration.openshift.io/currentConfig"]');
        if [[ "$MCP_NODE" == "$MCP_MASTER" ]] || [[ "$MCP_NODE" == "$MCP_WORKER" ]];
        then
            NODE_CN_MTU=$(oc debug node/${NODE} --  chroot /host /bin/bash -c "ip address show | grep -E '^([0-9]): br-int'" 2>/dev/null | awk -F'mtu ' '{print$2}' | cut -d ' ' -f1)
            NODE_HOST_MTU=$(oc debug node/${NODE} --  chroot /host /bin/bash -c "ip address show | grep -E '^([0-9]): ens'" 2>/dev/null | awk -F'mtu ' '{print$2}' | cut -d ' ' -f1)
            echo -e "$NODE\t OK \t HOST_MTU=${NODE_HOST_MTU} CN_MTU=${NODE_CN_MTU}";
            continue;
        fi;
        echo -e "$NODE\t FAIL \t CURRENT[${MCP_NODE}] != DESIRED[${MCP_WORKER} || ${MCP_MASTER}]";
    done
    oc get mcp
}

while true; do check_node_mcp; sleep 15; done
```

- Apply the migration:

```sh
oc patch Network.operator.openshift.io cluster --type=merge --patch \
  "{\"spec\": { \"migration\": null, \"defaultNetwork\":{ \"ovnKubernetesConfig\": { \"mtu\": ${OVERLAY_TO} }}}}"
```

- Wait for cluster stable:

```sh
while true; do check_node_mcp; sleep 15; done
```

- Validating cluster network MTU

```sh
NODE_NAME=$(oc get nodes -l node-role.kubernetes.io/outpost='' -o jsonpath={.items[0].metadata.name})
KPASS=$(cat auth/kubeadmin-password)

API_INT=$(oc get infrastructures cluster -o jsonpath={.status.apiServerInternalURI})

oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "\
oc login --insecure-skip-tls-verify -u kubeadmin -p ${KPASS} ${API_INT}; \
podman login -u kubeadmin -p \$(oc whoami -t) image-registry.openshift-image-registry.svc:5000; \
podman pull image-registry.openshift-image-registry.svc:5000/openshift/tests"
```

Example output:

```sh
Starting pod/ip-10-0-209-9ec2internal-debug ...
To use host binaries, run `chroot /host`
WARNING: Using insecure TLS client config. Setting this option is not supported!

Login successful.

You have access to 70 projects, the list has been suppressed. You can list all projects with 'oc projects'

Using project "default".
Welcome! See 'oc help' to get started.
Login Succeeded!
Trying to pull image-registry.openshift-image-registry.svc:5000/openshift/tests:latest...
Getting image source signatures
Copying blob sha256:2799c1fb4d899f5800972dbe30772eb0ecbf423cc4221eca47f8c25873681089
..
Writing manifest to image destination
Storing signatures
ec9d578280946791263973138ea0955f665a684a55ef332313480f7f1dfceece

Removing debug pod ...
```

## Creating User Workloads in Outpost


- Create the application

```sh
APP_NAME=myapp-outpost
cat << EOF > ./outpost-app.yaml
kind: Namespace
apiVersion: v1
metadata:
  name: ${APP_NAME}
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NAME}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: gp2-csi 
  volumeMode: Filesystem
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NAME}
spec:
  selector:
    matchLabels:
      app: ${APP_NAME}
  replicas: 1
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        zone-type: outposts
    spec:
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      nodeSelector: 
        node-role.kubernetes.io/outpost: ''
      tolerations: 
      - key: "node-role.kubernetes.io/outpost"
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
          volumeMounts:
            - mountPath: "/mnt/storage"
              name: data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ${APP_NAME}
EOF

oc create -f ./outpost-app.yaml
```

- Check deployments

```sh
$ oc get pv -n myapp-outpost
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                         STORAGECLASS   REASON   AGE
pvc-0ea0c08b-5993-4e9d-93c2-201e77dcb9d8   10Gi       RWO            Delete           Bound    myapp-outpost/myapp-outpost   gp2-csi                 16s

$ oc get all -n  myapp-outpost
Warning: apps.openshift.io/v1 DeploymentConfig is deprecated in v4.14+, unavailable in v4.10000+
NAME                                READY   STATUS    RESTARTS   AGE
pod/myapp-outpost-cb94f9cd6-npczx   1/1     Running   0          20m

NAME                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/myapp-outpost   1/1     1            1           77m

NAME                                      DESIRED   CURRENT   READY   AGE
replicaset.apps/myapp-outpost-cb94f9cd6   1         1         1       77m
```

## Expose the deployment through services

Expose the deployments using different service types.

### Service NodePort

- Deploy services exposing the NodePort:

```sh
cat << EOF > ./outpost-svc-np.yaml
---
apiVersion: v1
kind: Service 
metadata:
  name:  ${APP_NAME}-np
  namespace: ${APP_NAME}
spec:
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: NodePort
  selector: 
    app: ${APP_NAME}
EOF
```

<!-- 
### Service LoadBalancer with AWS Classic Load Balancer (fail)

```sh
cat << EOF | oc create -f -
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${APP_NAME}-clb
  name: ${APP_NAME}-clb
  namespace: ${APP_NAME}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-subnets: ${OutpostPublicSubnetId}
    service.beta.kubernetes.io/aws-load-balancer-target-node-labels: node-role.kubernetes.io/outpost=''
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    app: ${APP_NAME}
  type: LoadBalancer
EOF
```

Error message
```
$ oc describe  svc myapp-outpost-clb -n ${APP_NAME}
Events:
  Type     Reason                  Age   From                Message
  ----     ------                  ----  ----                -------
  Normal   EnsuringLoadBalancer    9s (x4 over 48s)  service-controller  Ensuring load balancer
  Warning  SyncLoadBalancerFailed  8s                service-controller  Error syncing load balancer: failed to ensure load balancer: ValidationError: You cannot use Outposts subnets for load balancers of type 'classic'
           status code: 400, request id: a90e376b-4ac4-4d5a-b3d3-127e025168f
```

- Test creating service in the regino


```sh
cat << EOF | oc create -f -
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${APP_NAME}-lb-default
  name: ${APP_NAME}-lb-default
  namespace: ${APP_NAME}
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    app: ${APP_NAME}
  type: LoadBalancer
EOF
``` -->

### Create a service with ALB ingress

Steps to deploy the service using Application Load Balancer on Outpost with ALBO (AWS Load Balancer Operator).

#### Install ALBO

- Install ALBO
```sh
ALBO_NS=aws-load-balancer-operator

# Install the Operator from OLM:
# Create the subscription:
cat << EOF | oc create -f -
---
kind: Namespace
apiVersion: v1
metadata:
  name: ${ALBO_NS}
---
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

---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: $ALBO_NS
  namespace: $ALBO_NS
spec:
  targetNamespaces:
  - $ALBO_NS

---
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

oc get CredentialsRequest aws-load-balancer-operator -n openshift-cloud-credential-operator
oc get OperatorGroup $ALBO_NS -n $ALBO_NS
oc get Subscription $ALBO_NS -n $ALBO_NS
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


#### Create ALB ingress in Outpost


- Deploy the service using the ingress

```sh
cat << EOF > ./outpost-svc-alb.yaml
---
apiVersion: v1
kind: Service 
metadata:
  name: ${APP_NAME}-svc-alb
  namespace: ${APP_NAME}
spec:
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: NodePort
  selector:
    app: ${APP_NAME}
EOF

# review and apply
oc create -f ./outpost-svc-alb.yaml
```

- Create the Ingress in Outpost subnet selecting only the instance running in Outpost as a target:

```sh
cat << EOF | oc create -f -
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: outpost-${APP_NAME}
  namespace: ${APP_NAME}
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: instance
    alb.ingress.kubernetes.io/subnets: ${OutpostPublicSubnetId}
    alb.ingress.kubernetes.io/target-node-labels: location=outpost
  labels:
    location: outpost
spec:
  ingressClassName: cloud
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${APP_NAME}-svc-alb
                port:
                  number: 80
EOF
```

## Destroy the cluster


- Delete the Outpost machine set:

```sh
oc delete machineset -n openshift-machine-api -l location=outpost
```

- Delete the CloudFormation stack for subnet:

```sh
aws cloudformation delete-stack --stack-name ${STACK_NAME}
```

- Delete cluster:

```sh
./openshift-install destroy cluster --log-level debug
```