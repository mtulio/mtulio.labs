# Lab - Using full spot for compute nodes in OpenShift clusters with Spot.io

> Documentation under development

Steps to setup an OCP on AWS with Spot.io .

## Default installation

Steps:

- Install OCP Cluster
- Export the Kubeconfig
- Export the environment variables for your cluster Name

```bash
export SPOTINST_CLUSTER_IDENTIFIER=mycluster
```

- [Create the Token on Spot.IO](https://console.spotinst.com/spt/settings/tokens/permanent) Console

```bash
export SPOTINST_TOKEN_OPENSHIFT=redacted
```

- Export your [SpotIO Account ID](https://console.spotinst.com/spt/settings/account/general) which will run the Cluster

```bash
export SPOTINST_ACCOUNT=act-xyz
```

- Install the Controller

```bash
curl -fsSL https://spotinst-public.s3.amazonaws.com/integrations/kubernetes/cluster-controller/scripts/init.sh | \
   SPOTINST_TOKEN=${SPOTINST_TOKEN_OPENSHIFT} \
   SPOTINST_ACCOUNT=${SPOTINST_ACCOUNT} \
   SPOTINST_CLUSTER_IDENTIFIER=${SPOTINST_CLUSTER_IDENTIFIER} \
   ENABLE_CSR_APPROVAL=true \
   ENABLE_OCEAN_METRIC_EXPORTER=true \
   bash
```

- Check if the controller is running

```bash
$ oc get pods -n kube-system
NAME                                                      READY   STATUS    RESTARTS   AGE
spot-ocean-metric-exporter-546ccf7648-fbsmv               1/1     Running   0          80s
spotinst-kubernetes-cluster-controller-7567f999fb-mlg9z   1/1     Running   0          86s

```

- Check if the cluster was created

```bash

```

## Custom Ocean Controller installation

> Based on the official documentation: https://docs.spot.io/ocean/tutorials/spot-kubernetes-controller/install-with-kubectl

Steps to install Ocean controller in a custom namespace:

- Export the env vars
```bash
SPOT_NAMESPACE=spot-ocean
SPOT_ACCOUNT_ID=[redacted]
SPOT_CLUSTER_ID=[redacted]
SPOT_TOKEN=[redacted]
```

- Create the base configuration
```bash
cat << EOF > oc create -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${SPOT_NAMESPACE}
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: spotinst-kubernetes-cluster-controller-config
  namespace: ${SPOT_NAMESPACE}
data:
  spotinst.cluster-identifier: ${SPOT_CLUSTER_ID}
  disable-auto-update: "true"
  enable-csr-approval: "true"
---
$ cat ocean-controller/secret.yaml 
apiVersion: v1
kind: Secret
metadata:
  name: spotinst-kubernetes-cluster-controller
  namespace: ${SPOT_NAMESPACE}
type: Opaque
data:
  token: $(echo -n \"${SPOT_TOKEN} | base64 |tr -d '\n'\" )
  account: $(echo -n \"${SPOT_ACCOUNT_ID} | base64 |tr -d '\n'\" )
EOF
```

- Create the resources (deployment, service accounts, roles)

```bash
 curl -s https://s3.amazonaws.com/spotinst-public/integrations/kubernetes/cluster-controller/spotinst-kubernetes-cluster-controller-ga.yaml \
    | sed "s/kube-system/${SPOT_NAMESPACE}/g" \
    | oc create -f -
```

## Create the Ocean cluster

> https://docs.spot.io/api/#operation/OceanAWSClusterCreate

### Create the cluster config based on the MachineSet configuration

> WIP

```json
{
  "cluster": {
    "region": "us-east-1",
    "name": "mrbspot22912",
    "controllerClusterId": "mrbspot22912",
    "autoScaler": {
      "resourceLimits": {
        "maxMemoryGib": 256,
        "maxVCpu": 128
      },
      "down": {
        "maxScaleDownPercentage": 60
      }
    },
    "capacity": {
      "minimum": 0,
      "maximum": 200,
      "target": 0
    },
    "compute": {
      "subnetIds": [
        "subnet-0886c7b1f127e3d26",
        "subnet-095b7b0e97a917d10",
        "subnet-0b492a5d4b065ff93",
        "subnet-0b6e5f66726795180",
        "subnet-0d8b3380ca6043097"
      ],
      "instanceTypes": {
        "whitelist": ["c5.xlarge","c5.2xlarge","c5.large","c5.4xlarge","c5.9xlarge","c5a.xlarge","c5a.large","c5a.8xlarge","c5a.4xlarge","c5a.2xlarge","c5ad.xlarge","c5ad.large","c5ad.8xlarge","c5ad.4xlarge","c5ad.2xlarge","c5d.9xlarge","c5d.xlarge","c5d.large","c5d.2xlarge","c5d.4xlarge","c5n.xlarge","c5n.2xlarge","c5n.9xlarge","c5n.large","c5n.4xlarge","c6a.xlarge","c6a.48xlarge","c6a.2xlarge","c6a.large","c6a.8xlarge","c6a.4xlarge","c6i.2xlarge","c6i.8xlarge","c6i.large","c6i.4xlarge","c6i.xlarge","c6id.xlarge","c6id.4xlarge","c6id.8xlarge","c6id.2xlarge","c6id.large","i3.8xlarge","i3.2xlarge","i3.4xlarge","i3.large","i3.xlarge","i3en.3xlarge","i3en.2xlarge","i3en.large","i3en.6xlarge","i3en.xlarge","i4i.xlarge","i4i.8xlarge","i4i.4xlarge","i4i.large","i4i.2xlarge","m5.large","m5.4xlarge","m5.xlarge","m5.8xlarge","m5.2xlarge","m5a.8xlarge","m5a.xlarge","m5a.large","m5a.2xlarge","m5a.4xlarge","m5ad.8xlarge","m5ad.large","m5ad.2xlarge","m5ad.xlarge","m5ad.4xlarge","m5d.4xlarge","m5d.large","m5d.8xlarge","m5d.2xlarge","m5d.xlarge","m5dn.xlarge","m5dn.large","m5dn.8xlarge","m5dn.4xlarge","m5dn.2xlarge","m5n.xlarge","m5n.large","m5n.8xlarge","m5n.4xlarge","m5n.2xlarge","m5zn.xlarge","m5zn.large","m5zn.6xlarge","m5zn.3xlarge","m5zn.2xlarge","m6a.xlarge","m6a.4xlarge","m6a.2xlarge","m6a.large","m6a.48xlarge","m6a.8xlarge","m6i.4xlarge","m6i.2xlarge","m6i.8xlarge","m6i.xlarge","m6i.large","m6id.xlarge","m6id.large","m6id.8xlarge","m6id.2xlarge","m6id.4xlarge","r5.2xlarge","r5.4xlarge","r5.8xlarge","r5.large","r5.xlarge","r5a.xlarge","r5a.large","r5a.4xlarge","r5a.2xlarge","r5a.8xlarge","r5ad.8xlarge","r5ad.4xlarge","r5ad.xlarge","r5ad.2xlarge","r5ad.large","r5b.xlarge","r5b.large","r5b.8xlarge","r5b.4xlarge","r5b.2xlarge","r5d.2xlarge","r5d.xlarge","r5d.large","r5d.4xlarge","r5d.8xlarge","r5dn.xlarge","r5dn.large","r5dn.8xlarge","r5dn.4xlarge","r5dn.2xlarge","r5n.xlarge","r5n.large","r5n.8xlarge","r5n.4xlarge","r5n.2xlarge","r6a.large","r6a.4xlarge","r6a.8xlarge","r6a.48xlarge","r6a.xlarge","r6a.2xlarge","r6i.8xlarge","r6i.4xlarge","r6i.large","r6i.xlarge","r6i.2xlarge","r6id.xlarge","r6id.8xlarge","r6id.large","r6id.4xlarge","r6id.2xlarge"]
      },
      "launchSpecification": {
        "imageId": "ami-0722eb0819717090f",
        "userData": "${USERDATA}",
        "securityGroupIds": [
          "sg-0390e0cdb2af37898"
        ],
        "iamInstanceProfile": {
          "arn": "arn:aws:iam::[redacted]:instance-profile/mrbspot22912-9cggd-worker-profile"
        },
        "keyPair": "openshift-dev",
        "tags": [
          {
            "tagKey": "Owner",
            "tagValue": "kubernetes.io/cluster/mrbspot22912-g4wtn"
          },
          {
            "tagKey": "kubernetes.io/cluster/mrbspot22912-g4wtn",
            "tagValue": "owned"
          },
          {
            "tagKey": "Name",
            "tagValue": "mrbspot22912-g4wtn-worker-spot"
          }
        ],
        "associatePublicIpAddress": false
      }
    },
    "scheduling": {},
    "strategy": {
      "utilizeReservedInstances": true,
      "fallbackToOd": true,
      "spotPercentage": 100,
      "gracePeriod": 600,
      "drainingTimeout": 60,
      "utilizeCommitments": false
    }
  }
}
```

### Create the Cluster using the API

```
curl -H "Authorization: bearer ${SPOT_TOKEN}"\
    -d ./ocean-cluster-config.json \
    https://api.spotinst.io/ocean/aws/k8s/cluster?accountId=${SPOT_ACCOUNT}
```

https://api.spotinst.io/ocean/aws/k8s/cluster?accountId=${SPOT_ACCOUNT}


curl -H "Authorization: bearer ${SPOT_TOKEN}" "https://api.spotinst.io/ocean/aws/k8s/cluster?accountId=${SPOT_ACCOUNT}"

curl -H "Authorization: bearer ${SPOT_TOKEN}"  "https://api.spotinst.io/ocean/k8s/cluster/o-ad61fbde/controllerHeartbeat?accountId=${SPOT_ACCOUNT}"
