<!-- > KCS 6996487 -->

## Title: RHOCP4: getting 'TLS handshake timeout' pulling images from AWS Local Zones workers

## Issue

- RHOCP installed in AWS with the default cluster network MTU is not pulling images from the internal registry
- TLS handshaking failures when communicating applications running in AWS Local Zone nodes and regular zones.

    ~~~
    Error: authenticating creds for "image-registry.openshift-image-registry.svc:5000": pinging container registry image-registry.openshift-image-registry.svc:5000: Get "https://image-registry.openshift-image-registry.svc:5000/v2/": net/http: TLS handshake timeout
    Trying to pull image-registry.openshift-image-registry.svc:5000/openshift/tools:latest...
    time="2023-02-02T19:03:09Z" level=warning msg="Failed, retrying in 1s ... (1/3). Error: initializing source docker://image-registry.openshift-image-registry.svc:5000/openshift/tools:latest: pinging container registry image-registry.openshift-image-registry.svc:5000: Get \"https://image-registry.openshift-image-registry.svc:5000/v2/\": net/http: TLS handshake timeout"
    (...)
    ~~~

## Environment

* Red Hat OpenShift Container Platform (RHOCP)
  * 4.12+
* Amazon Web Services (AWS) with worker nodes in AWS Local Zone subnets


## Resolution

You must use change the MTU of the cluster network according to the network plugin used.

Generally, the Maximum Transmission Unit (MTU) between an Amazon EC2 instance in a Local Zone and an Amazon EC2 instance in the Region is 1300, when using the network plugin:

- OVN-Kubernetes the cluster network MTU must be 1200
- OpenShift-SDN the cluster network MTU must be 1250

Steps to change the MTU in the existing cluster:

- Note the MTU of the machine network interface

    ~~~sh
    $ oc debug node/$(oc get nodes -o jsonpath='{.items[0].metadata.name}') -- chroot /host /bin/bash -c "ip addr show | egrep '?: ens'  | grep mtu" 2>/dev/null

    2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq master ovs-system state UP group default qlen 1000
    ~~~

- Set the MTU values to be used on the following commands

    ~~~sh
    $ MACHINE_MTU=9001
    $ CLUSTER_MTU_CUR=$(oc get network.config.openshift.io/cluster --output=jsonpath={.status.clusterNetworkMTU})
    $ CLUSTER_MTU_NEW=1200
    ~~~

- Patch the Cluster Network Operator to migrate to the new MTU:

    ~~~sh
    $ oc patch Network.operator.openshift.io cluster --type=merge \
      --patch "{
        \"spec\":{
          \"migration\":{
            \"mtu\":{
              \"network\":{
                \"from\":${CLUSTER_MTU_CUR},
                \"to\":${CLUSTER_MTU_NEW}
              },
              \"machine\":{\"to\":${MACHINE_MTU}}
            }}}}"
    ~~~

- Wait for the configuration rollout, it could take several minutes until applied to all nodes. (UPDATED=True, UPDATING=False, DEGRADED=False)

    ~~~sh
    $ oc get mcp -w
    ~~~

- Remove the migrations setting the new value to the default network configuration:

    ~~~sh
    $ oc patch network.operator.openshift.io/cluster --type=merge \
      --patch "{
        \"spec\":{
          \"migration\":null,
          \"defaultNetwork\":{
            \"ovnKubernetesConfig\":{\"mtu\":${CLUSTER_MTU_NEW}}
            }}}"
    ~~~

- Wait for the configuration rollout, it could take several minutes until applied to all nodes. (UPDATED=True, UPDATING=False, DEGRADED=False)

    ~~~sh
    $ oc get mcp -w
    ~~~

- Check the new MTU value on all overlay network interfaces (example bellow when using OVN-Kubernetes)

    ~~~sh
    $ for NODE_NAME in $(oc get nodes  -o jsonpath='{.items[*].metadata.name}'); do
      echo -e "\n>> check interface $NODE_NAME";
      oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "ip ad show ovn-k8s-mp0 | grep mtu" 2>/dev/null;
    done

    >> check interface ip-10-0-135-51.ec2.internal
    6: ovn-k8s-mp0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1200 qdisc noqueue state UNKNOWN group default qlen 1000

    (...)
    ~~~

- Connect to the Local Zone node and test pulling image from the internal registry:
    - Export the user and password of any user with administrative privileges (cluster-admin)

        ~~~sh
        $ ADMIN_USER=kubeadmin
        $ ADMIN_PASS=$(cat auth/kubeadmin-password)
        ~~~

    - Export the Internal API address and the Local Zone node name

        ~~~sh
        $ API_INT=$(oc get infrastructures cluster -o jsonpath={.status.apiServerInternalURI})
        $ NODE_NAME=$(oc get nodes -l node-role.kubernetes.io/edge -o jsonpath={.items[0].metadata.name})
        ~~~

    - Pull the image successfully:

        ~~~sh
        $ oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "\
        oc login --insecure-skip-tls-verify -u ${ADMIN_USER} -p ${ADMIN_PASS} ${API_INT}; \
        podman login -u ${ADMIN_USER} -p \$(oc whoami -t) image-registry.openshift-image-registry.svc:5000; \
        podman pull image-registry.openshift-image-registry.svc:5000/openshift/tools" 2>/dev/null;

        WARNING: Using insecure TLS client config. Setting this option is not supported!

        Login successful.

        You have access to 67 projects, the list has been suppressed. You can list all projects with 'oc projects'

        Using project "default".
        Login Succeeded!
        Trying to pull image-registry.openshift-image-registry.svc:5000/openshift/tools:latest...
        Getting image source signatures
        Copying blob sha256:b85fd973d4bcf767fe50f50b600e3479e89b49e1f391fdae2de3762cb2cbe418
        Copying blob sha256:d8190195889efb5333eeec18af9b6c82313edd4db62989bd3a357caca4f13f0e
        Copying blob sha256:833de2b0ccff7a77c31b4d2e3f96077b638aada72bfde75b5eddd5903dc11bb7
        Copying blob sha256:97da74cc6d8fa5d1634eb1760fd1da5c6048619c264c23e62d75f3bf6b8ef5c4
        Copying blob sha256:07a17b829f3072d3df76852bc7e1b855755d62a4fbe386d94e162589852db11b
        Copying blob sha256:f0f4937bc70fa7bf9afc1eb58400dbc646c9fd0c9f95cfdbfcdedd55f6fa0bcd
        Copying config sha256:fc2918e42bf489c9c40e9ba6e9df04bfb8ba9600eacd8945e18a5982172c454b
        Writing manifest to image destination
        Storing signatures
        fc2918e42bf489c9c40e9ba6e9df04bfb8ba9600eacd8945e18a5982172c454b
        ~~~


## Root Cause

AWS Local Zones require 1300 MTU to communicate with nodes running in the regular zones (availability zones/region). According to the AWS Documentation[1]:

~~~sh
Generally, the Maximum Transmission Unit (MTU) is as follows:
 - 9001 bytes between Amazon EC2 instances in the same Local Zone.
 - 1500 bytes between internet gateway and a Local Zone.
 - 1468 bytes between AWS Direct Connect and a Local Zone.
 - 1300 bytes between an Amazon EC2 instance in a Local Zone and an Amazon EC2 instance in the Region.
~~~

During installation, the maximum transmission unit (MTU) for the cluster network is detected automatically based on the MTU of the primary network interface of nodes in the cluster.[2]

When the OCP cluster is installed in AWS with nodes in AWS Local Zones using the default MTU on the cluster network, the services running in the Local Zone nodes will not properly communicate with the services hosted in the nodes running in the region, generating failures in services like the internal registry.

[1] https://docs.aws.amazon.com/local-zones/latest/ug/how-local-zones-work.html
[2] https://docs.openshift.com/container-platform/4.12/networking/changing-cluster-network-mtu.html

## Diagnostic Steps

- Check if the `edge` machines are Running

    ~~~sh
    $ oc get machines -n openshift-machine-api
    NAME                                       PHASE     TYPE          REGION      ZONE               AGE
    awslz-sbmz5-edge-us-east-1-nyc-1a-q8x8k    Running   c5d.2xlarge   us-east-1   us-east-1-nyc-1a   85m
    (...)
    ~~~

- Check if the `edge` nodes are Ready

    ~~~sh
    $ oc get nodes -l node-role.kubernetes.io/edge
    NAME                           STATUS   ROLES         AGE   VERSION
    ip-10-0-138-189.ec2.internal   Ready    edge,worker   75m   v1.25.4+77bec7a
    ~~~

- Review the current MTU for machine and cluster network interfaces:

    ~~~sh
    $ for NODE_NAME in $(oc get nodes  -o jsonpath='{.items[*].metadata.name}'); do
      echo -e "\n>> check interface $NODE_NAME";
      oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "ip ad show | egrep '?: (ens|ovn)' | grep mtu" 2>/dev/null;
    done
    ~~~

    - Example of the expected output of MTU on interface Machine/Overlay: 9001/8901

        ~~~sh
        >> check interface ip-10-0-138-189.ec2.internal
        2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq master ovs-system state UP group default qlen 1000
        7: ovn-k8s-mp0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 8901 qdisc noqueue state UNKNOWN group default qlen 1000

        (...)
        ~~~

- On the Local Zone node, check if you can't pull images from the internal registry:

    ~~~sh
    $ ADMIN_USER=kubeadmin
    $ ADMIN_PASS=$(cat auth/kubeadmin-password)

    $ API_INT=$(oc get infrastructures cluster -o jsonpath={.status.apiServerInternalURI})
    $ NODE_NAME=$(oc get nodes -l node-role.kubernetes.io/edge -o jsonpath={.items[0].metadata.name})

    $ oc debug node/${NODE_NAME} --  chroot /host /bin/bash -c "\
    oc login --insecure-skip-tls-verify -u ${ADMIN_USER} -p ${ADMIN_PASS} ${API_INT}; \
    podman login -u ${ADMIN_USER} -p \$(oc whoami -t) image-registry.openshift-image-registry.svc:5000; \
    podman pull image-registry.openshift-image-registry.svc:5000/openshift/tools" 2>/dev/null;
    ~~~

    - Example of the errors when retrieving images from the local registry:

        ~~~text
        Login successful.

        You have access to 67 projects, the list has been suppressed. You can list all projects with 'oc projects'

        Using project "default".
        Error: authenticating creds for "image-registry.openshift-image-registry.svc:5000": pinging container registry image-registry.openshift-image-registry.svc:5000: Get "https://image-registry.openshift-image-registry.svc:5000/v2/": net/http: TLS handshake timeout
        Trying to pull image-registry.openshift-image-registry.svc:5000/openshift/tools:latest...
        time="2023-02-02T19:03:09Z" level=warning msg="Failed, retrying in 1s ... (1/3). Error: initializing source docker://image-registry.openshift-image-registry.svc:5000/openshift/tools:latest: pinging container registry image-registry.openshift-image-registry.svc:5000: Get \"https://image-registry.openshift-image-registry.svc:5000/v2/\": net/http: TLS handshake timeout"
        (time="2023-02-02T19:03:30Z" level=warning msg="Failed, retrying in 1s ... (2/3). Error: initializing source docker://image-registry.openshift-image-registry.svc:5000/openshift/tools:latest: pinging container registry image-registry.openshift-image-registry.svc:5000: Get \"https://image-registry.openshift-image-registry.svc:5000/v2/\": net/http: TLS handshake timeout"
        time="2023-02-02T19:03:51Z" level=warning msg="Failed, retrying in 1s ... (3/3). Error: initializing source docker://image-registry.openshift-image-registry.svc:5000/openshift/tools:latest: pinging container registry image-registry.openshift-image-registry.svc:5000: Get \"https://image-registry.openshift-image-registry.svc:5000/v2/\": net/http: TLS handshake timeout")
        Error: initializing source docker://image-registry.openshift-image-registry.svc:5000/openshift/tools:latest: pinging container registry image-registry.openshift-image-registry.svc:5000: Get "https://image-registry.openshift-image-registry.svc:5000/v2/": net/http: TLS handshake timeout
        ~~~
