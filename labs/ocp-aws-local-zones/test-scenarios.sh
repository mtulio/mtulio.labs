#!/bin/bash

#
# Script to test a custom installer binary.
#
# It will generate a custom install-config.yaml
# with different scenarios with edge machine pool, then
# test the 'create manifests' command over
# different scenarios, validating some generated manifests.
#

# set -o errexit
set -o pipefail
set -o nounset

declare -gx JQ_CMD="yq -j -r "
declare -gx BIN_PATH=$1; shift
declare -gx TEST_ID=$1; shift

declare -gx AWS_REGION="us-east-1"
declare -gx FITER_EDGE_ZONE_NAME="${AWS_REGION}-nyc-1a"

declare -gx EXPECTED_PUBLIC_SUBNETS=3
declare -gx EXPECTED_PRIVATE_SUBNETS=3

# USW2 basic tests LZ: 2
# USW2 full LZ: 7
declare -gx EXPECTED_MACHINE_POOL_EDGE=1

declare -gx EXPECTED_MACHINE_POOL_COMPUTE=$(( EXPECTED_PUBLIC_SUBNETS + EXPECTED_PRIVATE_SUBNETS ))
declare -gx EXPECTED_MACHINE_SETS_COUNT=$(( EXPECTED_MACHINE_POOL_EDGE + EXPECTED_PRIVATE_SUBNETS ))

# USE1=6
# USW2=4
declare -gx ZONE_COUNT_REGION=5
# USE1=3+3+X
# USW2=3+3+6
declare -gx SUBNET_COUNT_REGION=7

declare -gx INSTALLER_SUCCESS_CODE=0
declare -gx INSTALLER_ERROR_CODE=3

if [[ -z ${BIN_PATH} ]]; then
    echo "${BIN_PATH} invalid argument #1 [${BIN_PATH}]"
    exit 1
fi

if [[ ! -x ${BIN_PATH} ]]; then
    echo "${BIN_PATH} is not executable binary [${BIN_PATH}]"
    exit 1
fi

if [[ -z ${TEST_ID} ]]; then
    echo "invalid test id #2 [${TEST_ID}]"
    exit 1
fi

source "${PWD}/zz-subnets.list"
expected_subnets_count=${SUBNET_COUNT_REGION}
if [[ ${#SUBNETS[*]} -ne $expected_subnets_count ]]; then
    echo "unexpected subnet count. want=[${expected_subnets_count}] got=[${#SUBNETS[*]}]"
    exit 1
fi

TEST_DIR=${PWD}/test_${TEST_ID}

if [[ ! -d ${TEST_DIR} ]]; then
    mkdir "${TEST_DIR}"
fi

declare -g INSTALL_CONFIG_BASE=${TEST_DIR}/install-config-base.yaml
declare -g INSTALL_CONFIG_AWS=${TEST_DIR}/install-config-aws.yaml
declare -g INSTALL_CONFIG_AZURE=${TEST_DIR}/install-config-azure.yaml
declare -g INSTALL_CONFIG_NONE=${TEST_DIR}/install-config-none.yaml
declare -gx CONSOLE_LOG=${TEST_DIR}/console.log

show() {
    echo -e "$@" | tee -a "${CONSOLE_LOG}"
}

cat << EOF > "${INSTALL_CONFIG_BASE}"
apiVersion: v1
metadata:
  name: ipi-${TEST_ID}
publish: External
pullSecret: '$(cat ~/.openshift/pull-secret-latest.json)'
sshKey: |
  $(cat ~/.ssh/id_rsa.pub)
EOF

cat << EOF > "${INSTALL_CONFIG_AWS}"
$(cat "${INSTALL_CONFIG_BASE}")
baseDomain: devcluster.openshift.com
platform:
  aws:
    region: $AWS_REGION
EOF

cat << EOF > "${INSTALL_CONFIG_AZURE}"
$(cat "${INSTALL_CONFIG_BASE}")
baseDomain: splat.azure.devcluster.openshift.com
platform:
  azure: {
    "baseDomainResourceGroupName": "os4-common",
    "cloudName": "AzurePublicCloud",
    "outboundType": "Loadbalancer",
    "region": "eastus"
}
EOF

cat << EOF > ${INSTALL_CONFIG_NONE}
$(cat "${TEST_DIR}/install-config-base.yaml")
baseDomain: devcluster.openshift.com
platform:
  none: {}
EOF

cat << EOF > "${TEST_DIR}/subnets-all.txt"
$(echo "    subnets:"; for SB in "${SUBNETS[@]}"; do echo "    - $SB"; done)
EOF

cat << EOF > "${TEST_DIR}/subnets-worker.txt"
$(echo "    subnets:"; for SB in "${SUBNETS[@]:0:6}"; do echo "    - $SB"; done)
EOF

cat << EOF > "${TEST_DIR}/subnets-edge.txt"
$(echo "    subnets:"; for SB in "${SUBNETS[@]:6:7}"; do echo "    - $SB"; done)
EOF

if [[ -f "${TEST_DIR}/install-config-base.yaml" ]]; then
    show "Base config created: [${TEST_DIR}/install-config-base.yaml]"
fi

### > Start tests

declare -g RESULTS=("TEST_ID-NAME\t\t\t\t RESULT\t INST_MANIFEST_RC\t SUMMARY: ComputePool[#] machines[zone=replicas=type=ebs=label_edge,...]\t")
declare -g RESULTS_SHORT=("TEST_ID-NAME\t\t\t\t RESULT\t INST_MANIFEST_RC")

RESULTS+=("--------\t\t\t\t --\t -- \t --\t -----")
RESULTS_SHORT+=("--------\t\t\t\t --\t -- \t --")

create_manifests() {
    show "\n>> Creating manifests for [${TEST_NAME}] <<<<<"
    local test_case_dir
    test_case_dir=$1
    cp "${test_case_dir}-install-config.yaml" "${test_case_dir}/install-config.yaml"
    set +o pipefail
    ./${BIN_PATH} create manifests --dir "${test_case_dir}"
    export INSTALLER_MANIFEST_RC=$?
    set -o pipefail
}

set_results_default() {
    export MACHINE_POOL_COUNT=0
    export MACHINE_POOL_AZS=""
    export MACHINE_POOL_SUMMARY=""
}

show_machinesets() {
    set_results_default
    local test_dir
    test_dir=$1
    for ms in $(ls ${test_dir}/openshift/99_openshift-cluster-api_worker-machineset-*.yaml); do
        manifest=$(basename $ms)
        az=$(${JQ_CMD} .spec.template.spec.providerSpec.value.placement.availabilityZone ${ms})
        instance_type=$(${JQ_CMD} .spec.template.spec.providerSpec.value.instanceType ${ms})
        ebs_root=$(${JQ_CMD} .spec.template.spec.providerSpec.value.blockDevices[].ebs.volumeType ${ms})
        replicas=$(${JQ_CMD} .spec.replicas ${ms})
        lbl_edge=$(${JQ_CMD} '.spec.template.spec.metadata.labels["machine.openshift.io/zone-type"]' ${ms} || true)
        echo -e ">> $manifest
replicas\t: ${replicas}
AZ\t\t: ${az}
instanceID\t: ${instance_type}
EBS\t\t: ${ebs_root}
zone_type\t $lbl_edge
meta\t\t: $(yq .spec.template.spec.metadata ${ms})
" ;
        MACHINE_POOL_COUNT=$(( ${MACHINE_POOL_COUNT} + 1 ))
        summary="${az}=${replicas}=${instance_type}=${ebs_root}=${lbl_edge}"
        if [[ -z ${MACHINE_POOL_SUMMARY} ]]; then
            MACHINE_POOL_SUMMARY="${summary}"
        else
            MACHINE_POOL_SUMMARY="${MACHINE_POOL_SUMMARY},${summary/\n//}"
        fi
    done    
}

set_results() {
    local want_installer_rc=$1; shift
    local want_machinepoolcount=$1; shift
    local msg_installer="OK[${INSTALLER_MANIFEST_RC}]\t\t"
    local final_results=OK
    local final_msg_field=TBD
    local final_msg=""

    if [[ $want_installer_rc -ne ${INSTALLER_MANIFEST_RC} ]]; then
        final_results=FAIL
        msg_installer="ERR[${INSTALLER_MANIFEST_RC}]\t\t"
    elif [[ ${INSTALLER_MANIFEST_RC} -ne 0 ]]; then
        msg_installer="OK_ERR[${INSTALLER_MANIFEST_RC}]\t"
    fi

    if [[ $want_machinepoolcount -ne ${MACHINE_POOL_COUNT} ]]; then
        final_results=FAIL
    fi

    final_msg_field="#[${MACHINE_POOL_COUNT}] machines[${MACHINE_POOL_SUMMARY}]"

    final_msg="${TEST_NAME}\t ${final_results}\t ${msg_installer} ${final_msg_field}"
    RESULTS+=("$final_msg")
    RESULTS_SHORT+=("${TEST_NAME}\t ${final_results}\t ${msg_installer}")
    show "$final_msg"
}


### TEST definition

run_tests_aws_existing_vpc() {
   
    # workers subnets only
    TEST_NAME="t00_01-aws-exist_vpc_workers-empty"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
$(cat ${TEST_DIR}/subnets-worker.txt)
EOF
    create_manifests ${TEST_CASE_DIR}
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "${EXPECTED_PRIVATE_SUBNETS}"

    # workers subnets with edge definition
    TEST_NAME="t00_01-aws-exist_vpc_workers-pool_edge"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
$(cat ${TEST_DIR}/subnets-worker.txt)
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform: {}
EOF
    create_manifests ${TEST_CASE_DIR}
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_ERROR_CODE}" "0"


    TEST_NAME="t00_01-aws-exist_vpc_workers-2x\t"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
$(cat ${TEST_DIR}/subnets-worker.txt)
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
EOF
    create_manifests ${TEST_CASE_DIR}
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_ERROR_CODE}" "0"


    TEST_NAME="t01-aws-exist_vpc_all-pool_empty"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
$(cat ${TEST_DIR}/subnets-all.txt)
EOF
    create_manifests ${TEST_CASE_DIR}
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "${EXPECTED_MACHINE_SETS_COUNT}" 

    TEST_NAME="t02-aws-exist_vpc_all-pool_worker"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
$(cat ${TEST_DIR}/subnets-all.txt)
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
EOF
    create_manifests ${TEST_CASE_DIR}
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "${EXPECTED_MACHINE_SETS_COUNT}"


    TEST_NAME="t03-aws-exist_vpc_all-pool_edge_only"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
$(cat ${TEST_DIR}/subnets-all.txt)
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform: {}
EOF
    create_manifests ${TEST_CASE_DIR}
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "${EXPECTED_MACHINE_SETS_COUNT}"


    TEST_NAME="t04-aws-exist_vpc_all-pool_wk_edge"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
$(cat ${TEST_DIR}/subnets-all.txt)
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform: {}
EOF
    create_manifests ${TEST_CASE_DIR}
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "${EXPECTED_MACHINE_SETS_COUNT}"

    TEST_NAME="t05-aws-exist_vpc_all-pool_edge_inst"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
$(cat ${TEST_DIR}/subnets-all.txt)
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform:
    aws:
      type: c5d.2xlarge
EOF
    create_manifests ${TEST_CASE_DIR}
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "${EXPECTED_MACHINE_SETS_COUNT}"


    TEST_NAME="t06-aws-exist_vpc_all-pool_edge_ebs"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
$(cat ${TEST_DIR}/subnets-all.txt)
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform:
    aws:
      rootVolume:
        type: gp3
        size: 120
EOF
    create_manifests ${TEST_CASE_DIR}
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "${EXPECTED_MACHINE_SETS_COUNT}"


    TEST_NAME="t07-aws-exist_vpc_all-pool_edge_zones"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
$(cat ${TEST_DIR}/subnets-all.txt)
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform:
    aws:
      zones:
      - ${FITER_EDGE_ZONE_NAME}
EOF
    create_manifests ${TEST_CASE_DIR}
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "4"


    TEST_NAME="t08-aws-exist_vpc_all-pool_edge_repl"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
$(cat ${TEST_DIR}/subnets-all.txt)
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  replicas: 5
EOF
    create_manifests ${TEST_CASE_DIR}
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "${EXPECTED_MACHINE_SETS_COUNT}"


    TEST_NAME="t09-aws-exist_vpc_edge_net-pool_edge"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
$(cat ${TEST_DIR}/subnets-edge.txt)
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform: {}
EOF
    create_manifests ${TEST_CASE_DIR} || true
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_ERROR_CODE}" "0"

}


run_tests_aws_new_vpc() {
 
    TEST_NAME="t10_01-aws-new_vpc-pool_compute_empty"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
EOF
    create_manifests ${TEST_CASE_DIR} || true
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "${ZONE_COUNT_REGION}"

    TEST_NAME="t10_02-aws-new_vpc-pool_worker_only"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
EOF
    create_manifests ${TEST_CASE_DIR} || true
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "${ZONE_COUNT_REGION}"


    TEST_NAME="t10_03-aws-new_vpc-pool_edge_only"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform: {}
EOF
    create_manifests ${TEST_CASE_DIR} || true
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_ERROR_CODE}" "0"


    TEST_NAME="t10_04-aws-new_vpc-pool_worker_edge"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AWS})
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform: {}
EOF
    create_manifests ${TEST_CASE_DIR}
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_ERROR_CODE}" "0"

}

run_tests_none() {

    TEST_NAME="t20_01-plat_none-default__config"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_NONE})
EOF
    create_manifests ${TEST_CASE_DIR} || true
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "0"

    TEST_NAME="t20_02-plat_none-pool_worker_edge"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_NONE})
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform: {}
EOF
    create_manifests ${TEST_CASE_DIR} || true
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_ERROR_CODE}" "0"

}


# Azure tests
run_test_azure() {
    TEST_NAME="t30_01-plat_azure-default_config"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AZURE})
EOF
    create_manifests ${TEST_CASE_DIR} || true
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "3"

    TEST_NAME="t30_02-plat_azure-pool_worker_only"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AZURE})
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
EOF
    create_manifests ${TEST_CASE_DIR} || true
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_SUCCESS_CODE}" "3"


    TEST_NAME="t30_03-plat_azure-pool_worker_edge"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AZURE})
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform: {}
EOF
    create_manifests ${TEST_CASE_DIR} || true
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_ERROR_CODE}" "0"


    TEST_NAME="t30_04-plat_azure-pool_edge_only"
    TEST_CASE_DIR="${PWD}/test_${TEST_ID}/${TEST_NAME}"
    show "\n>>>>> Setting up test [${TEST_NAME}] <<<<<"

    if [[ ! -d ${TEST_CASE_DIR} ]]; then
        mkdir ${TEST_CASE_DIR}
    fi
    cat << EOF > ${TEST_CASE_DIR}-install-config.yaml
$(cat ${INSTALL_CONFIG_AZURE})
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: edge
  platform: {}
EOF
    create_manifests ${TEST_CASE_DIR} || true
    show_machinesets ${TEST_CASE_DIR}
    set_results "${INSTALLER_ERROR_CODE}" "0"

}

run_tests_aws_existing_vpc
run_tests_aws_new_vpc
run_tests_none
run_test_azure


echo ">>>>>>>>>>>>>>>>>>>>>> Results"

for RS in "${RESULTS[@]}"; do
    show "${RS}";
done

echo ">>>>>>>>>>>>>>>>>>>>>> Results"
for RS in "${RESULTS_SHORT[@]}"; do
    show "${RS}";
done
