# Extending Red Hat OpenShift Container Platform to AWS Local Zones

> Authors: Marcos Entenza Garcia Marco Braga Fatih Nar

## Overview

In Red Hat OpenShift Container Platform 4.12, we introduced the ability to extend cluster formation into Amazon Web Services (AWS) Local Zones in Red Hat OpenShift. In this post, we present how to deploy OpenShift compute nodes in Local Zones at cluster creation time, where the OpenShift Installer creates compute nodes in configured Local Zones. In addition, we share how the cluster administrator adds compute nodes in Local Zones to an existing OpenShift cluster.

Before diving into deploying OpenShift with Local Zones, let's review what Local Zones are.

Local Zones allow you to use select AWS services, like compute and storage services, closer to more end-users, providing them with very low latency access to the applications running locally. Local Zones are fully-owned and managed by AWS with no-upfront commitment and no hardware purchase or lease required. In addition, Local Zones connect to the parent AWS cloud region via AWS' redundant and very high bandwidth private network, providing applications running in Local Zones fast, secure, and seamless access to the rest of AWS services.

![AWS Infrastructure Continuum](https://github.com/mtulio/mtulio.labs/assets/3216894/b4e68d09-bc65-40f4-91aa-1f1cbdea06e6)

<p><center>Figure-1 AWS Infrastructure Continuum</center></p>


Using OpenShift with Local Zones, application developers and service consumers will reap the following benefits:

- Improving application performance and user experience by hosting resources closer to the user, Local Zones reduce the time it takes for data to travel over the network, resulting in faster load times and more responsive applications. This is especially important for applications, such as video streaming or online gaming that require low-latency performance and real-time data access.
- Hosting resources in specific geographic locations leads to cost savings, whereby customers avoid high costs associated with data transfer charges, such as cloud egress charges, which is a significant business expense, when large volumes of data is moved between regions in the case of image, graphics, and video related applications). 
- Provide healthcare, government agencies, financial institutions, and other regulated industries a way to meet data residency requirements by hosting data and applications in specific locations to comply with regulatory laws and mandates.

Let's walk through the steps to install an OpenShift cluster in an existing virtual private cloud (VPC) in the US Virginia (us-east-1) region by creating a Local Zone subnet, OpenShift Machine Set manifests, and automatically launch worker nodes during the installation. This diagram below shows what gets created:

- An standard OpenShift Cluster is installed in us-east-1 with three Control Plane nodes and three Compute nodes
- One "edge" Compute node runs in the Local Zone subnet in the New York metropolitan region
- One Application Load Balancer exposes the sample application running in the Local Zone worker node

![aws-local-zones-diagram-blog-hc drawio](https://github.com/mtulio/mtulio.labs/assets/3216894/06d75201-82dd-4c13-963f-9850e8fc7d34)

<p><center>Figure-2 OpenShift Cluster installed in us-east-1 extending nodes to Local Zone in New York</center></p>


## Installing an OpenShift cluster with AWS Local Zones

To deploy a new OpenShift cluster extending compute nodes in Local Zone subnets, you install a cluster in an existing VPC and create MachineSet manifests for the Installer.

The installation process automatically creates tainted compute nodes with `NoSchedule.` This allows the administrator to choose workloads to run in each remote location, without needing additional steps to isolate the applications.

Once the cluster is installed, the label node-role.kubernetes.io/edge is set for each node located in the Local Zones, along with the regular node-role.kubernetes.io/worker.

Note the following considerations when deploying a cluster in AWS Local Zones:

- The Maximum Transmission Unit (MTU) between an Amazon EC2 instance in a Local Zone and an Amazon EC2 instance in the Region is 1300. This causes the cluster-wide network MTU to change according to the network plugin that is used on the deployment.
- Network resources such as Network Load Balancer (NLB), Classic Load Balancer, and Nat Gateways are not supported in AWS Local Zones.
- The AWS Elastic Block Storage (EBS) gp3 type volume is the default for node volumes and the default for the storage class set on AWS OpenShift clusters. This volume type is not globally available in Local Zone locations. By default, the nodes running in Local Zones are deployed with the gp2 EBS volume. The gp2-csi StorageClass must be set when creating workloads on Local Zone nodes.

Install the following prerequisites before you proceed to the next step:

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [OpenShift Installer 4.12+](https://console.redhat.com/openshift/downloads)
- [OpenShift CLI](https://console.redhat.com/openshift/downloads)

### Step 1.  Create the VPC

This section is optional. Create a VPC with your preferred customizations, as recommended in [Installing a cluster on AWS into an existing VPC](https://docs.openshift.com/container-platform/4.12/installing/installing_aws/installing-aws-vpc.html).
Define the environment variables:

~~~bash
$ export CLUSTER_REGION=us-east-1
$ export CLUSTER_NAME=ocp-lz
~~~

Download the following CloudFormation Templates with the following names:

- template-vpc.yam : [CloudFormation template for the VPC that uses AWS Local Zones](https://docs.openshift.com/container-platform/4.12/installing/installing_aws/installing-aws-localzone.html#installation-cloudformation-vpc-localzone_installing-aws-localzone)
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

> TODO add image VPC Cfn Stack

### Step 2.  Create the public subnet in the AWS Local Zone

Create the subnet on Local Zone (example New York [us-east-1-nyc-1a]), and set the variables used to Local Zones.

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

Enable the Zone Group and create the resources.

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


The network is ready! Now you can set up the OpenShift installer to create a cluster in the existing VPC.
3.  Setup the Install configuration
To create the install configuration, you set the Subnet IDs for all zones in the region excluding Local Zone's subnets.
First, collect the subnet Ids from the CloudFormation templates outputs:

~~~bash
$ mapfile -t SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[0].OutputValue' | tr ',' '\n')

$ mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks \
  --stack-name "${STACK_VPC}" \
  | jq -r '.Stacks[0].Outputs[1].OutputValue' | tr ',' '\n')
~~~


Then, create the install-config.yaml manifest (adapt it according your environment):

~~~bash
$ cat <<EOF > ${PWD}/install-config.yaml
apiVersion: v1
publish: External
baseDomain: "<CHANGE_ME: example.com>"
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

Create the manifests.

~~~bash
$ ./openshift-install create manifests
~~~

Set the maximum transmission unit (MTU) for the cluster network. Local Zones require 1300 MTU to communicate between nodes in Local Zone nodes and Availability Zones. Decrease the overhead of the cluster network plugin as OVN-Kubernetes requires 100 bytes (per our example). Learn more about the MTU at How Local Zones work.

~~~bash
$ cat <<EOF > manifests/cluster-network-03-config.yml
apiVersion: operator.openshift.io/v1
kind: Network
metadata:
  name: cluster
spec:
  defaultNetwork:
    ovnKubernetesConfig:
      mtu: 1200
EOF
~~~

### Step 4.  Create the Machine Set manifest

Finally, set the required variables to create the Machine Sets on the Local Zone subnets:

- Check the available types using: aws ec2 describe-instance-type-offerings [..]

~~~bash
$ export INSTANCE_TYPE="c5d.2xlarge"

# discovery values from manifests created by the Installer:
$ export AMI_ID=$(grep ami openshift/99_openshift-cluster-api_worker-machineset-0.yaml \
  | tail -n1 | awk '{print$2}')

$ export CLUSTER_ID="$(awk '/infrastructureName: / {print $2}' manifests/cluster-infrastructure-02-config.yml)"

# get the Local Zone subnetID
$ export SUBNET_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_LZ}" \
  | jq -r .Stacks[0].Outputs[0].OutputValue)
~~~


- Create the Machine Set.

~~~bash
$ cat <<EOF > openshift/99_openshift-cluster-api_worker-machineset-nyc1.yaml
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
  name: ${CLUSTER_ID}-edge-${ZONE_GROUP_NAME}a
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-edge-${ZONE_GROUP_NAME}a
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: edge
        machine.openshift.io/cluster-api-machine-type: edge
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-edge-${ZONE_GROUP_NAME}a
    spec:
      metadata:
        labels:
          machine.openshift.com/zone-type: local-zone
          machine.openshift.com/zone-group: ${ZONE_GROUP_NAME}
          node-role.kubernetes.io/edge: ""
      taints:
        - key: node-role.kubernetes.io/edge
          effect: NoSchedule
      providerSpec:
        value:
          ami:
            id: ${AMI_ID}
          apiVersion: machine.openshift.io/v1beta1
          blockDevices:
          - ebs:
              volumeSize: 120
              volumeType: gp2
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: ${CLUSTER_ID}-worker-profile
          instanceType: ${INSTANCE_TYPE}
          kind: AWSMachineProviderConfig
          placement:
            availabilityZone: ${ZONE_GROUP_NAME}a
            region: ${CLUSTER_REGION}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - ${CLUSTER_ID}-worker-sg
          subnet:
            id: ${SUBNET_ID}
          publicIp: true
          tags:
          - name: kubernetes.io/cluster/${CLUSTER_ID}
            value: owned
          userDataSecret:
            name: worker-user-data
EOF
~~~

Review the Machine Set manifest file - openshift/99_openshift-cluster-api_worker-machineset-nyc1.yaml -  to be sure it has been populated with your environment correctly


### Step 5.  Create the OpenShift cluster

Create the cluster.

~~~bash
$ ./openshift-install create cluster
~~~

The cluster should now be created. You can check the node object to confirm.

~~~bash
$ export KUBECONFIG=$PWD/auth/kubeconfig
$ oc get nodes -l node-role.kubernetes.io/edge
NAME                                    STATUS   ROLES         AGE   VERSION
ip-10-0-138-99.ec2.internal   Ready    edge,worker   29m   v1.25.4+77bec7a
~~~

You also can check the machine created by the Machine Set:

~~~bash
$ oc get machine  -n openshift-machine-api
NAME                                                              PHASE     TYPE            REGION    ZONE                    AGE
ocp-lz-2nnns-edge-us-east-1-nyc-1a-cw78g   Running   c5d.2xlarge   us-east-1   us-east-1-nyc-1a   93m
(...)
~~~

## How to Extend an existing OpenShift cluster over AWS Local Zones

To extend the compute nodes to Local Zones in an existing OpenShift cluster, be sure the VPC running the cluster has enough CIDR blocks to create the subnet(s) for the desired Local Zone location(s).

Refer to Step 2 in the previous section to extend your existing VPC creating nodes in Local Zones.

Adjust the MTU of the cluster network in existing clusters according to your network plugin per RHOCP4: getting 'TLS handshake timeout' pulling images from AWS Local Zones workers.  

Create the public subnet on Local Zone as described in Step 2 in the previous section.

Next, enable the Zone group. Then, create the Local Zone subnet running the CloudFormation Template. Finally, create the Machine Set manifest, adapting to your existing cluster as per Step 4 in previous section.

~~~bash
cat <<EOF > | oc create -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
(...)
~~~

## Deploy user-workloads in AWS Local Zones

As described in “How to Create an OpenShift cluster with AWS Local Zones at install time” section above, there are a few use cases to run workloads in Local Zones. We demonstrate how to take advantage of Local Zones by deploying a sample application and selecting workers running in Local Zones.

The compute nodes deployed in Local Zones have the following extra labels:

~~~bash
machine.openshift.com/zone-type: local-zone
machine.openshift.com/zone-group: us-east-1-nyc-1
node-role.kubernetes.io/edge: ""
~~~

You must set the proper tolerations to `node-role.kubernetes.io/edge`, selecting the node according to your use case.

This example uses the `machine.openshift.com/zone-group` label to select the Local Zone node(s), creates the following deployment to create a sample application in the network border group of New York (us-east-1-nyc-1):

~~~bash
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
        zoneGroup: ${ZONE_GROUP_NAME}
    spec:
      nodeSelector:
        machine.openshift.com/zone-group: ${ZONE_GROUP_NAME}
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
~~~

When we wrote this blog, Local Zones only supports AWS Application Load Balancer. To expose your application to end users, you create a custom ingress for each location by using the [AWS Application Load Balancer (ALB) Operator](https://docs.openshift.com/container-platform/4.12/networking/aws_load_balancer_operator/understanding-aws-load-balancer-operator.html).

Create the ALB Operator following the steps listed in [Installing the AWS Load Balancer Operator](https://docs.openshift.com/container-platform/4.12/networking/aws_load_balancer_operator/install-aws-load-balancer-operator.html), then [Create the ALB Controller](https://docs.openshift.com/container-platform/4.12/networking/aws_load_balancer_operator/create-instance-aws-load-balancer-controller.html).

Next, create the custom Ingress using Local Zone subnet.

~~~bash
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
    zoneGroup: ${ZONE_GROUP_NAME}
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
~~~

Wait for the Load Balancer to get created.

> TODO add images from AWS Console: Load Balancer, TG

Once created, discover the ALB URL and test it.

~~~bash
$ HOST=$(oc get ingress -n lz-apps ingress-lz-nyc-1 --template='{{(index .status.loadBalancer.ingress 0).hostname}}')

$ curl $HOST
GET / HTTP/1.1
X-Forwarded-For: 179.181.81.124
X-Forwarded-Proto: http
X-Forwarded-Port: 80
Host: k8s-lzapps-ingressl-13226f2551-de.us-east-1.elb.amazonaws.com
X-Amzn-Trace-Id: Root=1-63e18147-1532a244542b04bc75ffd473
User-Agent: curl/7.61.1
Accept: */*
~~~

To benchmark the performance, review the network time to connect between different locations:

~~~bash
# [1] NYC (outside AWS backbone)
$ curl -s http://ip-api.com/json/$(curl -s ifconfig.me) |jq -r '[.city, .countryCode]'
[  "North Bergen",   "US" ]
$ curl -sw "%{time_namelookup}   %{time_connect}     %{time_starttransfer}    %{time_total}\n" -o /dev/null $HOST
0.001452   0.004079     0.008914    0.009830

# [2] Within the Region (master nodes)
$ oc debug node/$(oc get nodes -l node-role.kubernetes.io/master -o jsonpath={'.items[0].metadata.name'}) -- chroot /host /bin/bash -c "\
hostname; \
curl -s http://ip-api.com/json/\$(curl -s ifconfig.me) |jq -r '[.city, .countryCode]';\
curl -sw \"%{time_namelookup}   %{time_connect}     %{time_starttransfer}    %{time_total}\\n\" -o /dev/null $HOST"
ip-10-0-54-118
[ "Ashburn",  "US" ]
0.002068   0.010196     0.019962    0.020985

# [3] London (outside AWS backbone)
$ curl -s http://ip-api.com/json/$(curl -s ifconfig.me) |jq -r '[.city, .countryCode]'
[ "London", "GB" ]
$ curl -sw "%{time_namelookup}   %{time_connect}     %{time_starttransfer}    %{time_total}\n" -o /dev/null $HOST
0.003332   0.099921     0.197535    0.198802

# [4] Brazil
$ curl -s http://ip-api.com/json/$(curl -s ifconfig.me) |jq -r '[.city, .countryCode]'
[ "Florianópolis", "BR" ]
$ curl -sw "%{time_namelookup}   %{time_connect}     %{time_starttransfer}    %{time_total}\n" -o /dev/null $HOST
0.022869   0.187408     0.355456    0.356435
~~~

The total time to connect, in seconds, from the client in NYC (outside AWS) to OpenShift edge node running in Local Zone was more than 2x faster compared with the client running in the regular zones.

| Server / Client | [1]NYC/US | [2]AWS Region/use1 | [3]London/UK | [4]Brazil |
| -- | -- | -- | -- | -- | -- |
| us-east-1-nyc-1a | 0.004079 | 0.010196 | 0.099921 | 0.187408 |


## Summary

OpenShift provides a platform for easy deployment, scaling, and management of containerized applications across the hybrid cloud including AWS. Using OpenShift with AWS Local Zones provides numerous benefits for organizations. It allows for lower latency and improved network performance as Local Zones are physically closer to end users, which enhances the overall user experience and reduces downtime. The combination of OpenShift and AWS Local Zones provides a flexible and scalable solution that enables organizations to modernize their applications and meet the demands of their customers and users; 1) improving application performance and user experience, 2) hosting resources in specific geographic locations reducing overall cost and 3) providing regulated industries with a way to meet data residency requirements.

