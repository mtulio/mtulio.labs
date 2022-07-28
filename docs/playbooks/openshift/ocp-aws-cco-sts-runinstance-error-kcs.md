# OCP on AWS - Troubleshooting RunInstance Error

> KCS URL: https://access.redhat.com/solutions/6969704

Red Hat OpenShift Container Platform Machine Failed with error launching instance: You are not authorized to perform this operation

## Issue

- The Machine creation is stuck in Failed phase with `Error Message`: `error launching instance: You are not authorized to perform this operation` (without an encoded error message when running the cluster using service endpoints)

~~~
$ oc describe machines -n openshift-machine-api ${MACHINE_NAME} |grep 'Error Message:'
  Error Message:           error launching instance: You are not authorized to perform this operation.
~~~

- The Machine creation is stuck in Failed phase with `Error Message`: `error launching instance: You are not authorized to perform this operation` (with an encoded error message)

~~~
$ ENCODED_ERROR_MESSAGE=$(oc describe machines -n openshift-machine-api ${MACHINE_NAME} |grep 'Error Message:' | awk -F'failure message: ' '{print$2}')
$ oc describe machines -n openshift-machine-api ${MACHINE_NAME} |grep 'Error Message:'
  Error Message:           error launching instance: You are not authorized to perform this operation. Encoded authorization failure message: ${ENCODED_ERROR_MESSAGE}
~~~

- The decoded error message shows that the permissions used by Machine API are not allowed to run the action `ec2:RunInstances`


## Environment

- Red Hat OpenShift Container Platform (RHOCP)
    - 4.x
- Amazon Web Services (AWS)
    - IAM service
- Authentication Mode: manual with STS

## Resolution

Check if there isn't any policy blocking or missing any required action defined on the `CredentialsRequests`. The following AWS services should be checked:

1) When using [Service Endpoints](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-customizations.html#installation-configuration-parameters-optional-aws_installing-aws-customizations) (install config field: `platform.aws.serviceEndpoints`): check if the existing VPC Endpoints for EC2 has the correct actions on the policy document, otherwise, you will have connectivity issues to reach the API services as it's blocked by Service Endpoint, thus the **encoded message will not be provided** on the `Error Message` when troubleshooting the pod of Machine API Controllers

2) Check the Policies attached to the IAM Role `${cluster_name}-openshift-machine-api-aws-cloud-credentials` has all the required permissions defined on the `CredentialsRequests`

3) Check if the IAM Role `${cluster_name}-openshift-machine-api-aws-cloud-credentials` hasn't [permissions boundary policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html) denying any required permissions defined on the `CredentialsRequests`, or any expression matching it

4) Check if the AWS Account hasn't any [Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html) attached to the Organizations' structure, where the account belongs, that could deny any actions defined on the `CredentialsRequests`


## Root Cause

Some possibilities could block the actions required for Machine API:

1) The EC2 endpoint policy for the VPC Endpoint is missing permissions

When the cluster is installed in a [private](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-private.html), [restricted](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-restricted-networks-aws-installer-provisioned.html) or [customized](https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-customizations.html) environment using the [AWS VPC PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-access-aws-services.html) with VPC endpoints, the ec2 endpoint policies should allow the API calls to the EC2 service and dependencies, like IAM, otherwise, the requests will not reach the required API and fail on the client side. The error message should look like this - without encoded error message as the service API can't be reached:

<!---
> NOTE: Steps to reproduce: A) Create one VPC, and VPC endpoints with "allow all policies"; B) Install an OCP cluster in an existing VPC setting the service endpoint on install-config.yaml `platform.aws.serviceEndpoints`; C) Wait for the cluster to be finished successfully; D) Change the VPC Endpoint policy to explicitly DENY all actions; E) Create a new machine/machineset, and check the phase
--->

~~~
$ oc describe machine   -n openshift-machine-api $MACHINE_NAME |grep 'Error Message:'
  Error Message:           error launching instance: You are not authorized to perform this operation.
~~~


2) Missing permissions on the IAM Role, in general named as `${cluster_name}-openshift-machine-api-aws-cloud-credentials`:

The Policy document attached to the IAM Role used by Machine API has incorrect permissions, not allowing to perform `ec2:RunInstances`, or equivalent, action to Machine API creates the Machine on the cloud provider.

The error message should look like this:

~~~
$ oc describe machines -n openshift-machine-api ${MACHINE_NAME} |grep 'Error Message:'
  Error Message:           error launching instance: You are not authorized to perform this operation. Encoded authorization failure message: ${ENCODED_ERROR_MESSAGE}
~~~

The fields below on the decoded error message should be checked:

- `allowed` should be set to `false`
- `explicitDeny` should be set to `false`, as the error is missing the explicit "Allow" for `ec2:RunInstances` on the policy document

The decoded error message looks like this:

~~~
{
  "allowed": false,
  "explicitDeny": false,
  "matchedStatements": {
    "items": []
  },
  "failures": {
    "items": []
  },
  "context": {
    "principal": {
      "id": "AROAT[redacted]:[redacted:session_name]",
      "arn": "arn:aws:sts::[redacted:account_id]:assumed-role/[redacted:cluster_id]-openshift-machine-api-aws-cloud-credentials/[redacted:session_name]"
    },
    "action": "ec2:RunInstances",
    "resource": "arn:aws:ec2:us-east-1:[redacted:account_id]:instance/*",
    "conditions": {
(...)
    }
  }
}
~~~

3) [Permissions Boundary](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html) policies for the IAM Role denying required actions:

The permissions boundary is used to set the maximum permissions that an identity-based policy can grant to an IAM entity, or not have. It's not a common configuration, for example, when the `ec2:RunInstances` is explicitly denied on the permissions boundary policies, the Machine API will not be able to run the RunInstances EC2 API operation to create the machines.

The fields below on the decoded error message should be checked:

- `explicitDeny` should be set to `true`
- `matchedStatements` should have the policy definition that matched the action defined on the `context.action` with the denied statement

The decoded error message looks like this:

~~~
{
  "allowed": false,
  "explicitDeny": true,
  "matchedStatements": {
    "items": [
      {
        "statementId": "",
        "effect": "DENY",
        "principals": {
          "items": [
            {
              "value": "SCOPE_POLICY_ISSUER"
            }
          ]
        },
        "principalGroups": {
          "items": []
        },
        "actions": {
          "items": [
            {
              "value": "ec2:RunInstances"
            }
          ]
        },
        "resources": {
          "items": [
            {
              "value": "*"
            }
          ]
        },
        "conditions": {
          "items": []
        }
      }
    ]
  },
  "failures": {
    "items": []
  },
  "context": {
    "principal": {
      "id": "AROAT[redacted]:[redacted:session_name]",
      "arn": "arn:aws:sts::[redacted:account_id]:assumed-role/[redacted:cluster_id]-openshift-machine-api-aws-cloud-credentials/[redacted:session_name]"
    },
    "action": "ec2:RunInstances",
    "resource": "arn:aws:ec2:us-east-1:[redacted:account_id]:instance/*",
    "conditions": {
(...)
    }
  }
}
~~~

4) Explicitly Deny with [Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html) on the [AWS Organizations](https://aws.amazon.com/organizations/) structure

Service control policies (SCPs) are a type of organization policy that you can use to manage permissions in your organization. SCPs offer central control over the maximum available permissions for all accounts in your organization.

When the SCP is applied to the AWS Account running OCP with an explicitly deny of `ec2:RunInstances`, or any expression matching required permissions, the Machine API will not be able to run the RunInstances EC2 API operation to create the machines.

The decoded error message looks like this:

~~~
{
  "allowed": false,
  "explicitDeny": true,
  "matchedStatements": {
    "items": [
      {
        "statementId": "Statement1",
        "effect": "DENY",
        "principals": {
          "items": [
            {
              "value": "[redacted]"
            }
          ]
        },
        "principalGroups": {
          "items": []
        },
        "actions": {
          "items": [
            {
              "value": "ec2:RunInstances"
            }
          ]
        },
        "resources": {
          "items": [
            {
              "value": "*"
            }
          ]
        },
        "conditions": {
          "items": []
        }
      }
    ]
  },
  "failures": {
    "items": []
  },
  "context": {
    "principal": {
      "id": "[redacted]:[redacted:user]",
      "arn": "arn:aws:sts::[redacted]:assumed-role/[redacted:sso_user_role_name]/[redacted:user]"
    },
    "action": "ec2:RunInstances",
    "resource": "arn:aws:ec2:us-east-1:[redacted:account_id]:instance/*",
    "conditions": {
(...)
    }
  }
}
~~~

## Diagnostic Steps

- Check the Machines and note the name on the failed phase:

~~~
$ oc get machines -n openshift-machine-api
~~~

- Check the `Error Message` of the Failed machine:

~~~
$ oc describe machine $MACHINE_NAME -n openshift-machine-api
# or filter directly the error field
$ oc describe machine $MACHINE_NAME -n openshift-machine-api |grep 'Error Message:'
~~~

- When the Error message has the encoded failed message provided by AWS, get the encoded message and decode it:

~~~
$ ENCODED_ERROR_MESSAGE=$(oc describe machines -n openshift-machine-api $MACHINE_NAME |grep 'Error Message:' | awk -F'failure message: ' '{print$2}')

$ echo $(aws sts decode-authorization-message --encoded-message $ENCODED_ERROR_MESSAGE | jq -r .DecodedMessage) |jq .
~~~

- Check the required permissions for MachineAPI defined on the `CredentialsRequests`:

~~~
$ oc get -n openshift-cloud-credential-operator \
    credentialsrequests openshift-machine-api-aws
~~~

- Run the [Policy Simulator](https://docs.aws.amazon.com/IAM/latest/APIReference/API_SimulatePrincipalPolicy.html) using [AWS CLI](https://docs.aws.amazon.com/cli/latest/reference/iam/simulate-principal-policy.html) or [AWS Console](https://policysim.aws.amazon.com/home/index.jsp) to check if the IAM Role has enough permissions as required on the `CredentialsRequests`:

~~~
$ ACTIONS=$(oc get -n openshift-cloud-credential-operator -o json  \
        credentialsrequests openshift-machine-api-aws \
        | jq -r '.spec.providerSpec.statementEntries[].action[]' \
        | sort -u | tr '\n' ' ')

$ MACHINE_API_ROLE_ARN=$(oc get secrets aws-cloud-credentials \
        -n openshift-machine-api \
        -o jsonpath='{.data.credentials}' |\
        base64 -d |\
        grep ^role_arn |\
        awk '{print$3}')

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

# Fix the KMS actions that require parameters:
$ ACTIONS="kms:CreateGrant kms:RevokeGrant kms:ListGrants"
$ aws iam simulate-principal-policy \
    --policy-source-arn ${MACHINE_API_ROLE_ARN} \
    --action-names ${ACTIONS} \
    --context-entries  "ContextKeyName='kms:GrantIsForAWSResource',ContextKeyValues=true,ContextKeyType=boolean" \
    | jq -r '(["EVAL_ACTION","EVAL_DECISION"] | (., map(length*"-"))),
             (.EvaluationResults[] | [.EvalActionName, .EvalDecision ])
             | @tsv' | column -t

EVAL_ACTION      EVAL_DECISION
-----------      -------------
kms:CreateGrant  allowed
kms:RevokeGrant  allowed
kms:ListGrants   allowed
~~~
