
## Review cluster info

### Check the provider

### Check the cluster version

### Check all the nodes are Ready

### Check all the machines are Running

### Gather Machine Information

## Graceful Power off

## Change instance Type

## Power on

## Check the services


- Wait the node to shutdown

> Wait until node is Status=NotReady

```
oc get node ${nodeName} -w
```

- Wait until the Instance is in stopped state by EC2 API (it can take a few minutes)

=== "AWS"

    ``` shell
    while true; do \
        st=$(aws ec2 describe-instance-status --instance-id $instanceId |jq -r .InstanceStatuses[0].InstanceState.Name); \
        echo “state=$st”; \
        test $st == "null" && break; \
        test $st == "running" && ( echo "state=$st; sleeping 15s"; sleep 15;); \
    done
    ```

=== "Azure"

    ``` shell
     while true; do \
        st=$(az vm get-instance-view \
            --resource-group $resourceGroup \
            --name $machineName \
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

=== "AWS"
    ```shell
    aws ec2 describe-instance-status --instance-id $instanceId
    ```
    
    Expected result: 
    
    ``` shell
    {
        "InstanceStatuses": []
    }
    ```

=== "Azure"

    ```shell
    aws ec2 describe-instance-status --instance-id $instanceId
    ```
    
    Expected result: 
    
    ``` shell
    {
        "InstanceStatuses": []
    }
    ```

## Resize

- Check the current size


- Change the size

=== "AWS"
    Body AWS
    ``` shell
    ToDo
    ```

=== "Azure"
    
    ``` shell
    az vm resize --resource-group $resourceGroup --name $machineName --size Standard_D8s_v3
    ```

- Wait until the Instance is in running state from Cloud Provider

=== "AWS"

    ``` shell
        ToDo
    ```

=== "Azure"

    ``` shell
    while true; do
        st=$(az vm get-instance-view \
            --resource-group $resourceGroup \
            --name $machineName \
            --output json \
            | jq -e '.instanceView.statuses[] | select( .code | startswith("PowerState") ).code');
        echo “state=$st”;
        test $st == "\"PowerState/running\"" && break;
        test $st == "\"PowerState/stopped\"" && ( echo "state=$st; sleeping 15s"; sleep 15;);
    done
    ```

- Wait the node to be in Ready (`STATUS=Ready`)

```shell
oc get node ${nodeName} -w
```

- Get the new machine size

```shell
oc get machines -n openshift-machine-api  $machineName
```

Sample output:
=== "AWS"
    Body AWS

    ``` shell
    open
    ```

=== "Azure"
    Body Azure
    
    ``` shell
    NAME                     PHASE     TYPE              REGION   ZONE   AGE
    mrbaz01-2754r-master-0   Running   Standard_D8s_v3   eastus   1      7h8m
    ```

- Template tab


=== "AWS"
    Body AWS

    ``` shell
    myCodeIsOpen
    ```

=== "Azure"
    Body Azure
    
    ``` shell
    myCodeIsOpen
    ```



#>>>

=== "C"

    ``` c
    #include <stdio.h>

    int main(void) {
      printf("Hello world!\n");
      return 0;
    }
    ```

=== "C++"

    ``` c++
    #include <iostream>

    int main(void) {
      std::cout << "Hello world!" << std::endl;
      return 0;
    }
    ```


## dasgdhashdasjda
dajshdjas



=== "Unordered list"

    * Sed sagittis eleifend rutrum
    * Donec vitae suscipit est
    * Nulla tempor lobortis orci

=== "Ordered list"

    1. Sed sagittis eleifend rutrum
    2. Donec vitae suscipit est
    3. Nulla tempor lobortis orci


## linking

asdad

<!-- 
## last

!!! example

    === "Unordered List"

        _Example_:

        ``` markdown
        * Sed sagittis eleifend rutrum
        * Donec vitae suscipit est
        * Nulla tempor lobortis orci
        ```

        _Result_:

        * Sed sagittis eleifend rutrum
        * Donec vitae suscipit est
        * Nulla tempor lobortis orci

    === "Ordered List"

        _Example_:

        ``` markdown
        1. Sed sagittis eleifend rutrum
        2. Donec vitae suscipit est
        3. Nulla tempor lobortis orci
        ```

        _Result_:

        1. Sed sagittis eleifend rutrum
        2. Donec vitae suscipit est
        3. Nulla tempor lobortis orci -->