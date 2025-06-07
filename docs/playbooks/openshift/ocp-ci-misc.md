# OpenShift CI Misc

## Gathere JOB_SPEC information

### Getting data from a PR

Run for presubmit in installer PR:

```sh
JOB_URL="https://prow.ci.openshift.org/view/gs/origin-ci-test/pr-logs/pull/openshift_installer/7722/pull-ci-openshift-installer-master-e2e-aws-ovn-shared-vpc-localzones/1724863721794179072"

ARTIFACTS_URL=$(curl -Ls $JOB_URL | grep '>Artifacts' | awk -F '=' '{print$2}' | awk -F'"' '{print$2}')
COMMIT=$(curl -Ls $ARTIFACTS_URL/podinfo.json | jq -r '.pod.spec.initContainers[] | select(.name=="initupload").env[] | select(.name=="JOB_SPEC").value' | jq -r '.refs.pulls[0].sha // null')

curl -s https://raw.githubusercontent.com/openshift/installer/${COMMIT}/upi/aws/cloudformation/01_vpc.yaml | less
```

Run for payload job triggered in the installer PR:

```sh
JOB_URL=https://prow.ci.openshift.org/view/gs/origin-ci-test/logs/openshift-installer-7722-nightly-4.15-e2e-aws-ovn-shared-vpc-localzones/1724544273619095552

ARTIFACTS_URL=$(curl -Ls $JOB_URL | grep '>Artifacts' | awk -F '=' '{print$2}' | awk -F'"' '{print$2}')
COMMIT=$(basename $(curl -Ls $ARTIFACTS_URL/podinfo.json | jq -r '.pod.spec.initContainers[] | select(.name=="initupload").env[] | select(.name=="JOB_SPEC").value' | jq -r '.extra_refs[0].pulls[0].sha // null' || true))

curl https://raw.githubusercontent.com/openshift/installer/${COMMIT}/upi/aws/cloudformation/01_vpc.yaml
```