#!/bin/bash

#
# Script to generate the MachineConfig
#

set -eau

help() {

    cat << EOF
${0} <OCP_VERSION> <APISERVER_INTERNAL_URL>

Examples:
  ${0} 4.11.4 https://api-int.mycluster.example.com

EOF
}


if [[ "${1:-}" == "" ]]; then
    echo "ERRRO: unable to read the OpenShift version"
    help
    exit 1
fi

if [[ "${2:-}" == "" ]]; then
    echo "ERRRO: unable to read the OpenShift Internal API URL"
    help
    exit 1
fi

OCP_VERSION="${1:-}"; shift
OCP_APISERVER_INTERNAL_URL="${1:-}"; shift

MC_HAIRPIN_FILE="./machine-config.yaml"

# used on envsubst to create the static pod manifest
export MCO_IMAGE=$(oc adm release info "${OCP_VERSION}" --image-for='machine-config-operator')

cat << EOF > ${MC_HAIRPIN_FILE}
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 98-kas-watcher
spec:
  config:
    ignition:
      version: 3.1.0
    systemd:
      units:
      - name: openshift-hairpin-routes.path
        enabled: true
        contents: |
          [Unit]
          Description=Watch for downfile changes
          Before=kubelet.service
          ConditionPathExists=!/etc/ignition-machine-config-encapsulated.json
          [Path]
          PathExistsGlob=/run/cloud-routes/*
          PathChanged=/run/cloud-routes/
          MakeDirectory=true
          [Install]
          RequiredBy=kubelet.service
      - name: openshift-hairpin-routes.service
        enabled: false
        contents: |
          [Unit]
          Description=Work around load balancer hairpin
          [Service]
          Type=simple
          ExecStart=/bin/bash /opt/libexec/openshift-hairpin-routes.sh start
          User=root
          SyslogIdentifier=openshift-hairpin-routes
    storage:
      files:
      - mode: 0644
        path: "/etc/kubernetes/manifests/apiserver-watcher.yaml"
        contents:
          source: data:text/plain;charset=utf-8;base64,$(envsubst < ./openshift-hairpin-apiserver-watcher.yaml | base64 -w0)
      - mode: 0755
        path: "/opt/libexec/openshift-hairpin-routes.sh"
        contents:
          source: data:text/plain;charset=utf-8;base64,$(base64 -w0 < ./openshift-hairpin-routes.sh)
EOF


test -f ${MC_HAIRPIN_FILE} && echo "MachineConfig manifest created at [${MC_HAIRPIN_FILE}]"
