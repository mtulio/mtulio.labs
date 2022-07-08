# Install OpenShift cluster in the edge with AWS Local Zones (tests)

This is an attachment for the article `ocp-aws-local-zones-day-0.md` (not included on the main post, but provides additional information to support the article).

## Tests performed <a name="tests"></a>

<!--
Tests log:

- 1: Install a cluster with LB subnets tagging. Result: fail, the Controller discoverer added the LZ subnet to the list to create the IG
- 2: Install a cluster with LB subnets tagging on the zones on the parent region and `unmanaged` to the LZ subnet. Result: success. The discoverer ignored the LZ subnet
- 3A: Install a cluster with no LB subnets tagging, and unmanaged on LZ subnet: Result: Succes
- 3B: Install the ELB Operator on the LZ subnet which has an `unmanaged` tag. Result: Controller is not finding the VPC tagged by cluster tag
- 4: Install with tags: Subn for LB, LZ Unmanaged, VPC cluster shared. Results: OK. There were wrong credentials granted to the controller, so the tag for VPC may be useless. Need to run more tests
- 5: Install with tags: Subn for LB. Results: Success
- 6: Install #4 + using NLB as default. Result: Success. The NLB has more unrestrictive security group rules, installing the compute nodes in the public subnets could expose the node ports directly to the internet.
- 7: Install with tags on Subn for LZ, No LB tags on All Subn. Results: Success. We don't need the Sub ELB tags on the parent zone, we need the unmanaged on the LZ zone
- 8: Install with tag kubernetes.io/role/elb=0 for LZ, and no tags for all Subn. Results: Failed. The Ingress does not look to the ELB tag and tries to add the subnet to the default router lb. It was fixed only when I added kubernetes.io/cluster/unmanaged=true tag (It is OK for provided network, but can be a problem on installer)
- 9: Install with LB tags on parent region, and no tags on LZ subnet. Result: failed
- 10: VPC Tag, LZ unmanaged tag. Result: Success
- 11: Set the LZ Subnet tag to kubernetes.io/cluster/<infraID>=unmanaged and observe the behavior. Result: Failed. The installer did not touch on this subnet, but the ingress operator failed trying to add the LZ subnet to the balancer.
-->

A quick review of the goal of this post:

- install an OpenShift cluster successfully in existing VPC which has, at least one, subnet on the Local Zone
- Make sure all the cluster operators has been finished without issues
- Make sure the Local Zone subnet can be used further deploying ingress exclusively for it using AWS ELB Operator (Local Zone supports only Application Load Balancers)

Said that, several combinations of tagging were executed to find the correct approach to install a cluster in existing VPC without falling into the Load Balancer controller add the Local Zone subnet automatically to the default router - which should be located only in the subnets in the parent region (non-edge/Local Zones).

The following matrix was created to document all the tests performed and the results:

| #   | VPC tag   | ELB tag   | LZ tag      | Res Install | Res ELB Op  | Desc |
| --  | --        | --        | --          | --          | --          | -- |
| 1   | --        | X         | --          | Fail        | NT          | `ERR#1` |
| 2   | --        | X         | X           | Success     | NT          | -- |
| 3A  | --        | --        | X           | Success     | NT          | -- |
| 3B  | --        | --        | X           | Success     | Failed      | `ERR#2`: ELB Oper expects cluster tag on VPC |
| 4   | X         | X         | X           | Success     | Success     | Needs retest, creds issues |
| 5   | X         | X         | X           | Success     | Success     | -- |
| 6   | X         | X         | X           | Success     | Success     | NLB as default ingress |
| 7   | --        | --        | X           | Success     | NT          | -- |
| 8   | --        | --        | X*          | Failed      | NT          | `ERR#1`: `*elb=0`: IG Controller ignored the '0' value |
| 9   | X         | X         | --          | Failed      | NT          | `ERR#1`: Controller tries to add the LZ Subnet |
| 10  | X         | --        | X           | Success     | Success     | -- |
| 11  | X         | --        | X*          | Failed      | NT          | `ERR#1`: set tag `kubernetes.io/cluster/<infraID>=unmanaged` 4.11.0-rc.1 |

- `VPC tag` is the cluster tag created on the VPC `kubernetes.io/cluster/<infraID>=.*`
- `ELB tag` is the Load Balancer tags created on the subnets on the parent zone (only) used by [Controler Subnet Auto Discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/deploy/subnet_discovery/): `kubernetes.io/role/elb=1` or `kubernetes.io/role/internal-elb=1`
- `LZ tag` is the "unmanaged" cluster tag set on the Local Zone subnet (only): `kubernetes.io/cluster/unmanaged=true`
- `Res Install` is the result of the installer execution
- `Res ELB Oper` is the result of the setup of ALB Operator and provisioning the ingress in the Local Zone Subnet (only)


`ERR#1`: Error when the controller tries to add the Local Zone subnet (`oc get co`):
```
ingress                                                  False       True          True       92s     The "default" ingress controller reports Available=False: IngressControllerUnavailable: One or more status conditions indicate unavailable: LoadBalancerReady=False (SyncLoadBalancerFailed: The service-controller component is reporting SyncLoadBalancerFailed events like: Error syncing load balancer: failed to ensure load balancer: ValidationError: You cannot have any Local Zone subnets for load balancers of type 'classic'...
```

`ERR#2`: ELB Controller cannot find the VPC cluster tag (`oc logs pod/aws-load-balancer-operator-controller-manager-[redacted] -n aws-load-balancer-operator`)
```
1.6572192750063934e+09	ERROR	setup	failed to get VPC ID	{"error": "no VPC with tag \"kubernetes.io/cluster/lzdemo-b88kd\" found"}
main.main
	/workspace/main.go:133
runtime.main
	/usr/local/go/src/runtime/proc.go:255
```

### Expectations

For default router/ingress/controller:

- Should not auto discovery all the subnets on the VPC when the subnets has been set on the install-config.yaml
- Should not auto discovery all the subnets on the VPC when the `kubernetes.io/role/elb=1` has been added to public subnets
- Should not try to add subnets not supported (Local Zones, Wavelength) to the technology used by Load Balancer (CLB/NLB) on the ingress
- The controller auto discover ignores the `kubernetes.io/role/elb=0`, so we can specify what subnets we would not like to be added/used by Load Balancer

For the AWS ELB Operator/Controller:

- Must not expect cluster tag set on the VPC as it is not required when installing clusters in existing VPCs. [See the documentation fragment](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-vpc.html#installation-custom-aws-vpc-requirements_installing-aws-vpc).
- Should not add all the nodes on the target groups, only the nodes which are running the service pods, or compute nodes which are in the zones of ALB. It will: 1) decrease the number of Health checks arriving to nodes not running the application; 2) decrease the number of unused nodes on the targets

For the uninstalling:

- Any ELB Created by ALB Operator should be deleted on the installer destroy flow
- Any SGs created to attach to ELB should be deleted
