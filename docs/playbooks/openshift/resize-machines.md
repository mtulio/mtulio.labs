# Resize Machines

<!--
Dev note: This markdown was created to be rendered using mkdocs-material plugin.
Reference of resources enabled on this page:
- https://squidfunk.github.io/mkdocs-material/reference/content-tabs/
- https://squidfunk.github.io/mkdocs-material/reference/admonitions/
-->

Steps to resize a Machine on OpenShift cluster.

!!! tldr "Important Note"
    - All steps described here will follow the safety way to resize a Machine in OCP 4.x.
    - This is not a official documentation and those steps were tested on versions 4.9 and 4.10.

Overview of steps:

- [Gather cluster information](#gather-cluster-information)
- [Set target Machines to resize](#general-steps-to-resize-each-machine)
- [Set the new size](#set-the-new-machine-size)
- Graceful Power off
- Change Machine size
- Power on
- Patch Machine Object spec

Supported/documented platforms:

- AWS
- Azure

## Gather cluster information

### Check the provider

Make sure you are running the steps for the correct Cloud Provider:

``` shell
oc get infrastructures \
    -o jsonpath='{.items[*].status.platformStatus.type}'
```

!!! info "Example output"

    === "AWS"
        ``` shell
        AWS
        ```

    === "Azure"
        ``` shell
        Azure
        ```

### Check the cluster version

``` shell
oc get clusterversion
```

### Check all the nodes are Ready

Make sure that all group of nodes that will be resized are with the `Status=Ready`.

!!! warning "Theme extension prerequisites"
    All steps described here was done on `master` nodes


``` shell
oc get nodes \
    -l kubernetes.io/os=linux,node-role.kubernetes.io/master=
```

Sample output:

```
NAME                     STATUS   ROLES    AGE     VERSION
mrbaz01-2754r-master-0   Ready    master   5h57m   v1.22.0-rc.0+8719299
mrbaz01-2754r-master-1   Ready    master   5h57m   v1.22.0-rc.0+8719299
mrbaz01-2754r-master-2   Ready    master   5h56m   v1.22.0-rc.0+8719299
```

### Check all the machines are Running

Make sure that all group of nodes that will be resized are with the `Status=Ready`.

Notes:
- Sample steps filtering the group of nodes: `master`

``` shell
oc get machines \
    -n openshift-machine-api \
    -l machine.openshift.io/cluster-api-machine-role=master
```

```
NAME                     PHASE     TYPE              REGION   ZONE   AGE
mrbaz01-2754r-master-0   Running   Standard_D4s_v3   eastus   1      6h1m
mrbaz01-2754r-master-1   Running   Standard_D4s_v3   eastus   3      6h1m
mrbaz01-2754r-master-2   Running   Standard_D4s_v3   eastus   2      6h1m
```

### Gather Machine Information

Gather Cloud provider information from Machine object.

!!! example "Choose the Cloud Provider"

    === "AWS"

        ``` shell
        oc get machines \
            -n openshift-machine-api \
            -l machine.openshift.io/cluster-api-machine-role=master \
            -o json \
            | jq -r '.items[]| (\
                "node_name: " + .status.nodeRef.name,\
                "machine_name: "+ .metadata.name,\
                "instanceId: "+ .status.providerStatus.instanceId,\
                "instanceTypeSpec: "+ .spec.providerSpec.value.instanceType,\
                "instanceTypeMeta: "+ .metadata.labels."machine.openshift.io/instance-type",\
                "")'

        ```

    === "Azure"

        ``` shell
        oc get machines \
            -n openshift-machine-api \
            -l machine.openshift.io/cluster-api-machine-role=master \
            -o json \
            | jq -r '.items[]| (\
                "node_name: " + .status.nodeRef.name,\
                "machine_name: "+ .metadata.name,\
                "instanceId: "+ .status.providerStatus.vmId,\
                "instanceTypeSpec: "+ .spec.providerSpec.value.vmSize,\
                "instanceTypeMeta: "+ .metadata.labels."machine.openshift.io/instance-type",\
                "")'
        ```

!!! info "Sample output"

    === "AWS"

        ``` shell
        N/A
        ```

    === "Azure"

        ``` shell
        node_name: mrbaz01-2754r-master-0
        machine_name: mrbaz01-2754r-master-0
        instanceId: /subscriptions/a-b-c-d-xyz/resourceGroups/mrbaz01-2754r-rg/providers/Microsoft.Compute/virtualMachines/mrbaz01-2754r-master-0
        instanceTypeSpec: Standard_D4s_v3
        instanceTypeMeta: Standard_D4s_v3

        node_name: mrbaz01-2754r-master-1
        machine_name: mrbaz01-2754r-master-1
        instanceId: /subscriptions/a-b-c-d-xyz/resourceGroups/mrbaz01-2754r-rg/providers/Microsoft.Compute/virtualMachines/mrbaz01-2754r-master-1
        instanceTypeSpec: Standard_D4s_v3
        instanceTypeMeta: Standard_D4s_v3

        node_name: mrbaz01-2754r-master-2
        machine_name: mrbaz01-2754r-master-2
        instanceId: /subscriptions/a-b-c-d-xyz/resourceGroups/mrbaz01-2754r-rg/providers/Microsoft.Compute/virtualMachines/mrbaz01-2754r-master-2
        instanceTypeSpec: Standard_D4s_v3
        instanceTypeMeta: Standard_D4s_v3
        ```

## General steps to resize each machine

!!! tip "Tip"
    Repeat the steps bellow for each machine you want to resize

Set the `machine_name` variable value.

!!! warning
    The variable `machine_name` should be set specific for your environment,
    and updated for each machine to resize.


``` shell
machine_name=mrbaz01-2754r-master-0
```

### Set the new Machine size

``` shell
new_machine_type="<cloud_provider_size>"
```

!!! info "Example by Cloud Provider"

    === "AWS"
        To check EC2 compatibility with OCP, please check [this doc](https://docs.openshift.com/container-platform/4.8/installing/installing_aws/installing-aws-vpc.html#installation-supported-aws-machine-types_installing-aws-vpc), then set:
        ``` shell
        new_machine_type="m5.xlarge"
        ```

    === "Azure"
        To check VM size available for specific VM, run:
        ``` shell
        az vm list-vm-resize-options \
            --resource-group ${resource_group} \
            --name ${machine_name} \
            --output table
        ```

        Then set the desired value:
        ``` shell
        new_machine_type="Standard_D8s_v3"
        ``` 

### Collect Machine info

!!! danger "Attention"
    You shouldn't change any step describe below, just run according your environment.

Discovery variable values based on `${machine_name}`

!!! example "Choose the Cloud Provider"

    === "AWS"

        ``` shell
        instanceId=$(oc get machine ${machine_name} -n openshift-machine-api -o jsonpath={.status.providerStatus.instanceId})

        node_name=$(oc get machine ${machine_name} -n openshift-machine-api -o jsonpath={.status.nodeRef.name})
        ```

    === "Azure"

        ``` shell
        resource_group=$(oc get machine ${machine_name} -n openshift-machine-api -o jsonpath={.spec.providerSpec.value.resourceGroup})

        instanceId=${machine_name}

        node_name=$(oc get machine ${machine_name} -n openshift-machine-api -o jsonpath={.status.nodeRef.name})
        ```

- Make sure all varialbes are set:

```bash
echo "[${instanceId}] [${node_name}] ${resource_group:-}"
```

### Graceful Power off

- Cordon the node

``` shell
oc adm cordon ${node_name}
```

- Drain the node

``` shell
oc adm drain ${node_name} --ignore-daemonsets --grace-period=60
```

- Shutdown

``` shell
oc debug node/${node_name} -- chroot /host shutdown -h 1
```

- Wait the node to shutdown

!!! warning "Attention"
    Wait until node is `Status=NotReady`

``` shell
oc get node ${node_name} -w
```

- Wait until the Instance/VM is in stopped state (by Cloud provider)

!!! example "Choose the Cloud Provider"

    === "AWS"

        ``` shell
        while true; do \
            st=$(aws ec2 describe-instance-status \
                --instance-id ${instanceId} \
                | jq -r .InstanceStatuses[0].InstanceState.Name); \
            echo “state=$st”; \
            test $st == "null" && break; \
            test $st == "running" && ( \
                echo "state=$st; sleeping 15s"; \
                sleep 15;\
            ); \
        done
        ```

    === "Azure"

        ``` shell
        while true; do \
            st=$(az vm get-instance-view \
                --resource-group ${resource_group} \
                --name ${machine_name} \
                --output json \
                | jq -e '.instanceView.statuses[] \
                | select( .code | startswith("PowerState") ).code'); \
            echo “state=$st”; \
            test $st == "\"PowerState/stopped\"" && break; \
            test $st == "\"PowerState/running\"" && ( \
                echo "state=$st; sleeping 15s"; \
                sleep 15;\
            ); \
        done
        ```


- Make sure that the node is turned off

!!! example "Choose the Cloud Provider"

    === "AWS"
        
        ``` shell
        aws ec2 describe-instance-status \
            --instance-id ${instanceId}
        ```
        
        Expected result: 
        
        ``` json
        {
            "InstanceStatuses": []
        }
        ```

    === "Azure"

        ``` shell
        az vm get-instance-view \
            --resource-group ${resource_group} \
            --name ${machine_name}  \
            --output table
        ```

        Expected result: 
        ```
        Name                    ResourceGroup     Location    ProvisioningState    PowerState
        ----------------------  ----------------  ----------  -------------------  ------------
        mrbaz01-2754r-master-0  mrbaz01-2754r-rg  eastus      Succeeded            VM stopped
        ```

### Change instance Type

- Change the size

!!! example "Choose the Cloud Provider"

    === "AWS"
        ``` shell
        aws ec2 modify-instance-attribute \
            --instance-id ${instanceId} \
            --instance-type ${new_machine_type}
        ```

    === "Azure"
        ``` shell
        az vm resize \
            --resource-group ${resource_group} \
            --name ${machine_name} \
            --size ${new_machine_type}
        ```

- Check the current [new] size

!!! example "Choose the Cloud Provider"

    === "AWS"
        ``` shell
        aws ec2 describe-instance-attribute \
            --instance-id ${instanceId} \
            --attribute instanceType
        ```

    === "Azure"
        ``` shell
        az vm get-instance-view \
            --resource-group ${resource_group} \
            --name ${machine_name} \
            --output json \
            | jq -r '.hardwareProfile.vmSize'
        ```

### Power on

- Power on the VM

!!! example "Choose the Cloud Provider"

    === "AWS"

        ``` shell
        aws ec2 start-instances \
            --instance-ids ${instanceId}
        ```

    === "Azure"

        ``` shell
        az vm start \
            --resource-group ${resource_group} \
            --name ${machine_name} \
            --output table
        ```

- Wait until the Instance is in running state from Cloud Provider

!!! example "Choose the Cloud Provider"

    === "AWS"

        ``` shell
        while true; do \
            st=$(aws ec2 describe-instance-status \
                --instance-id ${instanceId} \
                | jq -r .InstanceStatuses[0].InstanceState.Name \
            ); \
            echo "state=$st"; \
            test $st == "running" && break; \
            test $st == "null" && ( \
                echo "state=$st; sleeping 15s"; \
                sleep 15;\
            ); \
        done

        ```

    === "Azure"

        ``` shell
        while true; do
            st=$(az vm get-instance-view \
                --resource-group ${resource_group} \
                --name ${machine_name} \
                --output json \
                | jq -e '.instanceView.statuses[] | select( .code | startswith("PowerState") ).code');
            echo "state=$st";
            test $st == "\"PowerState/running\"" && break;
            test $st == "\"PowerState/stopped\"" && ( \
                echo "state=$st; sleeping 15s"; \
                sleep 15;\
            );
        done
        ```

- Wait the node to be in Ready (`STATUS=Ready`)

``` shell
oc get node ${node_name} -w
```

- Wait MAPI to reconcile and update the new machine size (`TYPE`)

``` shell
oc get machine ${machine_name} \
    -n openshift-machine-api
```

!!! info "Sample output"

    === "AWS"
        ``` shell
        NAME                   PHASE     TYPE        REGION      ZONE         AGE
        mrbg3-4glln-master-0   Running   m5.xlarge   us-east-1   us-east-1a   48m
        ```

    === "Azure"
        ``` shell
        NAME                     PHASE     TYPE              REGION   ZONE   AGE
        mrbaz01-2754r-master-0   Running   Standard_D8s_v3   eastus   1      7h8m
        ```

- Make sure that no csr is pending (it shouldn't have any pending)

All certs should be issued and approved, just make sure if there was any issue in that step.

``` shell
oc get csr
```

- Some operators should be degraded, review it:

``` shell
oc get co
```

- Uncordon the node

``` shell
oc adm uncordon ${node_name}
```

- Wait until all operators clear the degraded state

``` shell
oc get co -w
```

- Review the Machine object attributes


!!! example "Choose the Cloud Provider"

    === "AWS"
        ``` shell
        oc get machine ${machine_name} \
            -n openshift-machine-api \
            -o json \
            | jq -r '. | (\
                "node_name: " + .status.nodeRef.name,\
                "machine_name: "+ .metadata.name,\
                "instanceTypeSpec: "+ .spec.providerSpec.value.instanceType,\
                "instanceTypeMeta: "+ .metadata.labels."machine.openshift.io/instance-type",\
                "")'
        ```

    === "Azure"

        ``` shell
        oc get machine ${machine_name} \
            -n openshift-machine-api \
            -o json \
            | jq -r '. | (\
                "node_name: " + .status.nodeRef.name,\
                "machine_name: "+ .metadata.name,\
                "instanceTypeSpec: "+ .spec.providerSpec.value.vmSize,\
                "instanceTypeMeta: "+ .metadata.labels."machine.openshift.io/instance-type",\
                "")'
        ```


### Patch Machine API

Patch Machine Object:

!!! example "Choose the Cloud Provider"

    === "AWS"
        ``` shell
        oc patch machine ${machine_name} \
            -n openshift-machine-api \
            --type=merge \
            -p "{\"spec\":{\"providerSpec\":{\"value\":{\"instanceType\":\"${new_machine_type}\"}}}}"
        ```

    === "Azure"

        ``` shell
        oc patch machine ${machine_name} \
            -n openshift-machine-api \
            --type=merge \
            -p "{\"spec\":{\"providerSpec\":{\"value\":{\"vmSize\":\"${new_machine_type}\"}}}}"
        ```

- Review if the Machine Type was changed:

!!! info "Example output"

    === "AWS"
        ``` shell
        oc get machines ${machine_name} \
            -n openshift-machine-api \
            -o json \
            | jq -r '. | (\
                "node_name: " + .status.nodeRef.name,\
                "machine_name: "+ .metadata.name,\
                "instanceTypeSpec: "+ .spec.providerSpec.value.instanceType,\
                "instanceTypeMeta: "+ .metadata.labels."machine.openshift.io/instance-type",\
                "")'
        ```

        Sample output:
        ```
        node_name: ip-10-0-133-111.ec2.internal
        machine_name: mrbg3-4glln-master-0
        instanceTypeSpec: m5.xlarge
        instanceTypeMeta: m5.xlarge
        ```

    === "Azure"
        ``` shell
        oc get machines ${machine_name} \
            -n openshift-machine-api \
            -o json \
            | jq -r '. | (\
                "node_name: " + .status.nodeRef.name,\
                "machine_name: "+ .metadata.name,\
                "instanceTypeSpec: "+ .spec.providerSpec.value.vmSize,\
                "instanceTypeMeta: "+ .metadata.labels."machine.openshift.io/instance-type",\
                "")'
        ```

        Sample output:
        ```
        node_name: mrbaz01-2754r-master-1
        machine_name: mrbaz01-2754r-master-1
        instanceTypeSpec: Standard_D8s_v3
        instanceTypeMeta: Standard_D8s_v3
        ```


### Check services

- Check all cluster operators

``` shell
oc get co
```

- Review Kube apiservers

``` shell
oc get pod kube-apiserver-${node_name} \
    -n openshift-kube-apiserver
```

- Review etcd cluster

Pods

``` shell
oc get pod etcd-${node_name} \
    -n openshift-etcd
```

!!! info "Example output"
    ```
    NAME                          READY   STATUS    RESTARTS   AGE
    etcd-mrbaz01-2754r-master-1   4/4     Running   4          7h12m
    ```

Members

``` shell
oc exec \
    -n openshift-etcd \
    etcd-${node_name} -- etcdctl member list -w table 2>/dev/null
```

!!! info "Example output"
    ```
    +------------------+---------+------------------------+-----------------------+-----------------------+------------+
    |        ID        | STATUS  |          NAME          |      PEER ADDRS       |     CLIENT ADDRS      | IS LEARNER |
    +------------------+---------+------------------------+-----------------------+-----------------------+------------+
    | 612953730164bdff | started | mrbaz01-2754r-master-2 | https://10.0.0.6:2380 | https://10.0.0.6:2379 |      false |
    | 8bf6319e4243538c | started | mrbaz01-2754r-master-0 | https://10.0.0.7:2380 | https://10.0.0.7:2379 |      false |
    | de0c658dd1ee52b8 | started | mrbaz01-2754r-master-1 | https://10.0.0.8:2380 | https://10.0.0.8:2379 |      false |
    +------------------+---------+------------------------+-----------------------+-----------------------+------------+
    ```

Endpoints healthy (`HEALTH=true`)

``` shell
oc exec \
    -n openshift-etcd \
    etcd-${node_name} -- etcdctl endpoint health -w table 2>/dev/null
```

!!! info "Example output"
    ```
    +-----------------------+--------+-------------+-------+
    |       ENDPOINT        | HEALTH |    TOOK     | ERROR |
    +-----------------------+--------+-------------+-------+
    | https://10.0.0.8:2379 |   true | 16.361971ms |       |
    | https://10.0.0.6:2379 |   true | 16.523072ms |       |
    | https://10.0.0.7:2379 |   true | 15.879969ms |       |
    +-----------------------+--------+-------------+-------+
    ```


### Repeat the steps for each machine

Repeat the section "[General steps to resize each machine](#general-steps-to-resize-each-machine)" for each new machine to resize

##  Review all changes

- Review Nodes

``` shell
oc get nodes \
    -l kubernetes.io/os=linux,node-role.kubernetes.io/master=
```

- Gather current Machine summary

``` shell
oc get machines \
    -n openshift-machine-api \
    -l machine.openshift.io/cluster-api-machine-role=master
```

- Review Machines attributes from all machines


!!! example "Choose the Cloud Provider"

    === "AWS"
        ``` shell
        oc get machines \
            -n openshift-machine-api \
            -l machine.openshift.io/cluster-api-machine-role=master \
            -o json \
            | jq -r '.items[]| (\
                "node_name: " + .status.nodeRef.name,\
                "machine_name: "+ .metadata.name,\
                "instanceTypeSpec: "+ .spec.providerSpec.value.instanceType,\
                "instanceTypeMeta: "+ .metadata.labels."machine.openshift.io/instance-type",\
                "")'
        ```

    === "Azure"

        ``` shell
        oc get machines \
            -n openshift-machine-api \
            -l machine.openshift.io/cluster-api-machine-role=master \
            -o json \
            | jq -r '.items[]| (\
                "node_name: " + .status.nodeRef.name,\
                "machine_name: "+ .metadata.name,\
                "instanceTypeSpec: "+ .spec.providerSpec.value.vmSize,\
                "instanceTypeMeta: "+ .metadata.labels."machine.openshift.io/instance-type",\
                "")'
        ```

## Suggested Next Steps

- Create a [kubectl plugin](https://krew.sigs.k8s.io/plugins/) to handle all the steps covered here
