# OCP on Azure | Experiment | Explore Cloud permissions requested and required

> TBD/TODO/WIP. PTAL at [original document for AWS](./ocp-perms-track-aws-cloudtrail.md) to track goals.

## Prerequisites

> TBD

## Steps

### Draft | Azure notes

Go to Azure Console and enable Activity logs to an storage account:
- Go to [Activity Logs on Azure Monitor](https://portal.azure.com/#view/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/~/activityLog)
- Click on [Export Activity Log]
- Select "Add diagnostic settings"
- Type the name of archive in "Diagnostic setting name"
- Mark the boxes "Category" "Administrative"
- Mark the box "Archive to a storage account"
- Select the "Subscription" and the "Storage Account" used to archive
- Click on Save
- Go to the AWS Storage acccount and check if it is saving the data


Install a cluter


```sh

CLUSTER_NAME_AZ=lab-azmon
AZURE_BASE_RG=os4-common
AZURE_DOMAIN=splat.azure.devcluster.openshift.com
INSTALL_DIR=${PWD}/$CLUSTER_NAME_AZ
mkdir $INSTALL_DIR

cat << EOF > ${INSTALL_DIR}/install-config.yaml 
apiVersion: v1
metadata:
  name: $CLUSTER_NAME_AZ
featureSet: CustomNoUpgrade
featureGates:
- ClusterAPIInstall=true
publish: External
pullSecret: '$(cat $PULL_SECRET_FILE)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
baseDomain: $AZURE_DOMAIN
platform:
  azure:
    baseDomainResourceGroupName: $AZURE_BASE_RG
    cloudName: AzurePublicCloud
    outboundType: Loadbalancer
    region: eastus
EOF
./openshift-install create cluster --dir "${INSTALL_DIR}"
```

Extract credential requests from payload

```sh
oc adm release extract \
    --credentials-requests \
    --cloud=azure \
    --to=$PWD/credrequests-azure \
    --from=${RELEASE}
```

Extract credentials in-cluster:

```sh
credDir=$PWD/azure-credentials
mkdir $credDir
for creq in $PWD/credrequests-azure/*.yaml;
do
    echo $creq
    secretName=$(yq ea .spec.secretRef.name $creq)
    secretNS=$(yq ea .spec.secretRef.namespace $creq)
    oc get secret -o yaml -n $secretNS $secretName > $credDir/${secretNS}-${secretNS}.yaml
done
```


## Copy the data post install (Console)

- Go to the Storage Account
- Navigate to the container
- Download the file
- Rename it to identify post-install, such as `azure-events-install`

```sh
# Create the local directory if it doesn't exist
mkdir -p azure-events-install

# Download the entire container to the local directory
az storage blob download-batch --account-name mrbragaapicalllogs2 --source insights-activity-logs --destination azure-events-install --auth-mode login
```

## Run e2e on azure

```sh
export CLUSTER_AZURE_AUTH=$PWD/azure-cluster-ServicePrincipal.json
creds_file=$PWD/azure-cluster-creds.json
oc get secret/azure-credentials -n kube-system -o jsonpath='{.data}' > $creds_file
cat <<EOF > ${CLUSTER_AZURE_AUTH}
{
  "subscriptionId": "$(jq -r .azure_subscription_id $creds_file | base64 -d)",
  "clientId": "$(jq -r .azure_client_id $creds_file | base64 -d)",
  "clientSecret": "$(jq -r .azure_client_secret $creds_file | base64 -d)",
  "tenantId": "$(jq -r .azure_tenant_id $creds_file | base64 -d)"
}
EOF
export TEST_PROVIDER=azure
unset TEST_ARGS
export TEST_SUITE="openshift/conformance"
export ARTIFACT_DIR=${PWD}/azure-e2e
mkdir ${ARTIFACT_DIR}

AZURE_AUTH_LOCATION=${CLUSTER_AZURE_AUTH} openshift-tests run "${TEST_SUITE}" ${TEST_ARGS:-} \
        --provider "${TEST_PROVIDER}" \
        -o "${ARTIFACT_DIR}/e2e.log" \
        --junit-dir "${ARTIFACT_DIR}/junit"
```

Synchronize logs after e2e:

```sh
# Create the local directory if it doesn't exist
mkdir -p azure-events-e2e

# Download the entire container to the local directory
az storage blob download-batch --account-name mrbragaapicalllogs2 --source insights-activity-logs --destination azure-events-e2e 
```


### Destroy the cluster

- Call the installer to destroy and synhcronize logs:

```sh
./openshift-install destroy cluster --dir "${INSTALL_DIR}"

# sleep until events propagate
sleep 1200

# Create the local directory if it doesn't exist
mkdir -p azure-events-destroy

# Download the entire container to the local directory
az storage blob download-batch --account-name mrbragaapicalllogs2 --source insights-activity-logs --destination azure-events-destroy
```

### Extract information from events

```sh
# TODO single call to parse everything
./cci --provider azure --cluster-name $CLUSTER_NAME_AZ \
    --events-dir events-cluster-destroy/ \
    --credentials-request-dir $PWD/azure-credrequests \
    --output-prefix azure-events \
    --remove-event-pattern mrbragaapicalllogs2
```
