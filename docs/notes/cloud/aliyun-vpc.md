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
