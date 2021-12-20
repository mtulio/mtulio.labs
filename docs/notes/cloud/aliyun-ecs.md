# Aliyun/AlibabaCloud ECS (Compute)

## ECS

- Check availability/Stock in a given region

``` shell
aliyun ecs DescribeAvailableResource \
    --RegionId us-east-1 \
    --InstanceType ecs.g6.large \
    --DestinationResource InstanceType \
    | jq -r '.AvailableZones.AvailableZone[] | ("=>", .ZoneId, .StatusCategory, .Status, .StatusCategory)'
```

- Describe instances attributes

``` shell
aliyun ecs DescribeInstances \
    --RegionId us-east-1 \
    --VpcId ${VPC_ID} \
    |jq -r '.Instances.Instance[] | ("--", .HostName, .ZoneId, .VpcAttributes.VpcId, .VpcAttributes.VSwitchId)'
```

- Describe instances (+VSwitch filter)

``` shell
aliyun ecs DescribeInstances \
    --RegionId us-east-1 \
    --VpcId ${VPC_ID} |jq -r '.Instances.Instance[].VpcAttributes.VSwitchId' |sort |uniq -c
```


### CLI Endpoint

Using cli in different endpoints

- Global Endpoint
``` shell
$(which time) aliyun ecs DescribeAvailableResource \
    --RegionId us-east-1 \
    --InstanceType ecs.g6.large \
    --DestinationResource InstanceType >/dev/null
```

- Global endpoint for the service as argument

``` shell
ALI_ENDPOINT="ecs.aliyuncs.com"
dig +short ${ALI_ENDPOINT}
$(which time) aliyun ecs DescribeAvailableResource \
    --RegionId us-east-1 \
    --InstanceType ecs.g6.large \
    --DestinationResource InstanceType \
    --endpoint ${ALI_ENDPOINT} >/dev/null
```

- Regional endpoint for `us-east-1`

``` shell
ALI_ENDPOINT="ecs.us-east-1.aliyuncs.com"
dig +short ${ALI_ENDPOINT}
$(which time) aliyun ecs DescribeAvailableResource \
    --RegionId us-east-1 \
    --InstanceType ecs.g6.large \
    --DestinationResource InstanceType \
    --endpoint ${ALI_ENDPOINT} >/dev/null
```

- Regional endpoint for `cn-hangzhou`
``` shell
ALI_ENDPOINT="ecs-cn-hangzhou.aliyuncs.com"
dig +short ${ALI_ENDPOINT}
$(which time) aliyun ecs DescribeAvailableResource \
    --RegionId us-east-1 \
    --InstanceType ecs.g6.large \
    --DestinationResource InstanceType \
    --endpoint ${ALI_ENDPOINT} >/dev/null
```
