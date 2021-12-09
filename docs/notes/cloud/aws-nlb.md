# NLB

## Health Checks

Network Load Balancers use active and passive health checks to determine whether a target is available to handle requests.

By default, each load balancer node routes requests only to the healthy targets in its Availability Zone. If you enable cross-zone load balancing, each load balancer node routes requests to the healthy targets in all enabled Availability Zones. 

Types:
- Active
- Passive



## References:

- [AWS-Docs/What is a Network Load Balancer?](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/introduction.html)
- [AWS-Docs/NLB Troubleshooting](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-troubleshooting.html)
- [AWS-Blog/Avoiding overload in distributed systems by putting the smaller service in control](https://aws.amazon.com/builders-library/avoiding-overload-in-distributed-systems-by-putting-the-smaller-service-in-control/)
- [Article/HyperPlane: A Scalable Low-Latency Notification Accelerator for Software Data Planes](https://www.microarch.org/micro53/papers/738300a852.pdf)
- [Article/Hyperplane partitioning: An approach to global data partitioning for distributed memory machines](https://www.researchgate.net/publication/3796478_Hyperplane_partitioning_An_approach_to_global_data_partitioning_for_distributed_memory_machines)
- [Article-PDF/Hyperplane partitioning: An approach to global data partitioning for distributed memory machines](https://www.researchgate.net/profile/Yn-Srikant/publication/3796478_Hyperplane_partitioning_An_approach_to_global_data_partitioning_for_distributed_memory_machines/links/5460e5740cf2c1a63bff7671/Hyperplane-partitioning-An-approach-to-global-data-partitioning-for-distributed-memory-machines.pdf?origin=publication_detail)
- [Sandbox application to use different servers for Service and Health Check](https://github.com/mtulio/go-lab-api/blob/main/cmd/lab-app-server/main.go)
