#!/bin/bash

# Create the VPC and subnets in AWS Local Zones
# using CloudFormation Templates from UPI Installer.
# https://github.com/openshift/installer/tree/master/upi/aws/cloudformation

set -o pipefail
set -o nounset
set -o errexit

allowed_regions=("us-east-1" "use1" "us-west-2" "usw2")
if [[ $# -ne 1 ]]; then
    echo "Which region? ${allowed_regions[*]}"
    exit 1
fi
target_region=$1
valid_region=0
for reg in "${allowed_regions[@]}"; do
    if [[ "$reg" == "$target_region" ]]; then valid_region=1; fi
done
if [[ ${valid_region} -eq 0 ]]; then
    echo "Unknown region [${target_region}]. Allowed: ${allowed_regions[*]}"
    exit 1
fi

declare -gx CLUSTER_NAME
declare -gx VPC_CIDR
declare -gx VPC_SUBNETS_BITS
declare -gx VPC_SUBNETS_COUNT

# Cluster Name used by naming conventions
export CLUSTER_NAME="ipi-localzones"

# VPC Information
export VPC_CIDR="10.0.0.0/16"
export VPC_SUBNETS_BITS="10"
export VPC_SUBNETS_COUNT="3"

# AWS Regions and Local Zone group Information
export AWS_REGION_USW2="us-west-2"
export ZONE_GROUP_LAX="${AWS_REGION_USW2}-lax-1"
export ZONE_GROUP_LAS="${AWS_REGION_USW2}-las-1"
export ZONE_GROUP_DEN="${AWS_REGION_USW2}-den-1"
export ZONE_GROUP_PDX="${AWS_REGION_USW2}-pdx-1"
export ZONE_GROUP_PHX="${AWS_REGION_USW2}-phx-1"
export ZONE_GROUP_SEA="${AWS_REGION_USW2}-sea-1"

export AWS_REGION_USE1="us-east-1"
export ZONE_GROUP_BOS="${AWS_REGION_USE1}-bos-1"
export ZONE_GROUP_CHI="${AWS_REGION_USE1}-chi-1"
export ZONE_GROUP_DFW="${AWS_REGION_USE1}-dfw-1"
export ZONE_GROUP_IAH="${AWS_REGION_USE1}-iah-1"
export ZONE_GROUP_MCI="${AWS_REGION_USE1}-mci-1"
export ZONE_GROUP_MIA="${AWS_REGION_USE1}-mia-1"
export ZONE_GROUP_MSP="${AWS_REGION_USE1}-msp-1"
export ZONE_GROUP_NYC="${AWS_REGION_USE1}-nyc-1"
export ZONE_GROUP_PHL="${AWS_REGION_USE1}-phl-1"

# Base path for CloudFormation Templates
#export CFN_TEMPLATE_BASE="https://raw.githubusercontent.com/mtulio/installer/master"
export CFN_TEMPLATE_BASE="file:///home/mtulio/go/src/github.com/mtulio/installer"


stack_wait_for_complete() {
    local region=$1; shift
    local stack_name=$1; shift
    local stack_status
    echo -e " > Start waiter for the stack [${stack_name}] to report as CREATE_COMPLETE..."
    while true; do
        stack_status=$(aws cloudformation describe-stacks \
            --stack-name "${stack_name}" \
            --region "${region}" \
            | jq -r '.Stacks[0].StackStatus' )
        if [[ ${stack_status} == "CREATE_COMPLETE" ]]; then
            echo " >> Stack report ${stack_status}, continuing...";
            return
        fi
        echo " >> Stack reported undesired status: [${stack_status}] != [CREATE_COMPLETE]. Waiting 15s to the next check...";
        sleep 15
    done
}


create_vpc_stack() {
    local region=$1
    echo "Creating VPC stack..."

    TPL_URL="${CFN_TEMPLATE_BASE}/upi/aws/cloudformation/01_vpc.yaml"
    aws cloudformation create-stack \
        --region "${region}" \
        --stack-name ${CLUSTER_NAME}-vpc \
        --template-body ${TPL_URL} \
        --parameters \
            ParameterKey=VpcCidr,ParameterValue=${VPC_CIDR} \
            ParameterKey=SubnetBits,ParameterValue=${VPC_SUBNETS_BITS} \
            ParameterKey=AvailabilityZoneCount,ParameterValue=${VPC_SUBNETS_COUNT} || true &
    wait "$!"

    echo "Starting waiter VPC stack..."
    stack_wait_for_complete "${region}" "${CLUSTER_NAME}-vpc"
    # aws cloudformation wait stack-create-complete --stack-name "${CLUSTER_NAME}-vpc" &
    # wait "$!"

    aws cloudformation describe-stacks \
        --region "${region}" \
        --stack-name ${CLUSTER_NAME}-vpc 

    export VPC_ID=$(aws cloudformation describe-stacks \
        --region "${region}" \
        --stack-name ${CLUSTER_NAME}-vpc \
        | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="VpcId").OutputValue' )

    mapfile -t SUBNETS < <(aws cloudformation describe-stacks \
        --region "${region}" \
        --stack-name ${CLUSTER_NAME}-vpc \
        | jq -r '.Stacks[0].Outputs[0].OutputValue' | tr ',' '\n')

    mapfile -t -O "${#SUBNETS[@]}" SUBNETS < <(aws cloudformation describe-stacks \
        --region "${region}" \
        --stack-name ${CLUSTER_NAME}-vpc  \
        | jq -r '.Stacks[0].Outputs[1].OutputValue' | tr ',' '\n')

    export PUBLIC_RTB_ID=$(aws cloudformation describe-stacks \
        --region "${region}" \
        --stack-name ${CLUSTER_NAME}-vpc \
        | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PublicRouteTableId").OutputValue' )

    echo "REGION=${region}
VPC_ID=${VPC_ID}
SUBNETS=${SUBNETS[*]}
PUBLIC_RTB_ID=${PUBLIC_RTB_ID}"

}

create_subnet_stack() {
    local region
    local zone_name
    local subnet_cidr
    local subnet_name
    region="$1"; shift
    zone_name="$1"; shift
    subnet_cidr="$1"; shift
    subnet_name="$1"; shift

    echo ">> creating subnet [${subnet_name}] on zone [${zone_name}]"
    INSTALER_URL="file:///home/mtulio/go/src/github.com/mtulio/installer"
    #INSTALER_URL="https://raw.githubusercontent.com/mtulio/installer/master"
    TPL_URL="${INSTALER_URL}/upi/aws/cloudformation/01.99_net_local-zone.yaml"

    aws cloudformation create-stack \
        --region "${region}" \
        --stack-name "${subnet_name}" \
        --template-body "${TPL_URL}" \
        --parameters \
            ParameterKey=VpcId,ParameterValue="${VPC_ID}" \
            ParameterKey=ZoneName,ParameterValue="${zone_name}" \
            ParameterKey=SubnetName,ParameterValue="${subnet_name}" \
            ParameterKey=PublicSubnetCidr,ParameterValue="${subnet_cidr}" \
            ParameterKey=PublicRouteTableId,ParameterValue="${PUBLIC_RTB_ID}" || true &
    wait "$!"

    #aws cloudformation wait stack-create-complete --stack-name "${subnet_name}" &
    #wait "$!"
    echo "Starting waiter..."
    stack_wait_for_complete "${region}" "${subnet_name}"

    aws cloudformation describe-stacks \
        --region "${region}" \
        --stack-name "${subnet_name}"

    export SUBNET_ID=$(aws cloudformation describe-stacks \
        --region "${region}" \
        --stack-name "${subnet_name}" \
        | jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="PublicSubnetIds").OutputValue' )

    # Append the Local Zone Subnet ID to the Subnet List
    SUBNETS+=("${SUBNET_ID}")

    echo "SubnetsID=${#SUBNETS[*]}"
}


enable_zone_group() {
    local region=$1; shift
    local group=$1; shift
    aws ec2 modify-availability-zone-group \
        --region "${region}" \
        --group-name "${group}" \
        --opt-in-status opted-in
}

create_network_stack_use1() {
    create_vpc_stack "${AWS_REGION_USE1}"

    enable_zone_group "${AWS_REGION_USE1}" "${ZONE_GROUP_BOS}"
    create_subnet_stack "${AWS_REGION_USE1}" "${ZONE_GROUP_BOS}a" "10.0.192.0/22" "${CLUSTER_NAME}-public-use1-bos-1a"
    
    enable_zone_group "${AWS_REGION_USE1}" "${ZONE_GROUP_CHI}"
    create_subnet_stack "${AWS_REGION_USE1}" "${ZONE_GROUP_CHI}a" "10.0.196.0/22" "${CLUSTER_NAME}-public-use1-chi-1a"

    enable_zone_group "${AWS_REGION_USE1}" "${ZONE_GROUP_DFW}"
    create_subnet_stack "${AWS_REGION_USE1}" "${ZONE_GROUP_DFW}a" "10.0.200.0/22" "${CLUSTER_NAME}-public-use1-dfw-1a"

    enable_zone_group "${AWS_REGION_USE1}" "${ZONE_GROUP_IAH}"
    create_subnet_stack "${AWS_REGION_USE1}" "${ZONE_GROUP_IAH}a" "10.0.204.0/22" "${CLUSTER_NAME}-public-use1-iah-1a"

    enable_zone_group "${AWS_REGION_USE1}" "${ZONE_GROUP_MCI}"
    create_subnet_stack "${AWS_REGION_USE1}" "${ZONE_GROUP_MCI}a" "10.0.208.0/22" "${CLUSTER_NAME}-public-use1-mci-1a"

    enable_zone_group "${AWS_REGION_USE1}" "${ZONE_GROUP_MIA}"
    create_subnet_stack "${AWS_REGION_USE1}" "${ZONE_GROUP_MIA}a" "10.0.212.0/22" "${CLUSTER_NAME}-public-use1-mia-1a"

    enable_zone_group "${AWS_REGION_USE1}" "${ZONE_GROUP_MSP}"
    create_subnet_stack "${AWS_REGION_USE1}" "${ZONE_GROUP_MSP}a" "10.0.216.0/22" "${CLUSTER_NAME}-public-use1-msp-1a"

    enable_zone_group "${AWS_REGION_USE1}" "${ZONE_GROUP_NYC}"
    create_subnet_stack "${AWS_REGION_USE1}" "${ZONE_GROUP_NYC}a" "10.0.220.0/22" "${CLUSTER_NAME}-public-use1-nyc-1a"

    enable_zone_group "${AWS_REGION_USE1}" "${ZONE_GROUP_PHL}"
    create_subnet_stack "${AWS_REGION_USE1}" "${ZONE_GROUP_PHL}a" "10.0.224.0/22" "${CLUSTER_NAME}-public-use1-phl-1a"
}

create_network_stack_usw2() {
    create_vpc_stack "${AWS_REGION_USW2}"

    enable_zone_group "${AWS_REGION_USW2}" "${ZONE_GROUP_LAX}"
    create_subnet_stack "${AWS_REGION_USW2}" "${ZONE_GROUP_LAX}a" "10.0.192.0/22" "${CLUSTER_NAME}-public-usw2-lax-1a"
    create_subnet_stack "${AWS_REGION_USW2}" "${ZONE_GROUP_LAX}b" "10.0.196.0/22" "${CLUSTER_NAME}-public-usw2-lax-1b"

    enable_zone_group "${AWS_REGION_USW2}" "${ZONE_GROUP_LAS}"
    create_subnet_stack "${AWS_REGION_USW2}" "${ZONE_GROUP_LAS}a" "10.0.200.0/22" "${CLUSTER_NAME}-public-usw2-las-1a"

    enable_zone_group "${AWS_REGION_USW2}" "${ZONE_GROUP_DEN}"
    create_subnet_stack "${AWS_REGION_USW2}" "${ZONE_GROUP_DEN}a" "10.0.204.0/22" "${CLUSTER_NAME}-public-usw2-den-1a"

    enable_zone_group "${AWS_REGION_USW2}" "${ZONE_GROUP_PDX}"
    create_subnet_stack "${AWS_REGION_USW2}" "${ZONE_GROUP_PDX}a" "10.0.208.0/22" "${CLUSTER_NAME}-public-usw2-pdx-1a"

    enable_zone_group "${AWS_REGION_USW2}" "${ZONE_GROUP_PHX}"
    create_subnet_stack "${AWS_REGION_USW2}" "${ZONE_GROUP_PHX}a" "10.0.212.0/22" "${CLUSTER_NAME}-public-usw2-phx-1a"

    enable_zone_group "${AWS_REGION_USW2}" "${ZONE_GROUP_SEA}"
    create_subnet_stack "${AWS_REGION_USW2}" "${ZONE_GROUP_SEA}a" "10.0.216.0/22" "${CLUSTER_NAME}-public-usw2-sea-1a"
}

# Create network stack on the region
case $target_region in
"us-east-1"|"use1") create_network_stack_use1 ;;
"us-west-2"|"usw2") create_network_stack_usw2 ;;
*) echo "invalid region [${target_region}]. ${allowed_regions[*]}" ;;
esac

echo "SUBNETS=(${SUBNETS[*]})" | tee "${PWD}/zz-subnets.list"
