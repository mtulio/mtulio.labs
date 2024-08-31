# OCP on AWS - Deploy a cluster using existing Public IPv4 Pool

This guide shows how to create a cluster using a Public IPv4 pool that you brought to AWS.

If you not provisioned and advertised your Public CIDR IPv4 blocks to AWS, see the following AWS documentation to get starterd: "[Onboard your BYOIP](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-byoip.html#byoip-onboard)"

Starting on OpenShift 4.16 you can assign addresses from your custom Public IPv4 pool to cluster resources created by the openshift-install program when installing a cluster. This deployment allows you to have more control of public IPv4 used by the cluster.

Bringing your own Public IPv4 Pool (BYO Public IPv4) can also be used as an alternative to buying Public IPs from AWS, also considering the changes in charging for this since [February 2024](https://aws.amazon.com/blogs/aws/new-aws-public-ipv4-address-charge-public-ip-insights/).

## Prerequisites

- Public IPv4 Pool must be provisioned and advertised in the AWS Account. See more on AWS Documentation to "[Onboard your BYOIP](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-byoip.html#byoip-onboard)"
- Additional permissions must be added to: `ec2:DescribePublicIpv4Pools` and `ec2:DisassociateAddress`, 
- Total of ( (Zones*3 ) + 1) of Public IPv4 available in the pool, where: Zones is the total numbber of AWS zones used to deploy the OpenShift cluster.
    - Example to query the IPv4 pools available in the account, which returns the  `TotalAvailableAddressCount`:

```sh
$ aws ec2 describe-public-ipv4-pools --region us-east-1
{
    "PublicIpv4Pools": [
        {
            "PoolId": "ipv4pool-ec2-012456789abcdef00",
            "Description": "",
            "PoolAddressRanges": [
                {
                    "FirstAddress": "157.254.254.0",
                    "LastAddress": "157.254.254.255",
                    "AddressCount": 256,
                    "AvailableAddressCount": 83
                }
            ],
            "TotalAddressCount": 256,
            "TotalAvailableAddressCount": 83,
            "NetworkBorderGroup": "us-east-1",
            "Tags": []
        }
    ]
}
```

## Steps

- Create the install config setting the field `platform.aws.publicIpv4Pool`, and create the cluster:

```yaml
apiVersion: v1
baseDomain: ${CLUSTER_BASE_DOMAIN}
metadata:
  name: ocp-byoip
platform:
  aws:
    region: ${REGION}
    publicIpv4Pool: ipv4pool-ec2-012456789abcdef00
publish: External
pullSecret: '...'
sshKey: |
  '...'
```

- Create the cluster

```sh
openshift-install create cluster
```
