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
