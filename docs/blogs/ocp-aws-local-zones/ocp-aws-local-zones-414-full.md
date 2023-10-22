# Extending Red Hat OpenShift Container Platform to AWS Local Zones

> Authors: Marco Braga, Marcos Entenza Garcia, Fatih Nar

OpenShift users have many options when it comes to deploying a Red Hat OpenShift cluster
in AWS. In Red Hat OpenShift Container Platform 4.12, we introduced the manual steps
to extend cluster nodes into Amazon Web Services (AWS) Local Zones when installing in existing VPC.
We are pleased to announce in OpenShift 4.14 the fully IPI (installer-provisioned infrastructure) automation
to extend worker nodes to AWS Local Zones.

## What is AWS Local Zones?

[Local Zones][aws-localzones] allow you to use selected AWS services, like compute and storage services, closer to the metropolitan region, and end-users, than the regular zones, providing them with very low latency access to the applications running locally. Local Zones are fully owned and managed by AWS with no upfront commitment and no hardware purchase or lease required. In addition, Local Zones connect to the parent AWS cloud region via AWS' redundant and very high-bandwidth private network, providing applications running in Local Zones fast, secure, and seamless access to the rest of AWS services.

![AWS Infrastructure Continuum][aws-infrastructure-continuum]

<p align="center">Figure 1 AWS Infrastructure Continuum</p>

## OpenShift and AWS Local Zones

Using OpenShift with Local Zones, application developers and service consumers might have the following benefits:

- Improving application performance and user experience by hosting resources closer to the user. Local Zones reduce the time it takes for data to travel over the network, resulting in faster load times and more responsive applications. This is especially important for applications, such as video streaming or online gaming, that require low-latency performance and real-time data access.
- Saving costs by avoiding data transfer charges when hosting resources in specific geographic locations, whereby customers avoid high costs associated with data transfer charges, such as cloud egress charges, which is a significant business expense, when large volumes of data are moved between regions in the case of image, graphics, and video related applications.
- Providing to regulated industries, such as healthcare, government agencies, financial institutions, and others, a way to meet data residency requirements by hosting data and applications in specific locations to comply with regulatory laws and mandates.

## AWS Local Zones limitations in OpenShift

There are a few limitations in the current AWS Local Zones offering that requires attention when deploying OpenShift:

- The Maximum Transmission Unit (MTU) between an Amazon EC2 instance in a Local Zone and an Amazon EC2 instance in the Region is 1300. This causes the overlay network MTU to change according to the network plugin that is used on the deployment.
- Network resources such as Network Load Balancer (NLB), Classic Load Balancer, and Nat Gateways are not globally available in AWS Local Zones, so the installer will not deploy those resources automatically.
- The AWS Elastic Block Storage (EBS) volume type `gp3` is the default for node volumes and the storage class set on AWS OpenShift clusters. This volume type is not globally available in Local Zones locations. By default, the nodes running in Local Zones are deployed with the `gp2` EBS volume type, and the `gp2-csi` StorageClass must be set when creating workloads into those nodes.

## Hands-on!

The following sections describe how to deploy OpenShift compute nodes in Local Zones at cluster creation time, where the OpenShift Installer fully automates the cluster installation including network components in configured Local Zones. In addition, the Day 2 Operations section is added demonstrating how the cluster administrator extends compute nodes in Local Zones to an existing OpenShift cluster.

After the cluster is installed, a sample application is deployed and exposed to ingress traffic throughout the zone, demonstrating workloads in Local Zones, and measuring the network connection time from different locations.

The following diagram plots the geographically distributed deployment explored in this use case:

> TODO> the following image will be replaced with less blank parts, focusing in the cluster and clients components

![aws-local-zones-diagram-ocp-lz-413-map drawio][aws-local-zones-diagram-ocp-lz-413-map]

<p align="center">Figure 2 User Workloads in Local Zones</p>

The topology diagram below shows the infrastructure components created by the IPI installation:

- One standard OpenShift Cluster is installed in `us-east-1` with three Control Plane nodes and three Compute nodes.
- One regular VPC and subnets in Availability Zones.
- Public and private subnets in the Local Zone of the New York metropolitan region (`us-east-1-nyc-1a`).
- One `edge` compute node in the private subnet of `us-east-1-nyc-1a` zone;

Additionally, the steps for the Day 2 operation create:

- One Application Load Balancer exposing a sample application running in the Local Zone worker node.
- One public subnet in the Buenos Aires metropolitan region (`us-east-1-bue-1a`).
- One `edge` compute node in the public subnet of zone `us-east-1-bue-1a`

![aws-local-zones-diagram-blog-hc-414-diagram drawio][aws-local-zones-diagram-blog-hc-414-diagram]

<p align="center">Figure 3 OpenShift Cluster installed in us-east-1 extending nodes to Local Zone in New York</p>

## Installing an OpenShift cluster with AWS Local Zones

To deploy an OpenShift cluster extending compute nodes in Local Zone subnets, it is required to define the `edge` compute pool in the `install-config.yaml` file, not enabled by default.

The installation process creates the network components in Local Zone classifying those as "Edge Zone", creating MachineSet manifests for each location. See the [OpenShift documentation][ocp-docs-localzone] for more details.

Once the cluster is installed, the label `node-role.kubernetes.io/edge` is set to each node located in the Local Zones, along with the regular `node-role.kubernetes.io/worker`.

### Prerequisites

Install the following prerequisites before you proceed to the next step:

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [OpenShift Installer 4.14+](https://console.redhat.com/openshift/downloads)
- [OpenShift CLI](https://console.redhat.com/openshift/downloads)

### Step 1. Enable the AWS Local Zone Group

The zones in Local Zones are not enabled by default, the zone group needs to opt-in before creating resources in those locations.

You can list the available Local Zones and the attributes using the operation DescribeAvailabilityZones with AWS CLI:

```bash
aws --region us-east-1 ec2 describe-availability-zones \
    --query 'AvailabilityZones[].[{ZoneName: ZoneName, GroupName: GroupName, Status: OptInStatus}]' \
    --filters Name=zone-type,Values=local-zone \
    --all-availability-zones
```

To enable the Local Zone in New York (used in this post), run:

```bash
aws ec2 modify-availability-zone-group \
    --group-name "us-east-1-nyc-1" \
    --opt-in-status opted-in
```

### Step 2. Create the OpenShift Cluster

Create the `install-config.yaml` setting for the AWS Local Zone name in the `edge`
compute pool:

~~~yaml
apiVersion: v1
publish: External
baseDomain: "<CHANGE_ME: Base Domain>"
metadata:
  name: demo-lz
compute:
  - name: edge
    platform:
      aws:
        zones:
        - us-east-1-nyc-1a
platform:
  aws:
    region: us-east-1
pullSecret: '<CHANGE_ME: pull-secret-content>'
sshKey: |
  '<CHANGE_ME: ssh-keys>'
~~~

Create the cluster:

~~~bash
./openshift-install create cluster
~~~

That's it, the installer program creates all the infrastructure and configuration required to extend worker nodes in the selected location.

Once the installation is finished, review the EC2 worker node status provisioned by Machine API:

~~~bash
export KUBECONFIG=$PWD/auth/kubeconfig
./oc get machines -l machine.openshift.io/cluster-api-machine-role=edge -n openshift-machine-api
~~~
~~~text
NAME                                        PHASE     TYPE          REGION      ZONE               AGE
demo-lz-tvqld-edge-us-east-1-nyc-1a-scgjl   Running   c5d.2xlarge   us-east-1   us-east-1-nyc-1a   21m
~~~

You can also check the nodes created in AWS Local Zones after the machine is in the `Running` phase, labeled with `node-role.kubernetes.io/edge`:

~~~bash
./oc get nodes -l node-role.kubernetes.io/edge
~~~
~~~text
NAME                           STATUS   ROLES         AGE     VERSION
ip-10-0-194-188.ec2.internal   Ready    edge,worker   5m45s   v1.27.3+4aaeaec
~~~

![ocp-aws-localzones-step4-ocp-nodes-ec2][ocp-aws-localzones-step4-ocp-nodes-ec2]

<p align="center">Figure 4: OpenShift nodes created by the installer in AWS EC2 Console</p>

## Extending an existing OpenShift cluster to new AWS Local Zones

It is also possible to extend the existing cluster installed with the support of
Local Zones (Day 2) to new locations, allowing you to expand geographically
when it needs.

The steps in this section describe the Day 2 operations steps to extend
the compute node to a new location of Buenos Aires (`us-east-1-bue-1a`) in an existing
OpenShift cluster

### Prerequisites

- The cluster must be installed with Local Zones support. If the cluster was not installed using IPI with Local Zone support, the Maximum Transmit Unit (MTU) for the cluster-wide network must be adjusted before proceeding. See the "[AWS Local Zone tasks][ocp-aws-localzones-day2]" in the OpenShift documentation for more information.

- Export the variables:

```bash
export CLUSTER_NAME=demo-lz
export CLUSTER_BASEDOMAIN="example.com"

export AWS_REGION=us-east-1
export LOCAL_ZONE_GROUP_NYC="${AWS_REGION}-nyc-1"
export LOCAL_ZONE_NAME_NYC="${LOCAL_ZONE_GROUP_NYC}a"

export INFRA_ID="$(./oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')"

export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${INFRA_ID}-vpc" --query Vpcs[].VpcId --output text)
```

- The VPC running the cluster must have available CIDR blocks to create the subnet(s). You can check existing CIDR blocks allocated to the subnets within the VPC by running the following command:

```bash
aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=$VPC_ID \
  --query 'sort_by(Subnets, &Tags[?Key==`Name`].Value|[0])[].{
    SubnetName: Tags[?Key==`Name`].Value|[0],
    CIDR: CidrBlock
  }'
```

- Install `yq` utility to help when patching the manifests

```bash
yq_version=v4.34.2
yq_bin_arch=yq_linux_amd64
wget https://github.com/mikefarah/yq/releases/download/${yq_version}/${yq_bin_arch} \
  -O ./yq && chmod +x ./yq
```

### Step 1. Create the public subnet in the AWS Local Zone

The step describes how to create a subnet associated with the VPC Public Route table created by the installer using the AWS Cloud Formation template provided by OpenShift Installer.

- Create the required environment variables to create the subnet in the zone `us-east-1-bue-1a`:

~~~bash
export LOCAL_ZONE_CIDR_BUE="10.0.208.0/24"
export LOCAL_ZONE_GROUP_BUE="${AWS_REGION}-bue-1"
export LOCAL_ZONE_NAME_BUE="${LOCAL_ZONE_GROUP_BUE}a"
export PARENT_ZONE_NAME_BUE="$(aws ec2 describe-availability-zones \
  --all-availability-zones \
  --filters Name=zone-name,Values=${LOCAL_ZONE_NAME_BUE} \
  --query AvailabilityZones[].ParentZoneName --output text)"

export VPC_RTB_PUB=$(aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=${INFRA_ID}-public" \
  --query RouteTables[].RouteTableId --output text)

export SUBNET_NAME_BUE="${INFRA_ID}-public-${LOCAL_ZONE_NAME_BUE}"
export STACK_LZ=${INFRA_ID}-${LOCAL_ZONE_NAME_BUE}
~~~

- Enable the Zone Group:

```bash
aws ec2 modify-availability-zone-group \
    --group-name "${LOCAL_ZONE_GROUP_BUE}" \
    --opt-in-status opted-in
```

- Download the CloudFormation Template from the OpenShift documentation saving with the name `template-lz.yaml`: [CloudFormation template for the subnet that uses AWS Local Zones][ocp-aws-cloudformation-localzone-subnet].

- Create the CloudFormation stack to deploy the Local Zone subnet:

```bash
aws cloudformation create-stack --stack-name ${STACK_LZ} \
  --template-body file://template-lz.yaml \
  --parameters \
      ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
      ParameterKey=PublicRouteTableId,ParameterValue="${VPC_RTB_PUB}" \
      ParameterKey=ZoneName,ParameterValue="${LOCAL_ZONE_NAME_BUE}" \
      ParameterKey=SubnetName,ParameterValue="${SUBNET_NAME_BUE}" \
      ParameterKey=PublicSubnetCidr,ParameterValue="${LOCAL_ZONE_CIDR_BUE}" &&\
  aws cloudformation wait stack-create-complete --stack-name ${STACK_LZ}
```

- Export the subnet ID to be used later when creating a custom Ingress Controller:

```bash
export SUBNET_ID_BUE=$(aws cloudformation describe-stacks --stack-name "${STACK_LZ}" \
  | jq -r .Stacks[0].Outputs[0].OutputValue)
```

![ocp-aws-localzones-step5-cfn-subnet-bue-1a][ocp-aws-localzones-step5-cfn-subnet-bue-1a]

<p align="center">Figure 5: CloudFormation Stack for Local Zone subnet in us-east-1-bue-1a</p>

### Step 2. Create the additional Security Group

An additional security group with rules allowing ingress traffic for the ingress will be created and attached to the nodes in `us-east-1-bue-1a` zone. It is created to handle the existing Application Load Balancer (ALB) limitation in some locations, preventing the ingress traffic from a regular cloud-based load balancer through the ingress controller.

```bash
SG_NAME_INGRESS=${INFRA_ID}-localzone-ingress
SG_ID_INGRESS=$(aws ec2 create-security-group \
  --group-name ${SG_NAME_INGRESS} \
  --description "${SG_NAME_INGRESS}" \
  --vpc-id ${VPC_ID} | jq -r .GroupId)
```

Create the Security Group inbound rule allowing traffic by HTTP(80) used by the sharded ingress controller:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_INGRESS \
  --protocol tcp \
  --port 80 \
  --cidr "0.0.0.0/0"
```

### Step 3. Create MachineSet

The OpenShift component responsible for creating instances in the cloud provider is the Machine API (MAPI). The MachineSet manifest is added setting the zone attributes, and edge compute pool labels created by the installer.

The steps below show how to check the instance offered by the zone, and create the MachineSet manifest based on the existing one created by the installer (`us-east-1-nyc-1a`) to the Local Zone in Buenos Aires(`us-east-1-bue-1a`):

<!-- > Note: The Local Zone of Buenos Aires (`us-east-1-bue-1a`) was intentionally picked as it currently does not support AWS Application Load Balancers (ALB), used in New York zone (`us-east-1-nyc-1a`). -->

- Check and export the instance type offered by the Zone:

```bash
aws ec2 describe-instance-type-offerings --region ${AWS_REGION} \
  --location-type availability-zone \
  --filters Name=location,Values=${LOCAL_ZONE_NAME_BUE} \
  --query 'InstanceTypeOfferings[*].InstanceType' --output text
```
```text
t3.xlarge   c5.4xlarge
t3.medium   c5.12xlarge
c5.2xlarge  r5.2xlarge  m5.2xlarge
g4dn.2xlarge
```

- Set the name of the desired type:

```bash
export INSTANCE_TYPE_BUE=m5.2xlarge
```

- Export existing Machineset manifest and patch to the new location:

```bash
# Discover the machineset name from nyc-1
export BASE_MACHINESET_NYC=$(./oc get machineset -n openshift-machine-api \
  -o jsonpath='{range .items[*].metadata}{.name}{"\n"}{end}' | grep nyc-1)

# Extract the machineset manifest from nyc replacing the zone reference from NYC to BUE
./oc get machineset -n openshift-machine-api ${BASE_MACHINESET_NYC} -o yaml \
  | sed -s "s/nyc-1/bue-1/g" > machineset-lz-bue-1a.yaml

# Remove unused configurations
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

# Create a patch for the new location
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
                  - ${INFRA_ID}-localzone-public-ingress
EOF

# Apply the patch
./yq -i '. *= load("machineset-lz-bue-1a.patch.yaml")' machineset-lz-bue-1a.yaml
```

- Create the Machineset:

```bash
./oc create -f machineset-lz-bue-1a.yaml
```

- Wait for the machine creation:

```bash
./oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=edge
```
```text
NAME                                        PHASE         TYPE          REGION      ZONE               AGE
demo-lz-tvqld-edge-us-east-1-bue-1a-rvbb5   Provisioned   m5.2xlarge    us-east-1   us-east-1-bue-1a   79s
demo-lz-tvqld-edge-us-east-1-nyc-1a-scgjl   Running       c5d.2xlarge   us-east-1   us-east-1-nyc-1a   4h43m
```

The instance creation could take some time to finish, make sure the machine is in the Running phase before proceeding to the next steps.

All done, now the cluster has nodes running into two Local Zones: New York (US) and Buenos Aires (Argentina).

![ocp-aws-localzones-step5-ec2-bue-1a][ocp-aws-localzones-step5-ec2-bue-1a]

<p align="center">Figure 6: OpenShift nodes running in AWS Local Zones in EC2 Console</p>

## Deploying workloads in AWS Local Zones

This section demonstrates how to take advantage of Local Zones by deploying a sample application and selecting workers running into different locations.

Three deployments are created:

- Application running in the Region: ingressing the traffic using the OpenShift default router
- Application running in Local Zone NYC (US): ingressing traffic using Application Load Balancer
- Application running in Local Zone Buenos Aires (Argentina): ingressing traffic directly to the node (currently the zone does not support AWS Application Load Balancers)

The `edge` compute nodes deployed in Local Zones have the following extra labels:

~~~yaml
machine.openshift.io/zone-type: local-zone
machine.openshift.io/zone-group: us-east-1-<localzone_identifier>-1
node-role.kubernetes.io/edge: ""
~~~

You must set the tolerations to `node-role.kubernetes.io/edge`, selecting the node according to your use case.

The example below uses the `machine.openshift.io/zone-group` label to select the node(s), and creates the deployment for a sample application in the respective zone's network border group:

- Create the namespace:

~~~bash
export APPS_NAMESPACE="localzone-apps"
./oc create namespace ${APPS_NAMESPACE}
~~~

- Create the function to create the deployments for each location:

~~~bash
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
~~~

- Create the application for each location:

~~~bash
# App running in a node in New York
create_deployment "${AWS_REGION}-nyc-1" "app-nyc-1" "yes"

# App running in a node in Buenos Aires
create_deployment "${AWS_REGION}-bue-1" "app-bue-1" "yes"
~~~

Lastly, to deploy the application in the nodes running in the Region (regular/Availability Zones), a random node is picked and set up:

~~~bash
NODE_NAME=$(./oc get nodes -l node-role.kubernetes.io/worker='',topology.kubernetes.io/zone=${AWS_REGION}a \
  -o jsonpath='{.items[0].metadata.name}')

./oc label node ${NODE_NAME} machine.openshift.io/zone-group=${AWS_REGION}

# Deploy a running in a node in the regular zones
create_deployment "${AWS_REGION}" "app-default"
~~~

All set, all applications must be running into different locations:

```bash
./oc get pods -o wide  -n $APPS_NAMESPACE
```
```text
NAME                           READY   STATUS    RESTARTS   AGE     IP            NODE                          NOMINATED NODE   READINESS GATES
app-bue-1-689b95f4c4-jf6fb     1/1     Running   0          5m4s    10.131.2.6    ip-10-0-156-17.ec2.internal   <none>           <none>
app-default-857b5dc59f-r8cst   1/1     Running   0          75s     10.130.2.24   ip-10-0-51-38.ec2.internal    <none>           <none>
app-nyc-1-54ffd5c89b-bbhqp     1/1     Running   0          5m31s   10.131.0.6    ip-10-0-128-81.ec2.internal   <none>           <none>
```
```bash
./oc get pods --show-labels -n $APPS_NAMESPACE
```
```text
NAME                           READY   STATUS    RESTARTS   AGE     LABELS
app-bue-1-689b95f4c4-jf6fb     1/1     Running   0          5m16s   app=app-bue-1,pod-template-hash=689b95f4c4,zoneGroup=us-east-1-bue-1
app-default-857b5dc59f-r8cst   1/1     Running   0          87s     app=app-default,pod-template-hash=857b5dc59f,zoneGroup=us-east-1
app-nyc-1-54ffd5c89b-bbhqp     1/1     Running   0          5m43s   app=app-nyc-1,pod-template-hash=54ffd5c89b,zoneGroup=us-east-1-nyc-1
```

## Exposing applications to ingress traffic from internet

It's time to create to expose the application to the internet targeting ingressing the traffic from each zone group.

When this blog was written, Local Zones had limited support of AWS Load Balancers, supporting only AWS Application Load Balancer (ALB) with limited locations. To expose the application to end users using ALB, you need to create, when supported, a custom ingress for each location by using the [AWS Application Load Balancer (ALB) Operator][ocp-aws-albo].

In our example, only NYC Zone supports ALB and will use it to expose the sample app.  A new sharded router is deployed running in `Buenos Aires` node, ingressing the traffic directly from that location (`us-east-1-bue-1a`).

> Q: Do we need to add a diagram showing those three different types of exposing applications?

### Ingress for Availability Zone's app

Create the service and expose the application running in the region using the default router:

~~~bash
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
~~~

- After the Load Balancer is created, export the `APP_HOST_AZ` address for that location:

```bash
APP_HOST_AZ="$(oc get -n ${APPS_NAMESPACE} route.route.openshift.io/app-default -o jsonpath='{.status.ingress[0].host}')"
```

### Ingress for NYC (New York) Local Zone app

Create the ALB Operator following the steps listed in [Installing the AWS Load Balancer Operator][ocp-aws-albo-installing], then [Create the ALB Controller][ocp-aws-albo-controller].

- Make sure the ALB Controllers are running before proceeding:

```bash
./oc get pods -n aws-load-balancer-operator 
```
```text
NAME                                                             READY   STATUS    RESTARTS   AGE
aws-load-balancer-controller-cluster-567bc99b68-rnkjn            1/1     Running   0          43s
aws-load-balancer-controller-cluster-567bc99b68-s7w4z            1/1     Running   0          43s
aws-load-balancer-operator-controller-manager-7674db45d6-hmswz   2/2     Running   0          90s
```

- Extract the public subnet ID from NYC's Local Zone used by the Application load Balancer:

```bash
SUBNET_NAME_NYC="${INFRA_ID}-public-${LOCAL_ZONE_NAME_NYC}"

SUBNET_ID_NYC=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=$VPC_ID \
  --query "Subnets[].{Name: Tags[?Key==\`Name\`].Value|[0], ID: SubnetId} | [?Name==\`${SUBNET_NAME_NYC}\`].ID" \
  --output text)
```

- Create the custom Ingress on that location:

```bash
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
```

- Review the new ingress:

```bash
./oc get ingress  -n ${APPS_NAMESPACE}
```
```text
NAME               CLASS   HOSTS   ADDRESS                                                                   PORTS   AGE
ingress-lz-nyc-1   cloud   *       k8s-localzon-ingressl-814f3fc007-1883787437.us-east-1.elb.amazonaws.com   80      4s
```

![ocp-aws-localzones-step7-alb-nyc][ocp-aws-localzones-step7-alb-nyc]

<p align="center">Figure 7: Load Balancer created for the ingress using NYC Local Zone subnet</p>

![ocp-aws-localzones-step7-alb-tg-nyc][ocp-aws-localzones-step7-alb-tg-nyc]

<p align="center">Figure 8: Target Group added the Local Zone node as a target</p>

Once the Application Load Balancer has been provisioned, get the DNS name and test it:

```bash
APP_HOST_NYC=$(./oc get ingress -n ${APPS_NAMESPACE} ingress-lz-nyc-1 \
  --template='{{(index .status.loadBalancer.ingress 0).hostname}}')

while ! curl $APP_HOST_NYC; do sleep 5; done
```
```text
GET / HTTP/1.1
(...)
```

### Ingress for BUE (Buenos Aires) Local Zone app

Create a sharded ingress controller running in the `Buenos Aires` node using HostNetwork:

~~~bash
$ cat << EOF | ./oc create -f -
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: ingress-lz-bue-1
  namespace: openshift-ingress-operator
  labels:
    zoneGroup: us-east-1
spec:
  endpointPublishingStrategy:
    type: HostNetwork
  replicas: 1
  domain: apps-bue1.${CLUSTER_NAME}.${CLUSTER_BASEDOMAIN}
  nodePlacement:
    nodeSelector:
      matchLabels:
        machine.openshift.io/zone-group: us-east-1-bue-1
    tolerations:
      - key: "node-role.kubernetes.io/edge"
        operator: "Equal"
        value: ""
        effect: "NoSchedule"
  routeSelector:
    matchLabels:
      type: sharded
EOF
~~~

Create the service and the route:

~~~bash
$ cat << EOF | ./oc create -f -
apiVersion: v1
kind: Service 
metadata:
  name: app-bue-1
  namespace: ${APPS_NAMESPACE}
  labels:
    zoneGroup: us-east-1-bue-1
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
~~~

Discover and set the Buenos Aires' ingress address:

```bash
APP_HOST_BUE="$(./oc get route.route.openshift.io/app-bue-1 -o jsonpath='{.status.ingress[0].host}')"

IP_HOST_BUE="$(./oc get nodes -l topology.kubernetes.io/zone=us-east-1-bue-1a -o json | jq -r '.items[].status.addresses[] | select (.type=="ExternalIP").address')"

curl -H "Host: $APP_HOST_BUE" http://$IP_HOST_BUE
```

<!-- 
> TMP Note: DNS config: the controller is not adding the DNSes to the public zone for the custom ingress controller. How DNS creates RR automatically for the sharded routers which don't use service LB, but HostNetwork with public IP address on the host interface? -->

## Benchmarking the applications connection time

It is time to test each application endpoint from different locations on the internet, some are closer to the metropolitan regions located in the Local Zone, so we'll be able to measure the network benefits of using edge compute pools in OpenShift.

The tests make a few requests from different clients, extracting the [`curl` variables writing it out][curl-vars-wout] to the console.

Generate the script `curl.sh` to test the endpoints:

~~~bash
cat <<EOF > curl.sh
#!/usr/bin/env bash
echo "# Client Location:"
curl -s http://ip-api.com/json/\$(curl -s ifconfig.me) |jq -r '[.city, .countryCode]'

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
~~~

Copy and run `curl.sh` to the clients and run it:

```bash
bash curl.sh 
```

- Results of the **client** located in the region of **US/New York**:

```text
# Client Location: 
["North Bergen", "US"]

# Collecting request times to server running in AZs/Regular zones
# [endpoint app-default-localzone-apps.apps.demo-lz.devcluster.openshift.com]
time_namelookup  time_connect    time_starttransfer      time_total
0.010444         0.018078        0.031563                0.032449
0.012000         0.019141        0.030801                0.031725
0.000777         0.007918        0.019087                0.019860
0.001437         0.008690        0.020179                0.020955
0.005015         0.011915        0.023527                0.024309

# Collecting request times to server running in Local Zone NYC
# [endpoint k8s-localzon-ingressl-573f917a81-716983909.us-east-1.elb.amazonaws.com]
time_namelookup  time_connect    time_starttransfer      time_total
0.002986         0.005248        0.009702                0.010571
0.001368         0.003183        0.006447                0.007270
0.001100         0.002503        0.005711                0.006586
0.003174         0.004643        0.007955                0.008725
0.003144         0.004601        0.007663                0.008500

# Collecting request times to server running in Local Zone BUE
# [endpoint app-bue-1.apps-bue1.demo-lz.devcluster.openshift.com]
time_namelookup  time_connect    time_starttransfer      time_total
0.000026         0.141142        0.284566                0.285606
0.000027         0.141474        0.284454                0.285362
0.000025         0.141334        0.284213                0.285045
0.000023         0.141085        0.283620                0.284515
0.000026         0.141586        0.284625                0.285490
```

- Results of the **client** located in the region of **UK/London**:

~~~text
# Client Location: 
["Enfield", "GB"]

# Collecting request times to server running in AZs/Regular zones
# [endpoint app-default-localzone-apps.apps.demo-lz.devcluster.openshift.com]
time_namelookup  time_connect    time_starttransfer      time_total
0.014856         0.096285        0.181679                0.182629
0.001565         0.079669        0.162386                0.163355
0.001891         0.081879        0.165896                0.166834
0.001465         0.080108        0.163756                0.164491
0.001224         0.081282        0.165828                0.166998

# Collecting request times to server running in Local Zone NYC
# [endpoint k8s-localzon-ingressl-573f917a81-716983909.us-east-1.elb.amazonaws.com]
time_namelookup  time_connect    time_starttransfer      time_total
0.002339         0.092894        0.184171                0.185058
0.001506         0.085278        0.167627                0.168613
0.001176         0.083452        0.167570                0.168474
0.001483         0.092990        0.186173                0.186859
0.001130         0.083462        0.167462                0.168527

# Collecting request times to server running in Local Zone BUE
# [endpoint app-bue-1.apps-bue1.demo-lz.devcluster.openshift.com]
time_namelookup  time_connect    time_starttransfer      time_total
0.000046         0.229893        0.462351                0.463439
0.000030         0.233715        0.468338                0.469316
0.000057         0.230159        0.462013                0.463272
0.000041         0.230470        0.462181                0.463116
0.000044         0.228971        0.459642                0.460627
~~~

- Results of the **client** located in the region of **Brazil/South**:

~~~text
# Client Location: 
["Florianópolis", "BR"]

# Collecting request times to server running in AZs/Regular zones
# [endpoint app-default-localzone-apps.apps.demo-lz.devcluster.openshift.com]
time_namelookup time_connect time_starttransfer time_total
0.022768        0.172481     0.324897           0.326504
0.024175        0.178215     0.337317           0.338611
0.029904        0.183622     0.338799           0.340016
0.016936        0.172481     0.331656           0.333060
0.023056        0.174012     0.332869           0.333940

# Collecting request times to server running in Local Zone NYC
# [endpoint k8s-localzon-ingressl-573f917a81-716983909.us-east-1.elb.amazonaws.com]
time_namelookup time_connect time_starttransfer time_total
0.023081        0.182175     0.339818           0.340769
0.022908        0.187502     0.353711           0.354144
0.024140        0.181430     0.342511           0.343637
0.016736        0.175075     0.337191           0.338269
0.017669        0.180589     0.342865           0.343365

# Collecting request times to server running in Local Zone BUE
# [endpoint app-bue-1.apps-bue1.demo-lz.devcluster.openshift.com]
time_namelookup time_connect time_starttransfer time_total
0.000016        0.044052     0.090594           0.091382
0.000018        0.043565     0.090848           0.091869
0.000015        0.046529     0.092182           0.092997
0.000019        0.043899     0.089382           0.090326
0.000016        0.044163     0.089726           0.090368
~~~

- Aggregated results:

<p align="center">
  <img src="https://github.com/mtulio/mtulio.labs/assets/3216894/9250fb62-fd99-4c31-9d77-178c82e38cb7" />
  <p align="center"> Figure 9: Average connect and total time with slower points based on the baseline (fastest) </p>
</p>

The total time to connect, in milliseconds, from the client in NYC (outside AWS) to the OpenShift edge node running in the Local Zone was ~66% lower than the application running in the regular zones. It's also worth mentioning that there are benefits when clients accessing from different countries: the results from the client in Brazil decreased by more than 100% of the total request time when accessing the Buenos Aires deployment, instead of going to the Region's app due to the geographic proximity of those locations.

<p align="center">
  <img src="https://github.com/mtulio/mtulio.labs/assets/3216894/85c059f3-cfe5-4381-a4b4-fba7cce976d2" />
  <p align="center"> Figure 10: Client in NYC getting better experience accessing the NYC Local Zone, than the app in the region </p>
</p>


## Summary

OpenShift provides a platform for easy deployment, scaling, and management of containerized applications across the hybrid cloud including AWS. Using OpenShift with AWS Local Zones provides numerous benefits for organizations. It allows for lower latency and improved network performance as Local Zones are physically closer to end users, which enhances the overall user experience and reduces downtime. The combination of OpenShift and AWS Local Zones provides a flexible and scalable solution that enables organizations to modernize their applications and meet the demands of their customers and users:

- 1) improving application performance and user experience,
- 2) hosting resources in specific geographic locations reducing overall cost and
- 3) providing regulated industries with a way to meet data residency requirements.


## Categories

- OpenShift 4
- Edge
- AWS
- How-tos

<!-- 
External References
 -->

[aws-localzones]: https://aws.amazon.com/about-aws/global-infrastructure/localzones/

[ocp-docs-localzone]: https://docs.openshift.com/container-platform/4.14/installing/installing_aws/installing-aws-localzone.html 

[ocp-aws-cloudformation-localzone-subnet]: https://docs.openshift.com/container-platform/4.13/installing/installing_aws/installing-aws-localzone.html#installation-cloudformation-subnet-localzone_installing-aws-localzone

[ocp-aws-albo]: https://docs.openshift.com/container-platform/4.12/networking/aws_load_balancer_operator/understanding-aws-load-balancer-operator.html

[ocp-aws-albo-installing]: https://docs.openshift.com/container-platform/4.12/networking/aws_load_balancer_operator/install-aws-load-balancer-operator.html

[ocp-aws-albo-controller]: https://docs.openshift.com/container-platform/4.12/networking/aws_load_balancer_operator/create-instance-aws-load-balancer-controller.html

[ocp-aws-localzones-day2]: https://docs.openshift.com/container-platform/4.14/post_installation_configuration/aws-compute-edge-tasks
<!-- Under development to 4.14:
- https://github.com/openshift/openshift-docs/pull/60771
- https://63729--docspreview.netlify.app/openshift-enterprise/latest/post_installation_configuration/aws-compute-edge-tasks -->

[curl-vars-wout]: https://curl.se/docs/manpage.html#-w

<!-- 
Images hosted in github user content
 -->

[aws-infrastructure-continuum]: https://github.com/mtulio/mtulio.labs/assets/3216894/b4e68d09-bc65-40f4-91aa-1f1cbdea06e6

[aws-local-zones-diagram-ocp-lz-413-map]: https://github.com/mtulio/mtulio.labs/assets/3216894/2fe7ae42-5b1a-4f7c-9e95-f063489eadc6

[aws-local-zones-diagram-blog-hc-414-diagram]: https://github.com/mtulio/mtulio.labs/assets/3216894/6377e5ff-2489-46ce-8f1b-0f958f8c259a

[ocp-aws-localzones-step4-ocp-nodes-ec2]: https://github.com/mtulio/mtulio.labs/assets/3216894/be37e2f6-f2cb-44e8-a5b5-c0961a603261

[ocp-aws-localzones-step7-alb-nyc]: https://github.com/mtulio/mtulio.labs/assets/3216894/198527bf-773c-42b7-bcdc-30dc7a5a9aa9

[ocp-aws-localzones-step7-alb-tg-nyc]: https://github.com/mtulio/mtulio.labs/assets/3216894/4129eef8-31cb-4373-822b-ec6b542cbce2

[ocp-aws-localzones-step5-cfn-subnet-bue-1a]: https://github.com/mtulio/mtulio.labs/assets/3216894/6804bd3a-1104-4feb-9fa1-ca36a563e335

[ocp-aws-localzones-step5-ec2-bue-1a]: https://github.com/mtulio/mtulio.labs/assets/3216894/74b19d65-e425-4c0a-8f45-a25e6449da46

[ocp-aws-localzones-step8-aggregated-results]: https://github.com/mtulio/mtulio.labs/assets/3216894/9250fb62-fd99-4c31-9d77-178c82e38cb7

[ocp-aws-localzones-step8-nyc]: https://github.com/mtulio/mtulio.labs/assets/3216894/85c059f3-cfe5-4381-a4b4-fba7cce976d2