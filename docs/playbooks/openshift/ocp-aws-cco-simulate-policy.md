# OCP on AWS - Simulate CredentialsRequests permissions

AWS Provides a service to simulate if policies are proper defined on resources (User, Group or Roles).

You can use the [AWS CLI](https://docs.aws.amazon.com/cli/latest/reference/iam/simulate-principal-policy.html) or [AWS Console](https://policysim.aws.amazon.com/home/index.jsp).

In this playbook I will describe how to simulate the actions defined on the policies Provided by CredentialsRequests are properly defined/created on the AWS IAM Role for the component Machine API.

Let's put the hands on:

- Get the actions defined on the CredentialsRequests

```bash
ACTIONS=$(oc get -n openshift-cloud-credential-operator -o json  \
        credentialsrequests openshift-machine-api-aws \
        | jq -r '.spec.providerSpec.statementEntries[].action[]' \
        | sort -u | tr '\n' ' ')
```

- Extract the IAM Role ARN from the MachineAPI secret created by CCO

```bash
MACHINE_API_ROLE_ARN=$(oc get secrets aws-cloud-credentials \
        -n openshift-machine-api \
        -o jsonpath='{.data.credentials}' |\
        base64 -d |\
        grep ^role_arn |\
        awk '{print$3}')
```

- Now, let's call the AWS [Simulate Principal Policy service](https://docs.aws.amazon.com/IAM/latest/APIReference/API_SimulatePrincipalPolicy.html), sending the actions and the IAM Role extracted on the steps above:

```bash
$ aws iam simulate-principal-policy \
    --policy-source-arn ${MACHINE_API_ROLE_ARN} \
    --action-names ${ACTIONS} \
    | jq -r '(["EVAL_ACTION","EVAL_DECISION"] | (., map(length*"-"))),
             (.EvaluationResults[] | [.EvalActionName, .EvalDecision ])
             | @tsv' | column -t
EVAL_ACTION                                             EVAL_DECISION
-----------                                             -------------
ec2:CreateTags                                          allowed
ec2:DescribeAvailabilityZones                           allowed
ec2:DescribeDhcpOptions                                 allowed
ec2:DescribeImages                                      allowed
ec2:DescribeInstances                                   allowed
ec2:DescribeInternetGateways                            allowed
ec2:DescribeSecurityGroups                              allowed
ec2:DescribeSubnets                                     allowed
ec2:DescribeVpcs                                        allowed
ec2:RunInstances                                        allowed
ec2:TerminateInstances                                  allowed
elasticloadbalancing:DeregisterTargets                  allowed
elasticloadbalancing:DescribeLoadBalancers              allowed
elasticloadbalancing:DescribeTargetGroups               allowed
elasticloadbalancing:DescribeTargetHealth               allowed
elasticloadbalancing:RegisterInstancesWithLoadBalancer  allowed
elasticloadbalancing:RegisterTargets                    allowed
iam:CreateServiceLinkedRole                             allowed
iam:PassRole                                            allowed
kms:CreateGrant                                         implicitDeny
kms:Decrypt                                             allowed
kms:DescribeKey                                         allowed
kms:Encrypt                                             allowed
kms:GenerateDataKey                                     allowed
kms:GenerateDataKeyWithoutPlainText                     allowed
kms:ListGrants                                          implicitDeny
kms:RevokeGrant                                         implicitDeny
```

The collumn `EVAL_DECISION` shows the result of the evaluation of the Action against the IAM Role Policies. If it's `allowed` means that the IAM Role allows the action to be taken when the client calls the service API.

For the `implicitDeny` means that the action is not allowed for that IAM Role, or it's missing permissions (our case). Let's check the action `kms:CreateGrant`


```bash
$ oc get -n openshift-cloud-credential-operator -o json \
  credentialsrequests openshift-machine-api-aws \
  | jq -r '.spec.providerSpec.statementEntries[]
          | select (.action|any(. =="kms:CreateGrant"))
          | .'
```
```json
{
  "action": [
    "kms:RevokeGrant",
    "kms:CreateGrant",
    "kms:ListGrants"
  ],
  "effect": "Allow",
  "policyCondition": {
    "Bool": {
      "kms:GrantIsForAWSResource": true
    }
  },
  "resource": "*"
}

```

We can see that the `policyCondition` requires a field `kms:GrantIsForAWSResource` to be set.

When calling the service, you should be able to see the required fields on `MissingContextValues`:

```bash
ACTIONS="kms:CreateGrant"
aws iam simulate-principal-policy \
    --policy-source-arn ${MACHINE_API_ROLE_ARN} \
    --action-names "kms:CreateGrant"
```
```json
{
    "EvaluationResults": [
        {
            "EvalActionName": "kms:CreateGrant",
            "EvalResourceName": "*",
            "EvalDecision": "implicitDeny",
            "MatchedStatements": [],
            "MissingContextValues": [
                "kms:GrantIsForAWSResource"
            ],
            "OrganizationsDecisionDetail": {
                "AllowedByOrganizations": true
            }
        }
    ]
}
```

Let's call the simulate policy fixing the fields setting the option `--context-entries`:

```bash
ACTIONS="kms:CreateGrant kms:RevokeGrant kms:ListGrants"
aws iam simulate-principal-policy \
    --policy-source-arn ${MACHINE_API_ROLE_ARN} \
    --action-names ${ACTIONS} \
    --context-entries  "ContextKeyName='kms:GrantIsForAWSResource',ContextKeyValues=true,ContextKeyType=boolean" \
    | jq -r '(["EVAL_ACTION","EVAL_DECISION"] | (., map(length*"-"))),
             (.EvaluationResults[] | [.EvalActionName, .EvalDecision ])
             | @tsv' | column -t
```

The expected results:
```
EVAL_ACTION      EVAL_DECISION
-----------      -------------
kms:CreateGrant  allowed
kms:RevokeGrant  allowed
kms:ListGrants   allowed
```
