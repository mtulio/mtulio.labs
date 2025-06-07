## OpenShift restricted deployment | About bastion host

!!! warning "Experimental steps"
    The steps described on this page are experimental!

The bastion host will be responsible to access resources within the private subnets
in the VPC.

The bastion hosts deployed in OpenShift deployment using fully private VPC, without
ingress connectvity from the internet, uses native AWS service, Systems Manager (SSM), to tunneling
and access resources in the private subnets.


### Prerequisites

- AWS CLI installed
- session-manager-plugin installed
- Valid AWS credentials to access SSM (TODO policy)

### About AWS Systems Session Manager

> https://docs.aws.amazon.com/pt_br/systems-manager/latest/userguide/what-is-systems-manager.html

### About SSM Sessions

> TODO

- AWS SSM agent
- Agent running in the unprivileged container in the Bastion host, if the session is directly started to the node it will be in the jail inside the container.
- BiDi channels through VPC PrivateLink (AWS VPC Interface Endpoints)

### About SSM Session tunneling

> TODO

### About costs

> TODO

### About the permissions

#### IAM

> TODO permissions required to create sessions with different documents.

#### Network resources

> TODO

Once the access to AWS SSM is granted by the IAM user, it is possible to create tunnels to access the VPC. Although there is second level of authentication for each service.

For example, Kubernetes API requires a kubeconfig or valid users to acces on it, for
SSH the nodes still requires a valid SSH key added in the install time, so there
are no privileges scalation issues in the Bastion node.

#### SSH access

> TODO


### Bastion host lifecycle

The Bastion host EC2 instance can be stopped if no external access is required.


### Deployment Overview

Server (Bastion host):

- AWS SSM agent installed
- Service Endpoints created

Client:

- Valid IAM User
- AWS CLI installed
- session-manager-plugin installed