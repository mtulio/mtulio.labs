
# Run locally steps to destroy a cluster created by CI
# Prereq: setup okd-installer environment; setup OCI credentials

#CI_ARTIFACT_URL="https://gcsweb-ci.apps.ci.l2s4.p1.openshiftapps.com/gcs/origin-ci-test/pr-logs/pull/openshift_release/40390/rehearse-40390-periodic-ci-redhat-openshift-ecosystem-provider-certification-tool-main-4.13-platform-external-oci/1670813208698425344/artifacts/platform-external-oci/opct-upi-provision/artifacts/"

CI_ARTIFACT_URL="$1"
CI_CLUSTER_DIR=/tmp/okd-installer/clusters/oci-ci/
mkdir -p /tmp/okd-installer/clusters/oci-ci/

wget $CI_ARTIFACT_URL/cluster-vars-file.yaml -O $CI_CLUSTER_DIR/cluster-vars-file.yaml
wget $CI_ARTIFACT_URL/cluster_state.json -O $CI_CLUSTER_DIR/cluster_state.json

ansible-playbook mtulio.okd_installer.destroy_cluster  -e @$CI_CLUSTER_DIR/cluster-vars-file.yaml -vvv
