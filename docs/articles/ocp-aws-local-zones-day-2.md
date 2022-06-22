# Extending OpenShift compute nodes to the edge with AWS Local Zones
<!--METADATA_START

-->

__info__:

> Status: Waiting for review

> [PR to Collab]() : please review it! =]

> [PR Preview]()

> Preview on [Dev.to](https://dev.to/mtulio/extend-the-compute-nodes-of-red-hat-openshift-to-the-aws-local-zones-3ila-temp-slug-3175426?preview=a8f003668e3e7b34397193b446b0445e3aff8fddf94a1ee0a3c029eb42e1993a62806d842901646c28e69af1dd5f2d262ae53de215574fd2cacc6b15)

<!--METADATA_END-->

Let's talk about delivering single-digit millisecond latency applications to end-users on [OpenShift Cloud Platform](https://www.redhat.com/en/technologies/cloud-computing/openshift) clusters using [AWS Local Zones](https://aws.amazon.com/about-aws/global-infrastructure/localzones).

AWS Local Zones were created to locate Cloud Infrastructure closer to the large cities and IT centers, helping businesses to deliver their solutions to end-users faster.

**This is a Day-2 guide** used on OpenShift clusters installed with the support of [machine sets](https://docs.openshift.com/container-platform/4.10/machine_management/creating_machinesets/creating-machineset-aws.html)) to easily extend the compute nodes to the new locations far from the main zones within the region, closer to the end-user where can achieve lower latency.

If the Machines/nodes are not managed by machine sets, you can add new nodes by running [these steps](https://docs.openshift.com/container-platform/4.10/machine_management/user_infra/adding-aws-compute-user-infra.html) - not covered in this post.

As always, you need to design your application architecture to take advantage of that feature without being limited or impacted negatively.

I will walk through the solution example which can rely on user-close infrastructure while describing the steps to enable and create the resources in an OpenShift Cluster installed on AWS, then finally deploy one sample application running in the edge networks, and collect the latency from different locations (users) to different zone groups (parent/main region and Local Zones).


**User Story**

- As a company with hybrid cloud architecture, I would like to process real-time machine learning models in AWS specialized instances closer to my application.
- As a Regional Bakery operating within the eastern US, I want to deliver custom cakes to the city where my customers are, advertising the closest stores with availability and an estimated delivery time.
- As a doctor depending on the telemedicine solutions, I would like to have fast results from the exams to make fast decisions in an emergency. Those kinds of systems demand ML processing with high computing power closer to the end users.

**What you need to know**

Resources available to Local Zones are limited when compared to the parent region. For example, compute instances are very limited in terms of sizes and types, and for ELB only the Application Load Balancer is supported. The price is also not the same: when we look at the compute price of `c5d.2xlarge` in `NYC (New York)` it is 20% more expensive than the parent region, N. Virginia (`us-east-1`).

For that reason, it’s important to make sure that your architecture will take advantage of running close to the users.

To go deeper into the details about the limitations and pricing, check the [Local Zones](https://aws.amazon.com/about-aws/global-infrastructure/localzones/features/) and [EC2 pricing](https://aws.amazon.com/ec2/pricing/on-demand/) page.

## **Reference Architecture**

The demo application used in this article takes advantage of the users' geo-location to deliver the content. Look at the diagram:

![AWS OpenShift architecture on AWS Local Zones](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/7bjy9iixe4i73ivtbm53.png)

## **Requirements and considerations**

_Requirements_:

- [AWS CLI](https://github.com/aws/aws-cli) (used `1.20.52`)
- `jq` (used `1.5`)
- [OpenShift client `oc`]

_Considerations_:

The version of components used in this post:
- OpenShift/Kubernetes cluster: `4.10.10`

## **Extend the VPC to Local Zones subnets**

The first step is to choose the locations you want to use to opt-in on AWS EC2 configuration - it's opt-out by default.

You can use the `describe-availability-zones` to check the location available in the region running your cluster. So let's get started:

Get the region of your OpenShift cluster:

```bash
REGION="$(oc get infrastructure cluster \
    -o jsonpath='{.status.platformStatus.aws.region}')"
```

Check the AZs available in your region:

```bash
aws ec2 describe-availability-zones \
    --filters Name=region-name,Values=${REGION} \
    --query 'AvailabilityZones[].ZoneName' \
    --all-availability-zones
```

Depending on the region, that list can be long. Things you need to know:

- `${REGION}[a-z]` : Availability Zones available in the Region (parent)
- `${REGION}-LID-N[a-z]` : Local Zones available, where `LID-N` is the location identifier, and `[a-z]` is the zone identifier.
- `${REGION}-wl1-LID-wlz-[1-9]` : [Available Wavelength zones](https://aws.amazon.com/wavelength/)

Export the variables related to the Local Zone to create the subnets - in my example `US East (New York and Miami)`:

```bash
AZ_GROUP_NYC="${REGION}-nyc-1"
AZ_GROUP_MIA="${REGION}-mia-1"
AZ_NAME_NYC="${AZ_GROUP_NYC}a"
AZ_NAME_MIA="${AZ_GROUP_MIA}a"
```

Opt-in the location to your AWS Account - if it’s not already enabled:

```bash
aws ec2 modify-availability-zone-group \
    --group-name "${AZ_GROUP_NYC}" \
    --opt-in-status opted-in

aws ec2 modify-availability-zone-group \
    --group-name "${AZ_GROUP_MIA}" \
    --opt-in-status opted-in
```

### **_Steps to Create the Subnet_**

It's necessary to choose the CIDR available on your VPC to create the subnet in the new location. In this case, I am using the following CIDRs:
- New York: 10.0.216.0/24
- Miami: 10.0.217.0/24

Collect the Cluster and VPC information:

```bash
CLUSTER_ID="$(oc get infrastructure cluster \
    -o jsonpath='{.status.infrastructureName}')"

VPC_NAME="${CLUSTER_ID}-vpc"
VPC_ID="$(aws ec2 describe-vpcs \
    --filters Name=tag:Name,Values=${VPC_NAME} \
    --query 'Vpcs[].VpcId' --output text)"
```

Create the functions to generate the subnet request and creation:

```bash
create_subnet_request() {
  AZ_NAME=$1; shift
  SUBNET_CIDR=$1; shift
  SCOPE=$1; shift
  SUBNET_NAME="${CLUSTER_ID}-${SCOPE}-${AZ_NAME}"

  cat <<EOF | envsubst > subnet-${SUBNET_NAME}.json
{
    "TagSpecifications": [
        {
            "ResourceType": "subnet",
            "Tags": [
                {
                    "Key": "Name",
                    "Value": "${SUBNET_NAME}"
                }
            ]
        }
    ],
    "AvailabilityZone": "${AZ_NAME}",
    "VpcId": "${VPC_ID}",
    "CidrBlock": "${SUBNET_CIDR}"
}
EOF
}

create_subnet() {
  AZ_NAME=$1; shift
  SCOPE=$1; shift
  SUBNET_NAME="${CLUSTER_ID}-${SCOPE}-${AZ_NAME}"
  aws ec2 create-subnet \
    --cli-input-json "$(cat subnet-${SUBNET_NAME}.json)" \
    | jq -r '.Subnet.SubnetId'
}
```

Create the CLI request file for each subnet:

```bash
create_subnet_request "${AZ_NAME_NYC}" "10.0.216.0/24" "public"

create_subnet_request "${AZ_NAME_MIA}" "10.0.217.0/24" "public"
```

Review the CLI request:

```bash
ls subnet-*.json
```

Create the subnet:

```bash
SUBNET_ID_NYC_PUB=$(create_subnet "${AZ_NAME_NYC}" "public")
SUBNET_ID_MIA_PUB=$(create_subnet "${AZ_NAME_MIA}" "public")
```

Let's make sure the subnets can map Public IP to nodes:

> Optionally you can set the `ProviderSpec` attribute [`MapPublicIpOnLaunch`](https://docs.aws.amazon.com/sdk-for-go/api/service/ec2/) on the `Machine` spec.

```bash
aws ec2 modify-subnet-attribute --map-public-ip-on-launch  \
  --subnet-id "${SUBNET_ID_NYC_PUB}"

aws ec2 modify-subnet-attribute --map-public-ip-on-launch  \
  --subnet-id "${SUBNET_ID_MIA_PUB}"
```

The next step is to associate the subnet to a route table.

> To simplify the demonstration, only the public subnets were used. Ideally, in production, H.A. environments consider using the private subnets.

Get the route table ID:
```bash
RTB_NAME_PUB="${CLUSTER_ID}-public"
RTB_ID_PUB=$(aws ec2 describe-route-tables \
    --filters Name=tag:Name,Values=${RTB_NAME_PUB} \
    --query 'RouteTables[].RouteTableId' \
    --output text)
```

Associate the subnet to the Route Table using [`aws ec2 associate-route-table`](https://docs.aws.amazon.com/cli/latest/reference/ec2/associate-route-table.html):

```bash
aws ec2 associate-route-table \
    --route-table-id "${RTB_ID_PUB}" \
    --subnet-id "${SUBNET_ID_NYC_PUB}"

aws ec2 associate-route-table \
    --route-table-id "${RTB_ID_PUB}" \
    --subnet-id "${SUBNET_ID_MIA_PUB}"
```

All of the network configurations have been set for the new locations.

### **Choosing the Instance Type**

As I've mentioned, the Compute family and sizes are very limited on Local Zones, you can query the AWS API to check what instance types are available for each location:

```bash
aws ec2 describe-instance-type-offerings \
    --location-type availability-zone \
    --filters Name=location,Values=${AZ_NAME_NYC} \
    --region ${REGION}

aws ec2 describe-instance-type-offerings \
    --location-type availability-zone \
    --filters Name=location,Values=${AZ_NAME_MIA} \
    --region ${REGION}
```

We will use the instance `t3.medium`. Set the `INSTANCE_TYPE` environment variable that will be used to create the `MachineSet`:

```bash
INSTANCE_TYPE="t3.medium"
```

## **Create new Machines in the Local Zone**

This section describes the steps needed to create the `MachineSet` resources, which manage Machines in the recently created zones.

We are setting a Kubernetes node-role label `edge` (`node-role.kubernetes.io/edge=`), and setting the `taints` for those nodes as `NoSchedule` to avoid undesired workloads being deployed on the edge.

If you want to create the `MachineSets` from the existing ones, you can do it by saving it to a file and changing it later (not covered):

```bash
oc get machineset/${CLUSTER_ID}-worker-${REGION}a \
    -n openshift-machine-api \
    -o yaml > ${CLUSTER_ID}-edge-${AZ_NAME_ID}.yaml
```

Preferably, you should create the `MachineSet` using the variables set above with the following:

- Get the `AMI_ID` used on the worker nodes:
```bash
AMI_ID="$(oc get \
    machineset/${CLUSTER_ID}-worker-${REGION}a \
    -n openshift-machine-api \
    -o jsonpath='{.spec.template.spec.providerSpec.value.ami.id}')"
```

- Create the function to render the MachineSet manifest:

> The `MachineSet` manifest can be adapted. It's safe for use according to the running cluster with exported variables on the previous sections

```bash
create_machine_set() {
  AZ_NAME=$1; shift
  SCOPE=$1; shift
  SUBNET_NAME="${CLUSTER_ID}-${SCOPE}-${AZ_NAME}";
  cat <<EOF | envsubst | oc create -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
  name: ${CLUSTER_ID}-edge-${AZ_NAME}
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-edge-${AZ_NAME}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: edge
        machine.openshift.io/cluster-api-machine-type: edge
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-edge-${AZ_NAME}
    spec:
      metadata:
        labels:
          location: local-zone
          zone_group: ${AZ_NAME::-1}
          node-role.kubernetes.io/edge: ""
      taints:
        - key: node-role.kubernetes.io/edge
          effect: NoSchedule
      providerSpec:
        value:
          ami:
            id: ${AMI_ID}
          apiVersion: awsproviderconfig.openshift.io/v1beta1
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
            availabilityZone: ${AZ_NAME}
            region: ${REGION}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - ${CLUSTER_ID}-worker-sg
          subnet:
            filters:
            - name: tag:Name
              values:
              - ${SUBNET_NAME}
          tags:
          - name: kubernetes.io/cluster/${CLUSTER_ID}
            value: owned
          userDataSecret:
            name: worker-user-data
EOF
}
```

- Create the MachineSets for each Location

```bash
create_machine_set "${AZ_NAME_NYC}" "public"
create_machine_set "${AZ_NAME_MIA}" "public"
```

- Wait for the Machine to be created

```bash
oc get machines -n openshift-machine-api -w
```

- Wait for your node to be ready (check the label indicating the new AZ)

```bash
oc get nodes -l location=local-zone -w
```

Alternatively, you can check the nodes created in the zones using this query:

```bash
$ oc get nodes \
  -l location=local-zone -o json \
  | jq -r '.items[] | { "name": .metadata.name, "zone": .metadata.labels["topology.kubernetes.io/zone"] }'
{
  "name": "ip-10-0-216-123.ec2.internal",
  "zone": "us-east-1-nyc-1a"
}
{
  "name": "ip-10-0-217-56.ec2.internal",
  "zone": "us-east-1-mia-1a"
}
```

All set! Your Machines are ready to run your workloads.

## **Setup ALB Operator**

We will use the [Application Load Balancer Operator](https://github.com/openshift/aws-load-balancer-operator) to install the ALB Controller to be able to create ingress using the AWS Application Load Balancer. The installation will be performed from the source code, you can read more options on the project page.

> Note: if you don't want to build from source, or already deployed the ALB Operator, you can jump to the application deployment section.

1. Setup Local Development: https://github.com/openshift/aws-load-balancer-operator#local-development
2. Follow the tutorial to install: https://github.com/openshift/aws-load-balancer-operator/blob/main/docs/tutorial.md

> Quick steps after building the operand and operator container images and exported to your registry:

```bash
# Create the project to place the operator
oc new-project aws-load-balancer-operator

# Create the credentials secret
oc apply -f hack/operator-credentials-request.yaml

# Export the image name to be used
export IMG=quay.io/mrbraga/aws-load-balancer-operator:latest
# Build operator (...)
make deploy

oc get all -n aws-load-balancer-operator
```

3. Create the ALB Controller

```bash
cat <<EOF | envsubst | oc create -f -
apiVersion: networking.olm.openshift.io/v1alpha1
kind: AWSLoadBalancerController
metadata:
  name: cluster
spec:
  subnetTagging: Manual
  ingressClass: cloud
  config:
    replicas: 2
  enabledAddons:
    - AWSShield
    - AWSWAFv2
EOF
```

Done! Make sure the `AWSLoadBalancerController` was created correctly.

```bash
oc get AWSLoadBalancerController cluster -o yaml
```

You should be able to see the `subnetIds` discovered by the operator using the cluster tags, something like this:

```yaml
status:
(...)
  ingressClass: cloud
  subnets:
    internal:
    - subnet-01413cd7efad9178b
    - subnet-022f16980e77cc293
    - subnet-097b0dc75fc4fdc31
    - subnet-0be66875994175dee
    - subnet-0c0294c9de6751616
    subnetTagging: Manual
    tagged:
    - subnet-002c105e0bb598472
    - subnet-026977c5b3fb45435
    - subnet-0479f5a0434d84f85
    - subnet-05a634b3b37197f53
    - subnet-0e3bbcb042149a250
```

## **Deploy the Application**

Now it's time for action! In this section, we will deploy one sample application that extracts the public `clientIp` (from HTTP request headers), and the `serverIp` (discovered when the app is initialized), returning it to the user.

The app is called `geo-app`, feel free to change it by setting these environment variables:

```bash
APP_NS=geo-app
APP_BASE_NAME=geo-app
```

Create the App Namespace:

```bash
cat <<EOF | envsubst | oc create -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${APP_NS}
EOF
```

Create the deployment function:

```bash
create_deployment() {
  LOCATION=$1; shift
  AZ_NAME=$1; shift
  APP_NAME="${APP_BASE_NAME}-${LOCATION}"
  cat <<EOF | envsubst | oc create -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NS}
spec:
  selector:
    matchLabels:
      app: ${APP_NAME}
  replicas: 1
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        zone_group: ${AZ_NAME::-1}
    spec:
      nodeSelector:
        zone_group: ${AZ_NAME::-1}
      tolerations:
      - key: "node-role.kubernetes.io/edge"
        operator: "Equal"
        value: ""
        effect: "NoSchedule"
      containers:
      - image: quay.io/mrbraga/go-geo-app:latest
        imagePullPolicy: Always
        name: ${APP_NAME}
        ports:
        - containerPort: 8000
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NS}
labels:
  zone_group: ${AZ_NAME::-1}
spec:
  ports:
    - port: 80
      targetPort: 8000
      protocol: TCP
  type: NodePort
  selector:
    app: ${APP_NAME}
EOF
}
```

Create the deployment for each instance:

```bash
create_deployment "nyc" "${AZ_NAME_NYC}"
create_deployment "mia" "${AZ_NAME_MIA}"
```

Make sure the applications are running for each location:

- New York Local Zone resources

```bash
oc get pods -n ${APP_NS} -l zone_group=${AZ_GROUP_NYC} -o wide
oc get nodes -l topology.kubernetes.io/zone=${AZ_NAME_NYC}
```

- Miami Local Zone resources

```bash
oc get pods -n ${APP_NS} -l zone_group=${AZ_GROUP_MIA} -o wide
oc get nodes -l topology.kubernetes.io/zone=${AZ_NAME_MIA}
```

Create an ingress' function to set up the edge locations:

```bash
create_ingress() {
  LOCATION=$1; shift
  SUBNET=$1; shift
  APP_NAME=${APP_BASE_NAME}-${LOCATION}
  cat <<EOF | envsubst | oc create -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-lz-${LOCATION}
  namespace: ${APP_NS}
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: instance
    alb.ingress.kubernetes.io/subnets: ${SUBNET}
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
  labels:
    location: ${LOCATION}
spec:
  ingressClassName: cloud
  rules:
    - http:
        paths:
          - path: /
            pathType: Exact
            backend:
              service:
                name: ${APP_NAME}
                port:
                  number: 80

EOF
}
```

Create the ingress' instances for each edge location:

```bash
create_ingress "nyc" "${SUBNET_ID_NYC_PUB}"
create_ingress "mia" "${SUBNET_ID_MIA_PUB}"
```

Finally, let's create an instance of the same application in the default zones within the parent region (`${REGION}`). Let's do it in a single script:

```bash
SUBNETS=(`aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=${CLUSTER_ID}-public-${REGION}a" \
  --query 'Subnets[].SubnetId' \
  --output text`)
SUBNETS+=(`aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=${CLUSTER_ID}-public-${REGION}b" \
  --query 'Subnets[].SubnetId' \
  --output text`)
SUBNETS+=(`aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=${CLUSTER_ID}-public-${REGION}c" \
  --query 'Subnets[].SubnetId' \
  --output text`)
SUBNET=$(echo ${SUBNETS[@]} |tr ' ' ',')

APP_NAME="${APP_BASE_NAME}-main"
ZONE_GROUP="${REGION}"

cat <<EOF | envsubst | oc create -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NS}
spec:
  selector:
    matchLabels:
      app: ${APP_NAME}
  replicas: 1
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        zone_group: ${ZONE_GROUP}
    spec:
      containers:
      - image: quay.io/mrbraga/go-geo-app:latest
        imagePullPolicy: Always
        name: ${APP_NAME}
        ports:
        - containerPort: 8000
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NS}
labels:
  zone_group: ${ZONE_GROUP}
spec:
  ports:
    - port: 80
      targetPort: 8000
      protocol: TCP
  type: NodePort
  selector:
    app: ${APP_NAME}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-main
  namespace: ${APP_NS}
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: instance
    alb.ingress.kubernetes.io/subnets: ${SUBNET}
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
  labels:
    location: ${ZONE_GROUP}
spec:
  ingressClassName: cloud
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${APP_NAME}
                port:
                  number: 80
EOF
```

Wait for the load balancers to be provisioned and the `ADDRESS` is available:

```bash
oc get ingress -n ${APP_NS}
```

Get the Ingress URL for each location:

```bash
APP_URL_MAIN=$(oc get ingress \
  -l location=${REGION} -n ${APP_NS} \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname} ')

APP_URL_NYC=$(oc get ingress \
  -l location=nyc -n ${APP_NS} \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname} ')

APP_URL_MIA=$(oc get ingress \
  -l location=mia -n ${APP_NS} \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname} ')
```

Make sure you can reach both deployments:

```bash
$ curl -s http://${APP_URL_MAIN}/ |jq .serverInfo.address
"3.233.82.41"

$ curl -s http://${APP_URL_MIA}/ |jq .serverInfo.address
"64.187.128.146"

$ curl -s http://${APP_URL_NYC}/ |jq .serverInfo.address
"15.181.162.164"
```

## **Test and Benchmark**

Now it's time to make some measurements with `curl`.

We've run tests from 3 different sources to measure the total time to 3 different targets/zone groups (NYC, MIA, and parent region):
- Client#1's Location: Florianópolis/Brazil
- Client#2's Location: Digital Ocean/NYC3 (New York)
- Client#3's Location: Digital Ocean/SFN (San Francisco)

### Setup curl

Create the file `curl-format-all.txt`:
```bash
cat <<EOF> curl-format-all.txt
  time_namelookup:  %{time_namelookup} Sec\n
      time_connect:  %{time_connect} Sec\n
   time_appconnect:  %{time_appconnect} Sec\n
  time_pretransfer:  %{time_pretransfer} Sec\n
     time_redirect:  %{time_redirect} Sec\n
time_starttransfer:  %{time_starttransfer} Sec\n
                   ----------\n
        time_total:  %{time_total} Sec\n
EOF
```

Create the file `curl-format-table.txt` to return the attributes in a single-line tabulation format:

```bash
cat <<EOF> curl-format-table.txt
%{time_namelookup}   %{time_connect}     %{time_starttransfer}    %{time_total}
EOF
```

Create the functions used to test:

```bash
curl_all() {
  curl -w "@curl-format-all.txt" -o /dev/null -s ${1}
}

curl_table() {
  curl -w "@curl-format-table.txt" -o /dev/null -s ${1}
}
```

Also, create the function to collect data points, it will send 10 requests, one by second:

```bash
curl_batch() {
  echo -e " \tTime\t\t\t    DNS\t       Connect\t   TTFB\t       Total\t  "
  for x in $(seq 1 10) ; do
    echo -ne "$(date)\t   $(curl_table "${1}")\n";
    sleep 1;
  done
}
```

### Testing from (`Client#1`) / Brazil

Client's information:
- IP Address' Geo Location

```bash
$ curl -s ${APP_URL_NYC} |jq .clientInfo.geoIP
{
  "as": "AS18881 TELEFÔNICA BRASIL S.A",
  "city": "Florianópolis",
  "country": "Brazil",
  "countryCode": "BR",
  "isp": "TELEFÔNICA BRASIL S.A",
  "lat": -27.6147,
  "lon": -48.4976,
  "org": "Global Village Telecom",
  "query": "191.x.y.z",
  "region": "SC",
  "regionName": "Santa Catarina",
  "status": "success",
  "timezone": "America/Sao_Paulo",
  "zip": "88000"
}
```
- Distance between Public IP of Client and Server:

> The Server's location is not precise, as the AWS' Public IP is not exactly from the server's location, but the Parent's region. So the IP Address' location is the same between all locations (main region's zone and local zones), impacting the real value of the calculation

```bash
$ curl -s ${APP_URL_NYC} |jq .distance
{
  "kilometers": 7999.167714502702,
  "miles": 4970.452379666934,
  "nauticalMiles": 4316.340846502765
}
```

Summary of latency between Brazilian's client and servers:

```bash
$ curl_all "http://${APP_URL_MAIN}"
  time_namelookup:  0.001797 Sec
      time_connect:  0.166161 Sec
   time_appconnect:  0.000000 Sec
  time_pretransfer:  0.166185 Sec
     time_redirect:  0.000000 Sec
time_starttransfer:  0.335583 Sec
                   ----------
        time_total:  0.335633 Sec

$ curl_all "http://${APP_URL_NYC}"
  time_namelookup:  0.001948 Sec
      time_connect:  0.179021 Sec
   time_appconnect:  0.000000 Sec
  time_pretransfer:  0.179048 Sec
     time_redirect:  0.000000 Sec
time_starttransfer:  0.361730 Sec
                   ----------
        time_total:  0.361774 Sec

$ curl_all "http://${APP_URL_MIA}"
  time_namelookup:  0.001920 Sec
      time_connect:  0.132105 Sec
   time_appconnect:  0.000000 Sec
  time_pretransfer:  0.132164 Sec
     time_redirect:  0.000000 Sec
time_starttransfer:  0.287794 Sec
                   ----------
        time_total:  0.287832 Sec
```

### Testing from (`Client#2`) / NYC

Client's information:
- IP Address' Geo Location

```bash
$ curl -s ${APP_URL_NYC} |jq .clientInfo.geoIP
{
  "as": "AS14061 DigitalOcean, LLC",
  "city": "Clifton",
  "country": "United States",
  "countryCode": "US",
  "isp": "DigitalOcean, LLC",
  "lat": 40.8364,
  "lon": -74.1403,
  "org": "Digital Ocean",
  "query": "138.197.77.73",
  "region": "NJ",
  "regionName": "New Jersey",
  "status": "success",
  "timezone": "America/New_York",
  "zip": "07014"
}
```

- Distance:

```bash
$ curl -s ${APP_URL_NYC} |jq .distance
{
  "kilometers": 348.0206044278185,
  "miles": 216.24997789647117,
  "nauticalMiles": 187.79148080529555
}
```

Summary of latency between NY's client and servers:

```bash
$ curl_all "http://${APP_URL_MAIN}"
  time_namelookup:  0.001305 Sec
      time_connect:  0.009792 Sec
   time_appconnect:  0.000000 Sec
  time_pretransfer:  0.009842 Sec
     time_redirect:  0.000000 Sec
time_starttransfer:  0.022289 Sec
                   ----------
        time_total:  0.022362 Sec

$ curl_all "http://${APP_URL_NYC}"
  time_namelookup:  0.001284 Sec
      time_connect:  0.003788 Sec
   time_appconnect:  0.000000 Sec
  time_pretransfer:  0.003832 Sec
     time_redirect:  0.000000 Sec
time_starttransfer:  0.015924 Sec
                   ----------
        time_total:  0.015983 Sec

$ curl_all "http://${APP_URL_MIA}"
  time_namelookup:  0.001417 Sec
      time_connect:  0.032383 Sec
   time_appconnect:  0.000000 Sec
  time_pretransfer:  0.032434 Sec
     time_redirect:  0.000000 Sec
time_starttransfer:  0.089609 Sec
                   ----------
        time_total:  0.089729 Sec
```

<img src="https://acegif.com/wp-content/uploads/2020/b72nv6/partyparrt-40.gif">

Now we can see the advantage of operating on the edge delivering applications to a client close to the server, some insights from the values above:
- The time to connect to the NYC zone was 3x faster than the parent region, and 10x faster than the location far from the user
- The TTFB (`time_starttransfer`) was also 3 times faster than the parent region
- The total time to deliver close to the user was about 30% faster than the parent region
- The TTFB did not report, but the server can be improved as the backend does some processing when calculating the GeoIP

<img src="https://i.stack.imgur.com/XGlad.gif">

### Testing from (`Client#3`) / California

Client's information:
- IP Address' Geo Location

```bash
$ curl -s ${APP_URL_NYC} |jq .clientInfo.geoIP
{
  "as": "AS14061 DigitalOcean, LLC",
  "city": "Santa Clara",
  "country": "United States",
  "countryCode": "US",
  "isp": "DigitalOcean, LLC",
  "lat": 37.3931,
  "lon": -121.962,
  "org": "DigitalOcean, LLC",
  "query": "143.244.176.204",
  "region": "CA",
  "regionName": "California",
  "status": "success",
  "timezone": "America/Los_Angeles",
  "zip": "95054"
}
```

- Distance:

```bash
$ curl -s ${APP_URL_NYC} |jq .distance
{
  "kilometers": 3850.508486723844,
  "miles": 2392.5950491155672,
  "nauticalMiles": 2077.7295406519584
}
```

Summary of latency between California's client and servers:

```bash
$ curl_all "http://${APP_URL_MAIN}"
  time_namelookup:  0.001552 Sec
      time_connect:  0.072307 Sec
   time_appconnect:  0.000000 Sec
  time_pretransfer:  0.072370 Sec
     time_redirect:  0.000000 Sec
time_starttransfer:  0.146625 Sec
                   ----------
        time_total:  0.146696 Sec

$ curl_all "http://${APP_URL_NYC}"
  time_namelookup:  0.003108 Sec
      time_connect:  0.073105 Sec
   time_appconnect:  0.000000 Sec
  time_pretransfer:  0.073180 Sec
     time_redirect:  0.000000 Sec
time_starttransfer:  0.152823 Sec
                   ----------
        time_total:  0.152941 Sec


$ curl_all "http://${APP_URL_MIA}"
  time_namelookup:  0.001725 Sec
      time_connect:  0.070220 Sec
   time_appconnect:  0.000000 Sec
  time_pretransfer:  0.070274 Sec
     time_redirect:  0.000000 Sec
time_starttransfer:  0.164575 Sec
                   ----------
        time_total:  0.164649 Sec
```

### Benchmark Review

Let's move to the end of this benchmark by collecting more data points to normalize the results from the client and servers described above.

The script below tests each server and should be executed on **each client**:
```bash
run_batch() {
  URL="${1}"; shift
  LOC_SHORT="${1}"; shift
  LOCATION=$(curl -s ${URL} |jq -r ".clientInfo.geoIP | ( .countryCode + \"-\" + .region )")
  FILE_OUT="curl-batch_${LOCATION}-${LOC_SHORT}.txt"
  echo -e "\n ${URL}: " > tee -a ${FILE_OUT}
  curl_batch "${URL}" | tee -a ${FILE_OUT}
}

run_batch "${APP_URL_MAIN}" "main"
run_batch "${APP_URL_NYC}" "nyc"
run_batch "${APP_URL_MIA}" "mia"
```

You can find the raw files [here](https://github.com/mtulio/mtulio.labs/tree/master/labs/go-geo-app/data-benchmark).

Average in milliseconds:

| Client / Server | Main | NYC | MIA |
| -- | -- | -- | -- |
| BR-SC | 342.6579 | 352.2908 | 299.3756 |
| US-NY | 22.2609 | 16.0002 | 92.5647 |
| US-CA | 149.5462 | 152.1854 | 164.0881 |

Percentage comparing the parent region (negative is slower):

| Client / Server | Main | NYC | MIA |
| -- | -- | -- | -- |
| BR-SC | 0.00% | -2.81% | 12.63% |
| US-NY | 0.00% | 28.12% | -315.82% |
| US-CA | 0.00% | -1.76% | -9.72% |

The difference in `ms` compared to the parent region  (negative is slower):

| Client / Server | Main | NYC | MIA |
| -- | -- | -- | -- |
| BR-SC | 0 | -9.6329 | 43.2823 |
| US-NY | 0 | 6.2607 | -70.3038 |
| US-CA | 0 | -2.6392 | -14.5419 |


## **Conclusion**

One of the biggest challenges in delivering solutions is to improve application performance. This includes many layers, one of which is the infrastructure. Having an option to deliver low latency to the end-users with low code efforts is a big advantage in time to market.

There are points to improve, such as the limitation of infrastructure as well as the pricing. At the same time, if the demand grows, more infrastructure can be provisioned and more options, services, and competitors may be made available.

As we can see in the first part of this post, you can extend an existing OpenShift Cluster deployed with IPI to AWS Local Zones without any issues, then use an Application Load Balancer Operator to deliver the applications to the edge located in big cities.

Looking at the results of the benchmark, the improvement in the local zone is slightly higher than in the parent region when the client is close to the former, otherwise, there's no benefit in delivering it as the resources will be more expensive on the edge compared to those in the parent zone.

Anyway, you can see how easy it is now to create modern Kubernetes applications with the current easier access to the edge networks.

Next topics to review:
- Use the [Route53 Geolocation routing policy](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html) to deliver a single endpoint to users. It's not a part of this research to check the precision can cover the distance between the Local Zone and the parent region
- You can take advantage of ephemeral storage available on most instances in Local Zones, so if you are processing files on the board, the disk IO will be extremely faster and the solution cheaper.
- Check the AWS Wavelength, one more opportunity to deliver low latency applications directly from RAN (Radio Access Networks) / 5G devices

If you would like to further explore any topic described here, feel free to leave a comment!

Thanks for reaching the end of this research with me! :)

**References**

- [Red Hat OpenShift IPI Installer on AWS]()
- [AWS Local Zones](https://aws.amazon.com/about-aws/global-infrastructure/localzones/features/)
- [AWS Wavelenght](https://aws.amazon.com/wavelength/)
- [Red Hat OpenShift on Wavelenght](https://cloud.redhat.com/blog/running-an-openshift-worker-node-on-aws-wavelength-for-edge-applications)
