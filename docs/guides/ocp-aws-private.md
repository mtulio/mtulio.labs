# OCP on AWS private VPC

Options:

- Installing OCP on AWS with proxy
- Installing OCP on AWS with proxy and STS
- Installing OCP on AWS in disconnected clusters (no internet access)
- Installing OCP on AWS in disconnected clusters with STS


Solutions/Architectures/Deployments:

1) Deploy OpenShift in single stack IPv4 VPC with dedicated proxy in public subnets

- [ocp-aws-private-01-pre.md](./ocp-aws-private-01-pre.md)
- [ocp-aws-private-02-deploy-vpc-ipv4.md](./ocp-aws-private-02-vpc-ipv4-pub-blackhole.md)
- [ocp-aws-private-03_01-proxy-config.md](./ocp-aws-private-03_01-proxy-config.md)
- [ocp-aws-private-03_02-proxy-deploy-dedicated.md](./ocp-aws-private-03_02-proxy-deploy-dedicated.md)
- [Deploy private OpenShift cluster with dedicated proxy in VPC](./ocp-aws-private-04-cluster-install-proxy-jump.md)


2) Deploy OpenShift in single stack IPv4 VPC with shared proxy server IPv4

Step 1) Deploy shared proxy service

- Create Service VPC
- Deploy Proxy Server
- Deploy Custom VPC Service 

Step 2) Create VPC with private subnets

- Create VPC
- Create 

Step 2A) Deploy OpenShift cluster in private mode

- Deploy jump server using IPv6
- Deploy OpenShift using shared proxy service

Step 2B) Deploy OpenShift cluster in private mode

- Deploy jump server using private ipv4 and SSM access
- Deploy OpenShift using shared proxy service