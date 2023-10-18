# Extending Red Hat OpenShift Container Platform to AWS Local Zones

> Authors: Marco Braga, Marcos Entenza Garcia, Fatih Nar

OpenShift users have many options when it comes to deploying a Red Hat OpenShift cluster
in AWS. In Red Hat OpenShift Container Platform 4.12, we introduced the manual steps
to extend cluster nodes into Amazon Web Services (AWS) Local Zones when installing in existing VPC.
We are pleased to announce in OpenShift 4.14 the fully IPI (installer-provisioned infrastructure) automation
to extend worker nodes to AWS Local Zones.

## What is AWS Local Zones?

[Local Zones][aws-localzones] allow you to use selected AWS services, like compute and storage services,
closer to the metropolitan region, and end-users, than the regular zones, providing them with very low
latency access to the applications running locally. Local Zones are fully owned and managed by AWS with
no upfront commitment and no hardware purchase or lease required. In addition, Local Zones connect to
the parent AWS cloud region via AWS' redundant and very high-bandwidth private network, providing
applications running in Local Zones fast, secure, and seamless access to the rest of AWS services.

![AWS Infrastructure Continuum][aws-infrastructure-continuum]

<p align="center">Figure 1: AWS Infrastructure Continuum</p>

## OpenShift and AWS Local Zones

Using OpenShift with Local Zones, application developers and service consumers might have the following benefits:

- Improving application performance and user experience by hosting resources closer to the user. Local
  Zones reduce the time it takes for data to travel over the network, resulting in faster load times
  and more responsive applications. This is especially important for applications, such as video streaming
  or online gaming, that requires low-latency performance and real-time data access.
- Saving costs by avoiding data transfer charges when hosting resources in specific geographic locations,
  whereby customers avoid high costs associated with data transfer charges, such as cloud egress charges,
  which is a significant business expense, when large volumes of data are moved between regions in the case
  of image, graphics, and video-related applications.
- Providing to regulated industries, such as healthcare, government agencies, financial institutions, and others,
  a way to meet data residency requirements by hosting data and applications in specific locations to comply with
  regulatory laws and mandates.

## AWS Local Zones limitations in OpenShift

There are a few limitations in the current AWS Local Zones offering that require attention when deploying OpenShift:

- The Maximum Transmission Unit (MTU) between an Amazon EC2 instance in a Local Zone and an Amazon EC2 instance
  in the Region is 1300. This causes the overlay network MTU to change according to the network plugin that is used
  on the deployment.
- Network resources such as Network Load Balancer (NLB), Classic Load Balancer, and Nat Gateways are not globally
  available in AWS Local Zones, so the installer will not deploy those resources automatically.
- The AWS Elastic Block Storage (EBS) volume type `gp3` is the default for node volumes and the storage class set on
  regular AWS OpenShift clusters. This volume type is not globally available in Local Zones locations. By default,
  the nodes running in Local Zones are deployed with the `gp2` EBS volume type, and the `gp2-csi` StorageClass must
  be set when creating workloads into those nodes.

## Installing an OpenShift cluster with AWS Local Zones

This section describes how to deploy OpenShift compute nodes in Local Zones at cluster creation time, where the OpenShift Installer
fully automates the cluster installation including network components in configured Local Zones. 

The following diagram plots the infrastructure components created by the IPI installation with worker nodes in the Local Zone:

- One regular VPC, and subnets on each Availability Zone in the Region.
- One standard OpenShift Cluster in `us-east-1` with three Control Plane nodes, and three Compute nodes.
- Public and private subnets in the Local Zone in the New York metropolitan region (`us-east-1-nyc-1a`).
- One `edge` compute node in the private subnet in the zone `us-east-1-nyc-1a`;

![aws-local-zones-diagram-blog-hc-414-diagram drawio][aws-local-zones-diagram-blog-hc-414-diagram]

<p align="center">Figure 2: OpenShift Cluster installed in us-east-1 extending nodes to Local Zone in New York</p>

To deploy an OpenShift cluster extending compute nodes in Local Zone subnets, it is required to define the `edge` compute pool in the `install-config.yaml` file, not enabled by default.

The installation process creates the network components in the Local Zone classifying those as "Edge Zone", creating MachineSet manifests for each location. See the [OpenShift documentation][ocp-docs-localzone] for more details.

Once the cluster is installed, the label `node-role.kubernetes.io/edge` is set on each node located in the Local Zone, along with the default label `node-role.kubernetes.io/worker`.

### Prerequisites

Install the clients:

- [OpenShift Installer 4.14+](https://console.redhat.com/openshift/downloads)
- [OpenShift CLI](https://console.redhat.com/openshift/downloads)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

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

<p align="center">Figure 3: OpenShift nodes created by the installer in AWS EC2 Console</p>

The cluster is installed and is ready to run workloads in Edge Compute nodes.

The following references share how to enhance OpenShift and Local Zones:

- Day 2 tasks in Local Zones: creating workloads
- Extending existing clusters to AWS Local Zones
- Application Load Balancer Operator

## Benchmarking the application connection time

To validate the network improvement when delivering the application closer to the user,
we expanded the cluster installed in the section "" to create a node in a new Local Zone `us-east-1-bue-1a`.

The tests measure client connectivity to the application endpoint deployed in the cluster from different locations on the internet, some are closer to the metropolitan regions covered by nodes deployed in Local Zones, allowing us to measure the network benefits of using edge compute pools in OpenShift.

The image below shows an overview of the tested environment:

- three clients testing three endpoints
- clients are originating connections from New York (US), London (UK), South Brazil
- application distributed into different locations in the same cluster: Local Zone New York (us-east-1-nyc-1a), Local Zone Buenos Aires (us-east-1-bue-1a), and in the availability zone in the region (us-east-1)

![aws-local-zones-diagram-ocp-lz-413-map drawio][aws-local-zones-diagram-ocp-lz-413-map]

<p align="center">Figure 4: User Workloads in Local Zones</p>

### Environment

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
  <p align="center"> Figure 5: Average connect and total time with slower points based on the baseline (fastest) </p>
</p>

The total time to connect, in milliseconds, from the client in NYC (outside AWS) to the OpenShift edge node running in the Local Zone was ~66% lower than the application running in the regular zones. It's also worth mentioning that there are benefits when clients access from different countries: the results from the client in Brazil decreased by more than 100% of the total request time when accessing the Buenos Aires deployment, instead of going to the Region's app due to the geographic proximity of those locations.

<p align="center">
  <img src="https://github.com/mtulio/mtulio.labs/assets/3216894/85c059f3-cfe5-4381-a4b4-fba7cce976d2" />
  <p align="center"> Figure 6: Client in NYC getting better experience accessing the NYC Local Zone, than the app in the region </p>
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

[aws-local-zones-diagram-ocp-lz-413-map]: https://user-images.githubusercontent.com/3216894/273260316-1ca7391a-69b0-46c4-ae85-507b9cf6c201.png

[aws-local-zones-diagram-blog-hc-414-diagram]: https://github.com/mtulio/mtulio.labs/assets/3216894/1580de72-4383-4f2f-a715-2268bcface7b

[ocp-aws-localzones-step4-ocp-nodes-ec2]: https://github.com/mtulio/mtulio.labs/assets/3216894/be37e2f6-f2cb-44e8-a5b5-c0961a603261

[ocp-aws-localzones-step7-alb-nyc]: https://github.com/mtulio/mtulio.labs/assets/3216894/198527bf-773c-42b7-bcdc-30dc7a5a9aa9

[ocp-aws-localzones-step7-alb-tg-nyc]: https://github.com/mtulio/mtulio.labs/assets/3216894/4129eef8-31cb-4373-822b-ec6b542cbce2

[ocp-aws-localzones-step5-cfn-subnet-bue-1a]: https://github.com/mtulio/mtulio.labs/assets/3216894/6804bd3a-1104-4feb-9fa1-ca36a563e335

[ocp-aws-localzones-step5-ec2-bue-1a]: https://github.com/mtulio/mtulio.labs/assets/3216894/74b19d65-e425-4c0a-8f45-a25e6449da46

[ocp-aws-localzones-step8-aggregated-results]: https://github.com/mtulio/mtulio.labs/assets/3216894/9250fb62-fd99-4c31-9d77-178c82e38cb7

[ocp-aws-localzones-step8-nyc]: https://github.com/mtulio/mtulio.labs/assets/3216894/85c059f3-cfe5-4381-a4b4-fba7cce976d2