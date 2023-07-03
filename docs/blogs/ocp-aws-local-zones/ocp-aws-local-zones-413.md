# Extending Red Hat OpenShift Container Platform to AWS Local Zones

> Authors: Marcos Entenza Garcia, Marco Braga, Fatih Nar

## Overview

In Red Hat OpenShift Container Platform 4.12, we introduced the ability to extend cluster formation into Amazon Web Services (AWS) Local Zones in Red Hat OpenShift. In this post, we present how to deploy OpenShift compute nodes in Local Zones at cluster creation time, where the OpenShift Installer creates compute nodes in configured Local Zones. In addition, we share how the cluster administrator adds compute nodes in Local Zones to an existing OpenShift cluster.

Before diving into deploying OpenShift with Local Zones, let's review what Local Zones are.

Local Zones allow you to use selected AWS services, like compute and storage services, closer to the metropolitan region, and end-users, than the regular zones, providing them with very low latency access to the applications running locally. Local Zones are fully owned and managed by AWS with no upfront commitment and no hardware purchase or lease required. In addition, Local Zones connect to the parent AWS cloud region via AWS' redundant and very high-bandwidth private network, providing applications running in Local Zones fast, secure, and seamless access to the rest of AWS services.

![AWS Infrastructure Continuum](https://github.com/mtulio/mtulio.labs/assets/3216894/b4e68d09-bc65-40f4-91aa-1f1cbdea06e6)

<p><center>Figure-1 AWS Infrastructure Continuum</center></p>

### Benefits of Local Zones

Using OpenShift with Local Zones, application developers and service consumers will reap the following benefits:

- Improving application performance and user experience by hosting resources closer to the user. Local Zones reduce the time it takes for data to travel over the network, resulting in faster load times and more responsive applications. This is especially important for applications, such as video streaming or online gaming, that require low-latency performance and real-time data access.
- Hosting resources in specific geographic locations leads to cost savings, whereby customers avoid high costs associated with data transfer charges, such as cloud egress charges, which is a significant business expense, when large volumes of data is moved between regions in the case of image, graphics, and video related applications). 
- Providing healthcare, government agencies, financial institutions, and other regulated industries a way to meet data residency requirements by hosting data and applications in specific locations to comply with regulatory laws and mandates.

Let's walk through the steps to install an OpenShift cluster in an existing virtual private cloud (VPC) in the US Virginia (us-east-1) region by creating a Local Zone subnet, OpenShift Machine Set manifests, and automatically launching worker nodes during the installation. The diagram below shows what gets created:

- An standard OpenShift Cluster is installed in us-east-1 with three Control Plane nodes and three Compute nodes
- One "edge" Compute node runs in the Local Zone subnet in the New York metropolitan region
- One Application Load Balancer exposes the sample application running in the Local Zone worker node

![aws-local-zones-diagram-blog-hc drawio](https://github.com/mtulio/mtulio.labs/assets/3216894/06d75201-82dd-4c13-963f-9850e8fc7d34)

<p><center>Figure-2 OpenShift Cluster installed in us-east-1 extending nodes to Local Zone in New York</center></p>

After the cluster is installed, we'll share how to add new Local Zones in Day 2 operations, deploy and expose workloads in Local Zones, evaluating the network connection time from different locations.

![aws-local-zones-diagram-ocp-lz-413-map drawio](https://github.com/mtulio/mtulio.labs/assets/3216894/2fe7ae42-5b1a-4f7c-9e95-f063489eadc6)

<p><center>Figure-3 User Workloads in Local Zones</center></p>


## Installing an OpenShift cluster with AWS Local Zones

To deploy a new OpenShift cluster extending compute nodes in Local Zone subnets, you install a cluster in an existing VPC and create MachineSet manifests for the Installer.

The installation process automatically creates tainted compute nodes with `NoSchedule`. This allows the administrator to choose workloads to run in each remote location, without needing additional steps to isolate the applications.

Once the cluster is installed, the label `node-role.kubernetes.io/edge` is set for each node located in the Local Zones, along with the regular `node-role.kubernetes.io/worker`.

Note the following considerations when deploying a cluster in AWS Local Zones:

- The Maximum Transmission Unit (MTU) between an Amazon EC2 instance in a Local Zone and an Amazon EC2 instance in the Region is 1300. This causes the cluster-wide network MTU to change according to the network plugin that is used on the deployment.
- Network resources such as Network Load Balancer (NLB), Classic Load Balancer, and NAT Gateways are not supported in AWS Local Zones.
- The AWS Elastic Block Storage (EBS) `gp3` type volume is the default for node volumes and the default for the storage class set on AWS OpenShift clusters. This volume type is not globally available in Local Zone locations. By default, the nodes running in Local Zones are deployed with the `gp2` EBS volume. The `gp2-csi` StorageClass must be set when creating workloads on Local Zone nodes.

Install the following prerequisites before you proceed to the next step:

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [OpenShift Installer 4.13+](https://console.redhat.com/openshift/downloads)
- [OpenShift CLI](https://console.redhat.com/openshift/downloads)

### Step 1.  Create the VPC

Create a VPC with your preferred customizations, as recommended in [Installing a cluster on AWS into an existing VPC](https://docs.openshift.com/container-platform/4.13/installing/installing_aws/installing-aws-vpc.html).
Define the environment variables:

~~~bash
$ export CLUSTER_NAME=demo-lz
$ export CLUSTER_BASEDOMAIN="example.com"
$ export AWS_REGION=us-east-1
~~~

Download the following CloudFormation Templates with the following names:

- template-vpc.yaml: [CloudFormation template for the VPC that uses AWS Local Zones](https://docs.openshift.com/container-platform/4.12/installing/installing_aws/installing-aws-localzone.html#installation-cloudformation-vpc-localzone_installing-aws-localzone)
- template-lz.yaml: [CloudFormation template for the subnet that uses AWS Local Zones](https://docs.openshift.com/container-platform/4.12/installing/installing_aws/installing-aws-localzone.html#installation-cloudformation-subnet-localzone_installing-aws-localzone)

Create the VPC with CloudFormation Template:

~~~bash
$ export STACK_VPC=${CLUSTER_NAME}-vpc
$ aws cloudformation create-stack --stack-name ${STACK_VPC} \
     --template-body file://template-vpc.yaml \
     --parameters \
        ParameterKey=ClusterName,ParameterValue=${CLUSTER_NAME} \
        ParameterKey=VpcCidr,ParameterValue="10.0.0.0/16" \
        ParameterKey=AvailabilityZoneCount,ParameterValue=3 \
        ParameterKey=SubnetBits,ParameterValue=12

$ aws cloudformation wait stack-create-complete --stack-name ${STACK_VPC}
$ aws cloudformation describe-stacks --stack-name ${STACK_VPC}
~~~

![ocp-aws-localzones-step1-cfn-vpc](https://github.com/mtulio/mtulio.labs/assets/3216894/08c01da3-416b-4a70-a253-a931086ea978)

<p><center>Figure-4: CloudFormation Stack for VPC</center></p>


### Step 2.  Create the public subnet in the AWS Local Zone

Create the subnet on Local Zone (New York [us-east-1-nyc-1a]), and set the variables used to Local Zones.

~~~bash
$ export STACK_LZ=${CLUSTER_NAME}-lz-nyc-1a
$ export ZONE_GROUP_NAME=${CLUSTER_REGION}-nyc-1

# extract public and private subnetIds from VPC CloudFormation
$ export VPC_ID=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId").OutputValue' )
$ export VPC_RTB_PUB=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_VPC} \
  | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PublicRouteTableId").OutputValue' )
~~~

Enable the Zone Group and create the CloudFormation Stack for Local Zone subnets:

~~~bash
$ aws ec2 modify-availability-zone-group \
    --group-name "${ZONE_GROUP_NAME}" \
    --opt-in-status opted-in

$ aws cloudformation create-stack --stack-name ${STACK_LZ} \
     --template-body file://template-lz.yaml \
     --parameters \
        ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}" \
        ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
        ParameterKey=PublicRouteTableId,ParameterValue="${VPC_RTB_PUB}" \
        ParameterKey=LocalZoneName,ParameterValue="${ZONE_GROUP_NAME}a" \
        ParameterKey=LocalZoneNameShort,ParameterValue="nyc-1a" \
        ParameterKey=PublicSubnetCidr,ParameterValue="10.0.128.0/20"

$ aws cloudformation wait stack-create-complete --stack-name ${STACK_LZ} 

$ aws cloudformation describe-stacks --stack-name ${STACK_LZ}
~~~

![ocp-aws-localzones-step2-cfn-subnet-nyc-1a](https://github.com/mtulio/mtulio.labs/assets/3216894/e6e25f4f-b76d-4214-8639-9a9dc176ad5f)

<p><center>Figure-5: CloudFormation Stack for Local Zone subnet in NYC</center></p>

The network setup is ready! Now you can set up the OpenShift installer to create a cluster in the existing VPC.

![ocp-aws-localzones-step2-subnets](https://github.com/mtulio/mtulio.labs/assets/3216894/7f1ba097-95c6-4022-92a6-9714c52b5928)

<p><center>Figure-6: VPC Subnets</center></p>

### Step 3. Setup the Install configuration

To install OCP in existing subnets, the field `platform.aws.subnets` must be set with the subnets IDs created in the last section.

Running the following commands the variable `SUBNETS` will be populated with the output values of CloudFormation stacks:

- Public and Private subnets:

~~~bash
$ mapfile -t SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[0].OutputValue' | tr ',' '\n')

$ mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[1].OutputValue' | tr ',' '\n')
~~~

- Local Zone subnets:

~~~bash
# Set the SUBNET_ID to be used later
export SUBNET_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_LZ}" \
  | jq -r .Stacks[0].Outputs[0].OutputValue)

# Append the Local Zone subnet to the subnet ID list
SUBNETS+=(${SUBNET_ID})
~~~

Lastly, create the `install-config.yaml` with the subnets:

~~~bash
$ cat <<EOF > ${PWD}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: "${CLUSTER_BASEDOMAIN}"
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${CLUSTER_REGION}
    subnets:
$(for SB in ${SUBNETS[*]}; do echo "    - $SB"; done)
pullSecret: '<CHANGE_ME: pull-secret-content>'
sshKey: |
  '<CHANGE_ME: ssh-keys>'
EOF
~~~

All 7 subnets, including Local Zone, must be defined:

~~~bash
$ grep -A 7 subnets ${PWD}/install-config.yaml
~~~

**Optionally**, check the generated Machineset manifests generated:

> The installer will automatically discover the supported instance type for each Local Zone and create the MachineSet manifests. The Maximum Transmission Unit (MTU) for the cluster network will automatically be adjusted according to the network plugin set on install-config.yaml.

~~~bash
$ ./openshift-install create manifests
$ ls -l manifests/cluster-network-*
$ ls -l openshift/99_openshift-cluster-api_worker-machineset-*
~~~

### Step 4.  Create the OpenShift cluster

Create the cluster:

~~~bash
$ ./openshift-install create cluster
~~~

Check the nodes created in AWS Local Zones, labeled with `node-role.kubernetes.io/edge`:

~~~bash
$ export KUBECONFIG=$PWD/auth/kubeconfig
$ oc get nodes -l node-role.kubernetes.io/edge
NAME                          STATUS   ROLES         AGE     VERSION
ip-10-0-128-81.ec2.internal   Ready    edge,worker   4m46s   v1.26.3+b404935
~~~

You can also check the machine created by Machineset added on install time:

~~~bash
$ oc get machines -l machine.openshift.io/cluster-api-machine-role=edge -n openshift-machine-api
NAME                                        PHASE     TYPE          REGION      ZONE               AGE
demo-lz-knlm2-edge-us-east-1-nyc-1a-f2lzd   Running   c5d.2xlarge   us-east-1   us-east-1-nyc-1a   12m
~~~

![ocp-aws-localzones-step4-ocp-nodes-ec2](https://github.com/mtulio/mtulio.labs/assets/3216894/7d6c9c54-dc6e-41eb-84b4-7288533b7890)

<p><center>Figure-7: OpenShift nodes created by the installer in AWS EC2 Console</center></p>

## Extend an existing OpenShift cluster to new AWS Local Zones

This step describes the Day 2 operations to extend the compute nodes to new Local Zones locations in an existing OpenShift cluster, be sure the VPC running the cluster has enough CIDR blocks to create the subnet(s).

Repeat the [Step 2](#step-2--create-the-public-subnet-in-the-aws-local-zone) to create subnets in Buenos Aires (Argentina) using the zone name `us-east-1-bue-1a`. The location of Buenos Aires was intentionally picked as it currently does not support AWS Application Load Balancers (ALB), used in New York zone (`us-east-1-nyc-1a`).

> Note: if the cluster wasn't installed using IPI with Local Zone subnets, the Maximum Transmit Unit (MTU) for the cluster-wide network must be adjusted before proceeding. See the OpenShift documentation for more information.

![ocp-aws-localzones-step5-cfn-subnet-bue-1a](https://github.com/mtulio/mtulio.labs/assets/3216894/486f4361-d8c3-4810-b5bb-0fd7a6c0fc46)

<p><center>Figure-8: CloudFormation Stack for Local Zone subnet in us-east-1-bue-1a</center></p>

Finally, to create nodes using the new zone, the MachineSet manifest must be added setting the zone attributes. The steps below show how to check the instance offered by the zone, and create the MachineSet manifest based on the existing one in the Local Zone of Buenos Aires(`us-east-1-bue-1a`):


- Check and export the instance type offered by the Zone:

~~~bash
$ aws ec2 describe-instance-type-offerings \
    --location-type availability-zone \
    --filters Name=location,Values=${AWS_REGION}-bue-1a \
    --region ${AWS_REGION} \
    --query 'InstanceTypeOfferings[*].InstanceType' --output text
t3.xlarge   c5.4xlarge
t3.medium   c5.12xlarge
c5.2xlarge  r5.2xlarge  m5.2xlarge
g4dn.2xlarge

$ export INSTANCE_BUE=m5.2xlarge
~~~

- Export existing Machineset manifest and patch to the new location:

~~~bash
# Discover and copy the nyc-1 machineset manifest
$ BASE_MANIFEST=$(oc get machineset -n openshift-machine-api -o jsonpath='{range .items[*].metadata}{.name}{"\n"}{end}' | grep nyc-1)

$ oc get machineset -n openshift-machine-api ${BASE_MANIFEST} -o yaml > machineset-lz-bue-1a.yaml

# replace the subnet ID from NYC to BUE
sed -si "s/${SUBNET_ID}/${SUBNET_ID_BUE}/g" machineset-lz-bue-1a.yaml

# replace the zone reference from NYC to BUE
sed -si "s/nyc-1/bue-1/g" machineset-lz-bue-1a.yaml

# replace the instance type to a new one
current_instance=$(oc get machineset -n openshift-machine-api ${BASE_MANIFEST} -o jsonpath='{.spec.template.spec.providerSpec.value.instanceType}')
sed -si "s/${current_instance}/${INSTANCE_BUE}/g" machineset-lz-bue-1a.yaml

# set the replicas to 0 to create a custom SG before launching the node
sed -si "s/replicas: 1/replicas: 0/g" machineset-lz-bue-1a.yaml
~~~

- Create the Machineset:

~~~bash
$ oc create -f machineset-lz-bue-1a.yaml
~~~

- Considering the limitation of ALB in the zone `us-east-1-bue-1a`, the service running in this node will be reached directly from the internet. A dedicated security group will be created and attached to the node running in that zone:

> Save the `SG_ID_BUE` to set the ingress rules on the next steps

~~~bash
$ INFRA_ID="$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')"
$ SG_NAME_BUE=${INFRA_ID}-lz-ingress-bue-1
$ SG_ID_BUE=$(aws ec2 create-security-group \
    --group-name ${SG_NAME_BUE} \
    --description "${SG_NAME_BUE}" \
    --vpc-id ${VPC_ID} | jq -r .GroupId)
~~~

- Update the Machineset with the new security group:

~~~bash
$ export MCSET_BUE=$(oc get machineset -n openshift-machine-api -o jsonpath='{range .items[*].metadata}{.name}{"\n"}{end}' | grep bue-1)

# Patch the MachineSet manifest adding the new Security Group
$ oc patch machineset ${MCSET_BUE} -n openshift-machine-api --type=merge \
  --patch "{
    \"spec\":{
      \"template\":{
        \"spec\":{
          \"providerSpec\":{
            \"value\": {
              \"securityGroups\":[{
                \"filters\": [{
                  \"name\": \"tag:Name\",
                  \"values\":[\"${INFRA_ID}-worker-sg\",\"${INFRA_ID}-lz-ingress-bue-1\"]
                }] }]}}}}}}"
~~~

- Scale the node and wait for the machine creation

~~~bash
$ oc scale --replicas=1 -n openshift-machine-api $MCSET_BUE
$ oc get machines -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=edge -w
NAME                                        PHASE         TYPE          REGION      ZONE               AGE
demo-lz-knlm2-edge-us-east-1-bue-1a-zd8zs   Provisioned   m5.2xlarge    us-east-1   us-east-1-bue-1a   8m47s
demo-lz-knlm2-edge-us-east-1-nyc-1a-f2lzd   Running       c5d.2xlarge   us-east-1   us-east-1-nyc-1a   55m
(...)
~~~

> It can take some time to finish the provisioning by AWS, make sure the machine is in the Running phase before proceeding.

All done, now the cluster is installed and running into two Local Zones, New York (US) and Buenos Aires (Argentina).

![ocp-aws-localzones-step5-ec2-bue-1a](https://github.com/mtulio/mtulio.labs/assets/3216894/545342e3-8298-41d8-be4a-7542ab4d9e16)

<p><center>Figure-9: OpenShift nodes running in AWS Local Zones in EC2 Console</center></p>

## Deploy workloads in AWS Local Zones

As described in the section ["Installing an OpenShift cluster with AWS Local Zones"](#installing-an-openshift-cluster-with-aws-local-zones), there are a few use cases to run workloads in Local Zones. This post demonstrates how to take advantage of Local Zones by deploying a sample application and selecting workers running in Local Zones.

Three deployments will be created:

- Application running in the Region, ingress traffic using the default router
- Application running in Local Zone NYC (US) ingressing traffic using Application Load Balancer
- Application running in Local Zone Buenos Aires (Argentina) ingressing traffic directly to the node (currently the zone does not support AWS Application Load Balancers)

The `edge` compute nodes deployed in Local Zones have the following extra labels:

~~~yaml
machine.openshift.io/zone-type: local-zone
machine.openshift.io/zone-group: us-east-1-nyc-1
node-role.kubernetes.io/edge: ""
~~~

You must set the tolerations to `node-role.kubernetes.io/edge`, selecting the node according to your use case.

The example below uses the `machine.openshift.io/zone-group` label to select the node(s), and creates the deployment for a sample application in the respective zone's network border group:

- Create the namespace:

~~~bash
export APPS_NAMESPACE="localzone-apps"
oc create namespace ${APPS_NAMESPACE}
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

Lastly, to deploy the application in the nodes running in the Region (regular/Availability Zones), a random node is picked and set it up:

~~~bash
NODE_NAME=$(oc get nodes -l node-role.kubernetes.io/worker='',topology.kubernetes.io/zone=${AWS_REGION}a -o jsonpath='{.items[0].metadata.name}')
oc label node ${NODE_NAME} machine.openshift.io/zone-group=${AWS_REGION}

# App running in a node in the regular zones
create_deployment "${AWS_REGION}" "app-default"
~~~

All set, all applications must be running into different locations:

~~~bash
$ oc get pods -o wide 
NAME                           READY   STATUS    RESTARTS   AGE     IP            NODE                          NOMINATED NODE   READINESS GATES
app-bue-1-689b95f4c4-jf6fb     1/1     Running   0          5m4s    10.131.2.6    ip-10-0-156-17.ec2.internal   <none>           <none>
app-default-857b5dc59f-r8cst   1/1     Running   0          75s     10.130.2.24   ip-10-0-51-38.ec2.internal    <none>           <none>
app-nyc-1-54ffd5c89b-bbhqp     1/1     Running   0          5m31s   10.131.0.6    ip-10-0-128-81.ec2.internal   <none>           <none>

 $ oc get pods --show-labels
NAME                           READY   STATUS    RESTARTS   AGE     LABELS
app-bue-1-689b95f4c4-jf6fb     1/1     Running   0          5m16s   app=app-bue-1,pod-template-hash=689b95f4c4,zoneGroup=us-east-1-bue-1
app-default-857b5dc59f-r8cst   1/1     Running   0          87s     app=app-default,pod-template-hash=857b5dc59f,zoneGroup=us-east-1
app-nyc-1-54ffd5c89b-bbhqp     1/1     Running   0          5m43s   app=app-nyc-1,pod-template-hash=54ffd5c89b,zoneGroup=us-east-1-nyc-1
~~~

## Create Ingress for each application

It's time to create the ingress to route the internet traffic on each location.

When this blog has been written, Local Zones has limited support of AWS Load Balancers, supporting only AWS Application Load Balancer (ALB) with limited locations. To expose your application to end users with ALB, you must create, when supported, a custom ingress for each location by using the [AWS Application Load Balancer (ALB) Operator](https://docs.openshift.com/container-platform/4.12/networking/aws_load_balancer_operator/understanding-aws-load-balancer-operator.html).

In our example, only NYC Local Zone supports ALB and will use it to expose their `NYC`'s app.  A new sharded router will be deployed running in `Buenos Aires` node, ingressing the traffic directly from that location (`us-east-1-bue-1a`).

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

- Export the `APP_HOST_AZ` address for that location:

```bash
APP_HOST_AZ="$(oc get route.route.openshift.io/app-default -o jsonpath='{.status.ingress[0].host}')"
```

### Ingress for NYC (New York) Local Zone app

Create the ALB Operator following the steps listed in [Installing the AWS Load Balancer Operator](https://docs.openshift.com/container-platform/4.12/networking/aws_load_balancer_operator/install-aws-load-balancer-operator.html), then [Create the ALB Controller](https://docs.openshift.com/container-platform/4.12/networking/aws_load_balancer_operator/create-instance-aws-load-balancer-controller.html).

> Make sure the ALB Controllers are running before proceeding

```bash
$ oc get pods -n aws-load-balancer-operator 
NAME                                                             READY   STATUS    RESTARTS   AGE
aws-load-balancer-controller-cluster-567bc99b68-rnkjn            1/1     Running   0          43s
aws-load-balancer-controller-cluster-567bc99b68-s7w4z            1/1     Running   0          43s
aws-load-balancer-operator-controller-manager-7674db45d6-hmswz   2/2     Running   0          90s
```

Create the custom Ingress using only the Local Zone subnet:

> Note: the variable `SUBNET_ID` must be set with the NYC subnet ID

~~~bash
$ cat << EOF | oc create -f -
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
    alb.ingress.kubernetes.io/subnets: ${SUBNET_ID}
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
~~~

Wait for the Load Balancer to get created.

![ocp-aws-localzones-step7-alb-nyc](https://github.com/mtulio/mtulio.labs/assets/3216894/7f4f1b0f-5470-403e-b93d-bdefabd6f1c1)

<p><center>Figure-10: Load Balancer created for the ingress using NYC Local Zone subnet</center></p>

![ocp-aws-localzones-step7-alb-tg-nyc](https://github.com/mtulio/mtulio.labs/assets/3216894/15cd5adb-d7d4-42c3-a1dc-249658667ebd)

<p><center>Figure-11: Target Group added the Local Zone node as a target</center></p>

Once created, discover the load balancer host address and test it.

~~~bash
$ APP_HOST_NYC=$(oc get ingress -n ${APPS_NAMESPACE} ingress-lz-nyc-1 --template='{{(index .status.loadBalancer.ingress 0).hostname}}')

$ curl $APP_HOST_NYC
GET / HTTP/1.1
(...)
~~~

### Ingress for BUE (Buenos Aires) Local Zone app

Create a sharded ingressController running in the `Buenos Aires` node using HostNetwork:

~~~bash
$ cat << EOF | oc create -f -
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
$ cat << EOF | oc create -f -
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

Finally, patch the EC2 Security Group with ingress rules allowing traffic through HTTP(80) and HTTPS(442) used by the new router:

~~~bash
$ aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID_BUE \
    --protocol tcp \
    --port 80 \
    --cidr "0.0.0.0/0"

$ aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID_BUE \
    --protocol tcp \
    --port 443 \
    --cidr "0.0.0.0/0"
~~~

Discover and set the Buenos Aires' ingress address:

~~~bash
$ APP_HOST_BUE="$(oc get route.route.openshift.io/app-bue-1 -o jsonpath='{.status.ingress[0].host}')"

$ IP_HOST_BUE="$(oc get nodes -l topology.kubernetes.io/zone=us-east-1-bue-1a -o json | jq -r '.items[].status.addresses[] | select (.type=="ExternalIP").address')"

$ curl -H "Host: $APP_HOST_BUE" http://$IP_HOST_BUE
~~~

> Note: DNS config: the controller is not adding the DNSes to the public zone for the custom ingress controller. How DNS creates RR automatically for the sharded routers which don't use service LB, but HostNetwork with public IP address on the host interface?

## Benchmark the applications

As commented at the begging of this post, we'll test each application endpoint from different locations on the internet, some are closer to the metropolitan regions located in the Local Zone, so we'll be able to measure the network benefits of using edge compute pools in OpenShift.

We will run simple tests creating a few requests from different clients, extracting the [`curl` variables writing it out](https://curl.se/docs/manpage.html#-w) to the console.

Prepare the script `curl.sh` to test on each location:

~~~bash
$ echo "
#!/usr/bin/env bash
echo \"# Client Location: \"
curl -s http://ip-api.com/json/\$(curl -s ifconfig.me) |jq -r '[.city, .countryCode]'

run_curl() {
  echo -e \"time_namelookup\\t time_connect \\t time_starttransfer \\t time_total\"
  for idx in \$(seq 1 5); do
    curl -sw \"%{time_namelookup} \\t %{time_connect} \\t %{time_starttransfer} \\t\\t %{time_total}\\n\" \
    -o /dev/null -H \"Host: \$1\" \${2:-\$1}
  done
}

echo -e \"\n# Collecting request times to server running in AZs/Regular zones [endpoint ${APP_HOST_AZ}]\"
run_curl ${APP_HOST_AZ}

echo -e \"\n# Collecting request times to server running in Local Zone NYC [endpoint ${APP_HOST_NYC}]\"
run_curl ${APP_HOST_NYC}

echo -e \"\n# Collecting request times to server running in Local Zone BUE [endpoint ${APP_HOST_BUE}]\"
run_curl ${APP_HOST_BUE} ${IP_HOST_BUE}
" > curl.sh
~~~

Copy and run `curl.sh` to the clients:

- Client located in the region of US/New York:

~~~bash
$ bash curl.sh 
# Client Location: 
["North Bergen", "US"]

# Collecting request times to server running in AZs/Regular zones [endpoint app-default-localzone-apps.apps.demo-lz.devcluster.openshift.com]
time_namelookup  time_connect    time_starttransfer      time_total
0.010444         0.018078        0.031563                0.032449
0.012000         0.019141        0.030801                0.031725
0.000777         0.007918        0.019087                0.019860
0.001437         0.008690        0.020179                0.020955
0.005015         0.011915        0.023527                0.024309

# Collecting request times to server running in Local Zone NYC [endpoint k8s-localzon-ingressl-573f917a81-716983909.us-east-1.elb.amazonaws.com]
time_namelookup  time_connect    time_starttransfer      time_total
0.002986         0.005248        0.009702                0.010571
0.001368         0.003183        0.006447                0.007270
0.001100         0.002503        0.005711                0.006586
0.003174         0.004643        0.007955                0.008725
0.003144         0.004601        0.007663                0.008500

# Collecting request times to server running in Local Zone BUE [endpoint app-bue-1.apps-bue1.demo-lz.devcluster.openshift.com]
time_namelookup  time_connect    time_starttransfer      time_total
0.000026         0.141142        0.284566                0.285606
0.000027         0.141474        0.284454                0.285362
0.000025         0.141334        0.284213                0.285045
0.000023         0.141085        0.283620                0.284515
0.000026         0.141586        0.284625                0.285490
~~~

- Client located in the region of UK/London:

~~~bash
$ bash curl.sh
# Client Location: 
["Enfield", "GB"]

# Collecting request times to server running in AZs/Regular zones [endpoint app-default-localzone-apps.apps.demo-lz.devcluster.openshift.com]
time_namelookup  time_connect    time_starttransfer      time_total
0.014856         0.096285        0.181679                0.182629
0.001565         0.079669        0.162386                0.163355
0.001891         0.081879        0.165896                0.166834
0.001465         0.080108        0.163756                0.164491
0.001224         0.081282        0.165828                0.166998

# Collecting request times to server running in Local Zone NYC [endpoint k8s-localzon-ingressl-573f917a81-716983909.us-east-1.elb.amazonaws.com]
time_namelookup  time_connect    time_starttransfer      time_total
0.002339         0.092894        0.184171                0.185058
0.001506         0.085278        0.167627                0.168613
0.001176         0.083452        0.167570                0.168474
0.001483         0.092990        0.186173                0.186859
0.001130         0.083462        0.167462                0.168527

# Collecting request times to server running in Local Zone BUE [endpoint app-bue-1.apps-bue1.demo-lz.devcluster.openshift.com]
time_namelookup  time_connect    time_starttransfer      time_total
0.000046         0.229893        0.462351                0.463439
0.000030         0.233715        0.468338                0.469316
0.000057         0.230159        0.462013                0.463272
0.000041         0.230470        0.462181                0.463116
0.000044         0.228971        0.459642                0.460627
~~~

- Client located in the region of Brazil/South:

~~~bash
$ bash curl.sh
# Client Location: 
["Florianópolis", "BR"]

# Collecting request times to server running in AZs/Regular zones [endpoint app-default-localzone-apps.apps.demo-lz.devcluster.openshift.com]
time_namelookup time_connect time_starttransfer time_total
0.022768        0.172481     0.324897           0.326504
0.024175        0.178215     0.337317           0.338611
0.029904        0.183622     0.338799           0.340016
0.016936        0.172481     0.331656           0.333060
0.023056        0.174012     0.332869           0.333940

# Collecting request times to server running in Local Zone NYC [endpoint k8s-localzon-ingressl-573f917a81-716983909.us-east-1.elb.amazonaws.com]
time_namelookup time_connect time_starttransfer time_total
0.023081        0.182175     0.339818           0.340769
0.022908        0.187502     0.353711           0.354144
0.024140        0.181430     0.342511           0.343637
0.016736        0.175075     0.337191           0.338269
0.017669        0.180589     0.342865           0.343365

# Collecting request times to server running in Local Zone BUE [endpoint app-bue-1.apps-bue1.demo-lz.devcluster.openshift.com]
time_namelookup time_connect time_starttransfer time_total
0.000016        0.044052     0.090594           0.091382
0.000018        0.043565     0.090848           0.091869
0.000015        0.046529     0.092182           0.092997
0.000019        0.043899     0.089382           0.090326
0.000016        0.044163     0.089726           0.090368

~~~

Aggregating the results:

![ocp-aws-localzones-step8-aggregated-results](https://github.com/mtulio/mtulio.labs/assets/3216894/9250fb62-fd99-4c31-9d77-178c82e38cb7)

<p><center>Figure-12: Average connect and total time with slower points based on the baseline (fastest)</center></p>

The total time to connect, in milliseconds, from the client in NYC (outside AWS) to the OpenShift edge node running in Local Zone was ~66% faster than the server running in the regular zones. It's also worth mentioning that there are improvements in clients accessing from different countries, looking at the results from the client in Brazil decreased by more than 100% of the total request time when accessing the Buenos Aires server, instead of going to the Region due to the geographic proximity of those locations.

![ocp-aws-localzones-step8-nyc](https://github.com/mtulio/mtulio.labs/assets/3216894/85c059f3-cfe5-4381-a4b4-fba7cce976d2)

<p><center>Figure-13: Client in NYC getting better experience accessing the NYC Local Zone, than the app in the region</center></p>

## Summary

OpenShift provides a platform for easy deployment, scaling, and management of containerized applications across the hybrid cloud including AWS. Using OpenShift with AWS Local Zones provides numerous benefits for organizations. It allows for lower latency and improved network performance as Local Zones are physically closer to end users, which enhances the overall user experience and reduces downtime. The combination of OpenShift and AWS Local Zones provides a flexible and scalable solution that enables organizations to modernize their applications and meet the demands of their customers and users; 1) improving application performance and user experience, 2) hosting resources in specific geographic locations reducing overall cost and 3) providing regulated industries with a way to meet data residency requirements.


## Categories

- OpenShift 4
- Edge
- AWS
- How-tos
