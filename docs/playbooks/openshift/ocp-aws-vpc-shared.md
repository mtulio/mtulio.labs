# Lab - OCP VPC-Shared Installation Steps

> Note: incomplete due to limitations.

Steps to create VPC-Sharing with Private Hosted Zone (PHZ) on different accounts

Scenario:
- Account A:
    - VPC sharing with Account_B
- Account B: 
    - private hosted zone
    - EC2 resources running in VPC-Shared by Account_A

## Steps

### Setup Account A

- [Create VPC on Account A](https://us-east-1.console.aws.amazon.com/vpc/home?region=us-east-1#CreateVpcWizard:)
- [Create a Resource Sharing](https://us-east-1.console.aws.amazon.com/ram/home?region=us-east-1#CreateResourceShare), selecting the subnets to be shared with Account B
    - Tradeoffs when sharing the resources
        - Enabling RAM only in AWS Org will not work
        - Enabling RAM in AWS Org makes the RAM Settings unchangeable
        - Disabling RAM in AWS Org allows the RAM Settings to be changed, then enabled.
        - Once the flag `Enabling sharing with AWS Organizations` is set, you can **create** the resource sharing associated with resources to be shared.
        - It was allowed to enable that flag only in the Master account, where AWS Org is created. The is an open question on how to allow child accounts to use RAM and share resources since the AWS Org RAM flag is not working as expected.
    - Create the resource sharing the subnet. Set the target to Account, Org, or OU, that is placed the Account B
    - Go to Participant account, Account B, and check if the subnets are shared there


### Setup Account B

Create the PHZ, associating it to a **LOCAL VPC** (it's not supported to create a PHZ without VPCs, it's also not supported to create a PHZ associating to shared VPC)

- A) Go to `Account A` and run:

> NOTE: Result=Failed - Account A was not authorized to create the requests to PHZ_B. Only when creating the PHZ in Account A

```bash
PHZ_ID_B=Z045791747O0ULXC2PQG
#PHZ_ID_A=Z032052428E32A7FG2XWS
PHZ_ID=${PHZ_ID_B}

PHZ_REGION=us-east-1
VPC_SHARED_REGION=us-east-1
VPC_SHARED_ID=vpc-060d341979cb34623

ACCOUNT_A_AKID="[redacted]"
ACCOUNT_A_AKSECRET="[redacted]"
ACCOUNT_A_TOKEN="[redacted]"

AWS_ACCESS_KEY_ID=${ACCOUNT_A_AKID} \
    AWS_SECRET_ACCESS_KEY=${ACCOUNT_A_AKSECRET} \
    AWS_SESSION_TOKEN=${ACCOUNT_A_TOKEN} \
    aws route53 create-vpc-association-authorization \
        --hosted-zone-id ${PHZ_ID} \
        --vpc VPCRegion=${VPC_SHARED_REGION},VPCId=${VPC_SHARED_ID} \
        --region ${PHZ_REGION}
```

- B) Return to `Account B` and run:
```bash
ACCOUNT_B_AKID="[redacted]"
ACCOUNT_B_AKSECRET="4[redacted]"
ACCOUNT_B_TOKEN="[redacted]"


AWS_ACCESS_KEY_ID=${ACCOUNT_B_AKID} \
    AWS_SECRET_ACCESS_KEY=${ACCOUNT_B_AKSECRET} \
    AWS_SESSION_TOKEN=${ACCOUNT_B_TOKEN} \
    aws route53 associate-vpc-with-hosted-zone \
        --hosted-zone-id ${PHZ_ID} \
        --vpc VPCRegion=${VPC_SHARED_REGION},VPCId=${VPC_SHARED_ID} \
        --region ${PHZ_REGION}
```
- C) Go back to `Account A` and delete the association request

```bash
AWS_ACCESS_KEY_ID=${ACCOUNT_A_AKID} \
    AWS_SECRET_ACCESS_KEY=${ACCOUNT_A_AKSECRET} \
    AWS_SESSION_TOKEN=${ACCOUNT_A_TOKEN} \
    aws route53 delete-vpc-association-authorization \
        --hosted-zone-id ${PHZ_ID} \
        --vpc VPCRegion=${VPC_SHARED_REGION},VPCId=${VPC_SHARED_ID} \
        --region ${PHZ_REGION}
```

### Create resources on Shared-VPC

- Return to `Account B` and run instances in the shared VPC
