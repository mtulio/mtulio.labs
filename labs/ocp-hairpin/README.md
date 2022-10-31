# OCP Engineering Labs - Hairpin work around for Kube API Server (KAS)

This is the script to create generic MachineConfig manifest to address the hairpin connection issue on OCP, first implemented on the Azure, GCP and Alibaba on [MCO](https://github.com/openshift/machine-config-operator/blob/master/templates/master/00-master/).

NOTE: this is on PoC/experiment and should not use in production.

## Usage

To create/update/generate the MachineConfig object to be added to the manifest directory for OpenShift installer:

> Make sure to replace the OpenShift Version[1] and the internal URL for OpenShift Kubernetes API[2]:

```bash
./machine-config.sh 4.11.4 https://api-int.mycluster.example.com
```

The file `machine-config.yaml` should be generated on the same directory you ran the script, copy it to the instlaller's manifest directory created by `openshift-install create manifests`.

```bash
cp ./machine-config.yaml /path/to/install-config/manifests/
```

## References:

- [Static pods to redirect hairpin traffic for Azure](https://github.com/openshift/machine-config-operator/blob/master/templates/master/00-master/azure/files/opt-libexec-openshift-azure-routes-sh.yaml)
- [Static pods to redirect hairpin traffic for AlibabaCloud](https://github.com/openshift/machine-config-operator/tree/master/templates/master/00-master/alibabacloud)
