# Azure Monitor CLI | Notes


## az monitor metrics list

### Load Balancer

- Available metrics

```
VipAvailability
DipAvailability
ByteCount
PacketCount
SYNCount
SnatConnectionCount
AllocatedSnatPorts
UsedSnatPorts
```

- get metric

```
az monitor metrics  list \
    --resource ${RESOURCE} \
    --metrics SnatConnectionCount \
```

- only data points

```
RESOURCE="/subscriptions/XXX7/resourceGroups/azarc-dgbwg-rg/providers/Microsoft.Network/loadBalancers/azarc-dgbwg"
az monitor metrics  list \
    --resource ${RESOURCE} \
    --metrics SnatConnectionCount \
    --start-time 2022-01-28T13:41 \
    | jq -r '.value[].timeseries[].data[] | [ .timeStamp, .total|tostring ] | join(": ")' |head -n 30

az monitor metrics  list \
    --resource ${RESOURCE} \
    --metrics AllocatedSnatPorts \
    --start-time 2022-01-28T13:41 \
    | jq -r '.value[].timeseries[].data[] | [ .timeStamp, .average|tostring ] | join(": ")' |head -n 30

az monitor metrics  list \
    --resource ${RESOURCE} \
    --metrics UsedSnatPorts \
    --start-time 2022-01-28T13:41 \
    | jq -r '.value[].timeseries[].data[] | [ .timeStamp, .average|tostring ] | join(": ")' |head -n 30

az monitor metrics  list \
    --resource ${RESOURCE} \
    --metrics ByteCount \
    --start-time 2022-01-28T13:41 \
    | jq -r '.value[].timeseries[].data[] | [ .timeStamp, .total|tostring ] | join(": ")' |head -n 30

az monitor metrics  list \
    --resource ${RESOURCE} \
    --metrics PacketCount \
    --start-time 2022-01-28T13:41 \
    | jq -r '.value[].timeseries[].data[] | [ .timeStamp, .total|tostring ] | join(": ")' |head -n 30

az monitor metrics  list \
    --resource ${RESOURCE} \
    --metrics SYNCount \
    --start-time 2022-01-28T13:41 \
    | jq -r '.value[].timeseries[].data[] | [ .timeStamp, .total|tostring ] | join(": ")' |head -n 30
```

- Filter for ["Outbound availability"](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-diagnostics#outbound-availability-alerting)

```
az monitor metrics  list \
    --resource ${RESOURCE} \
    --metrics SnatConnectionCount \
    --start-time 2022-01-28T13:41 \
    --filter "ConnectionState eq 'Failed'" \
    | jq -r '.value[].timeseries[].data[] | [ .timeStamp, .total|tostring ] | join(": ")' |head -n 30
```


## See also

- [Labs: azure metrics parser](https://github.com/mtulio/mtulio.labs/tree/master/labs/azure-metrics-parser)
