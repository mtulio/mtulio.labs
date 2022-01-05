# Aliyun/AlibabaCloud VPC

## VPC

- Create VPC

``` bash
# create VPC
aliyun vpc CreateVpc \
    --RegionId us-east-1 \
    --CidrBlock 10.1.0.0/16 \
    --Description "pr5379 t1" \
    --VpcName "${VPC_NAME}"

VPC_ID="$(aliyun vpc DescribeVpcs \
    --RegionId us-east-1 \
    --VpcName ${VPC_NAME} a
    |jq -r '.Vpcs.Vpc[].VpcId')"
echo ${VPC_ID}
```

- Check existing

``` shell
aliyun vpc DescribeVpcs \
    --RegionId us-east-1 \
    |jq -r '.Vpcs.Vpc[]| (.VpcId, .VpcName)'
```

- Batch: list/create/list/delete on different regions:

Script used to test pourpose to validate cli iteraction with VPC Cloud API.

```bash
VPC_PREFIX="test-"
REGIONS="us-east-1 cn-beijing ap-northeast-1"

list_vpcs() {
  echo "# Listing VPCs on Regions..."
  for R in ${REGIONS}; do 
	  echo "## Listing VPCs on region=[${R}]"
	  aliyun vpc DescribeVpcs --RegionId "${R}" |jq -r '.Vpcs.Vpc[] | (.VpcId, .VpcName)'
  done
}

create_vpcs() {
  echo "# Creating VPC on Regions..."
  for R in ${REGIONS}; do 
    echo "## Creating VPCs on region=[${R}]"
    VPC_NAME="${VPC_PREFIX}-${R}"
    aliyun vpc CreateVpc \
      --RegionId "${R}" \
      --CidrBlock 10.0.0.0/16 \
      --Description "${VPC_PREFIX} vpc on Region ${R}" \
      --VpcName "${VPC_NAME}"
    VPC_ID="$(aliyun vpc DescribeVpcs \
        --RegionId "${R}" \
        --VpcName "${VPC_NAME}" \
        |jq -r '.Vpcs.Vpc[].VpcId')"
    echo "## Describing VpcId=[${VPC_ID}]"
    aliyun vpc DescribeVpcs \
      --RegionId "${R}" \
      --VpcId "${VPC_ID}" \
      |jq -r '.Vpcs.Vpc[] | (.VpcId, .VpcName, .RegionId)'
  done
}

delete_vpcs() {
  echo "# Deleting [test] VPC on Regions..."
  for R in ${REGIONS}; do 
    VPC_NAME="${VPC_PREFIX}-${R}"
    echo "## Deleting VPC on region=[${R}] with Name=${VPC_NAME}"
    VPC_ID="$(aliyun vpc DescribeVpcs \
        --RegionId "${R}" \
        --VpcName "${VPC_NAME}" \
        |jq -r '.Vpcs.Vpc[].VpcId')"
    echo "## Deleting VpcId=[${VPC_ID}]"
    aliyun vpc DeleteVpc \
      --RegionId "${R}" \
      --VpcId "${VPC_ID}"
  done
}

list_vpcs
create_vpcs
list_vpcs
delete_vpcs
list_vpcs
```

## vSwitches

- Describe vSwitchs from a VPC

``` shell
VPC_ID="$(aliyun vpc DescribeVpcs \
    --RegionId us-east-1 \
    --VpcName ${VPC_NAME} \
    |jq -r '.Vpcs.Vpc[].VpcId')"
echo ${VPC_ID}

$ aliyun vpc DescribeVSwitches \
    --RegionId us-east-1 \
    --VpcId ${VPC_ID} \
    |jq -r '.VSwitches.VSwitch[] | ("--", .VpcId, .ZoneId, .VSwitchName, .VSwitchId)'
```

- Describe vSwitches from instances from a given VPC

```shell
aliyun ecs DescribeInstances \
    --RegionId us-east-1 \
    --VpcId ${VPC_ID} \
    | jq -r '.Instances.Instance[] |\
            ("--", .HostName, .ZoneId, \
                .VpcAttributes.VpcId, .VpcAttributes.VSwitchId\
            )'
```

- Describe and count by ID
```shell
aliyun ecs DescribeInstances \
    --RegionId us-east-1 \
    --VpcId ${VPC_ID} \
    | jq -r '.Instances.Instance[].VpcAttributes.VSwitchId' \
    | sort | uniq -c
```
