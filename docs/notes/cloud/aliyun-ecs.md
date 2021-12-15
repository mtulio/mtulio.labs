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
