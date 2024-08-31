## Deploy VPC Endpoint (VPCe) for Proxy Cluster

!!! warning "Experimental steps"
    The steps described on this page are experimental!

!!! info "CloudFormation templates"
    The CloudFormation templates mentioned on this page are available in the path:
    [mtulio.labs/labs/labs/ocp-install-iac/aws-cloudformation-templates](https://github.com/mtulio/mtulio.labs/tree/master/labs/ocp-install-iac/aws-cloudformation-templates)


This section describe the steps to create a custom VPC PrivateLink
to expose the HA cluster proxy service, allowing be shared privately
between different VPCs/Accounts.


### Create the VPC PrivateLink service

> TODO