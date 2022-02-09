# Azure High Availability

## Availability Sets

References:

- [Regions and availability zones](https://docs.microsoft.com/en-us/azure/availability-zones/az-overview)
- [Availability sets overview](https://docs.microsoft.com/en-us/azure/virtual-machines/availability-set-overview)

Overview of Region:

- Each Azure region features datacenters deployed within a latency-defined perimeter
- They're connected through a dedicated regional low-latency network

Overview of AZs:

- Azure availability zones are physically separate locations within each Azure region that are **tolerant to local failures.**
- Failures can range from software and hardware failures to events such as earthquakes, floods, and fires.
- Tolerance to failures is achieved because of redundancy and logical isolation of Azure services.
- To ensure resiliency, a minimum of three separate availability zones are present in all availability zone-enabled regions.
- **Azure availability zones are connected by a high-performance network with a round-trip latency of less than 2ms.**
- They help your data stay synchronized and accessible when things go wrong.
- **Each zone is composed of one or more datacenters equipped with independent power, cooling, and networking infrastructure.**
- Availability zones are designed so that if one zone is affected, regional services, capacity, and high availability are supported by the remaining two zones.

Overview Availability sets:

- **Each virtual machine in your availability set is assigned an update domain and a fault domain**
- Each availability set can be configured with up to **three fault domains and twenty update domains**
- **Update domains indicate groups of virtual machines and underlying physical hardware** that can be rebooted at the same time
- When more than five virtual machines are configured within a single availability set with five update domains, the sixth virtual machine is placed into the same update domain as the first virtual machine, the seventh in the same update domain as the second virtual machine, and so on.
- The order of update domains being rebooted may not proceed sequentially during planned maintenance, but only one update domain is rebooted at a time.
- A rebooted update domain is given 30 minutes to recover before maintenance is initiated on a different update domain.
