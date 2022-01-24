# OCP Bootstrap | Notes


## HowTos

### OCP - Adding a new platform specific file to bootstrap

- Change the installer

```bash

```

- Test it

```bash
$ rm -rf .local/clusters/tmp/

$ mkdir .local/clusters/tmp/
$ cp .local/clusters/mrbkas_install-config.yaml .local/clusters/tmp/install-config.yaml

$ .local/bin/openshift-install-master-2021011301  --dir .local/clusters/tmp/ create ignition-configs 
INFO Consuming Install Config from target directory 
INFO Ignition-Configs created in: .local/clusters/tmp and .local/clusters/tmp/auth 

$ jq -r '.storage.files[] | select(.path=="/usr/local/bin/report-progress.sh") | .contents.source' .local/clusters/tmp/bootstrap.ign  |sed 's/data\:text\/plain\;charset\=utf\-8;base64,//g' |base64 -d
<custom_script>
```
ALIBABA_CFG_RESOURCE_GROUP_ID=mrbbz92-z9hj7-rg
