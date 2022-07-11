# InvalidIdentityToken when installing OpenShift on AWS using manual authentication mode with STS 

## Issue

- When installing OpenShift on AWS using manual authentication mode with STS, many operators that require credentials with AWS are failing to authenticate to AWS.
- The Machine Controller logs is reporting `InvalidIdentityToken` and `WebIdentityErr` when `AssumeRoleWithWebIdentity`

~~~
$ oc  logs machine-api-controllers-[redacted] -n openshift-machine-api -c machine-controller
(...)
I0704 20:55:07.356052       1 controller.go:175] my-cluster-qntmh-master-0: reconciling Machine
I0704 20:55:07.356106       1 actuator.go:104] my-cluster-qntmh-master-0: actuator checking if machine exists
E0704 20:55:07.782783       1 reconciler.go:266] my-cluster-qntmh-master-0: error getting existing instances: WebIdentityErr: failed to retrieve credentials
caused by: InvalidIdentityToken: Couldn't retrieve verification key from your identity provider,  please reference AssumeRoleWithWebIdentity documentation for requirements
    status code: 400, request id: [redacted]
E0704 20:55:07.782827       1 controller.go:303] my-cluster-qntmh-master-0: failed to check if machine exists: WebIdentityErr: failed to retrieve credentials
caused by: InvalidIdentityToken: Couldn't retrieve verification key from your identity provider,  please reference AssumeRoleWithWebIdentity documentation for requirements
    status code: 400, request id: [redacted]
~~~

- The Image Registry Operator is reporting `InvalidIdentityToken` and `WebIdentityErr` when `AssumeRoleWithWebIdentity`
~~~
$ oc logs pod/cluster-image-registry-operator-[redacted] -n openshift-image-registry
(...)
I0704 21:18:07.603948       1 generator.go:60] object *v1.ClusterOperator, Name=image-registry updated: changed:metadata.resourceVersion={"56299" -> "56307"}, changed:status.conditions.1.message={"Progressing: Unable to apply resources: unable to sync storage configuration: WebIdentityErr: failed to retrieve credentials\nProgressing: caused by: InvalidIdentityToken: Couldn't retrieve verification key from your identity provider,  please reference AssumeRoleWithWebIdentity documentation for requirements\nProgressing: \tstatus code: 400, request id: [redacted]" -> "Progressing: Unable to apply resources: unable to sync storage configuration: WebIdentityErr: failed to retrieve credentials\nProgressing: caused by: InvalidIdentityToken: Couldn't retrieve verification key from your identity provider,  please reference AssumeRoleWithWebIdentity documentation for requirements\nProgressing: \tstatus code: 400, request id: [redacted]"}
~~~

## Environment

- Red Hat OpenShift Container Platform [RHOCP]
  - 4.8+
- Installing the cluster with manual authentication mode in AWS with STS
- AWS Account installing RHOCP does not allow public S3 Buckets or objects

## Resolution

You should replace the URL used for OIDC before creating the cluster. The official and supported solution is not yet delivered and can be followed by [RFE-2898](https://issues.redhat.com/browse/RFE-2898)

There is one option, not yet supported, to use AWS CloudFront Distribution to serve objects on a private S3 Bucket. The steps are described in the upstream project documentation:

- [Choose Option 7b](https://github.com/openshift/cloud-credential-operator/blob/master/docs/sts.md#steps-to-install-an-openshift-cluster-with-sts) when the Steps to install an OpenShift Cluster with STS.
  - Step-by-step by creating ["Short-lived Credentials with AWS Security Token Service using AWS CloudFront and private S3 bucket"](https://github.com/openshift/cloud-credential-operator/blob/master/docs/sts-private-bucket.md).

## Root Cause

OpenID Connect specification requires a public URL (IssuerURL) to store the JSON Web Key Set and configuration. That URL/issuerURL is included on the ProjectedServiceAccountToken, and it's used by the AWS STS service when the method AssumeRolWithWebIdentity is called to assume the IAM Role and get the short-lived credentials. Then the client can use the credentials to authenticate on the service API (EC2, S3, etc).

The `ccoctl` uses the S3 Bucket URL to create the IAM OIDC identity provider, thus the objects stored on the bucket (public keys and OIDC configurations) should be public. Customers who do not want or is not allowed to create public buckets, or public objects, should expose JWKS publically using other solution.

## Diagnostic Steps

The steps below can be reproduced with any component which is using the service account tokens projected to the pod that was created through CredentialsRequests custom resources.

The MachineAPI will be used as an example to diagnose those steps.

1) Check the logs events reporting `InvalidIdentityToken`

~~~
$ oc logs -n openshift-machine-api -c machine-controller machine-api-controllers-[redacted] | grep -c InvalidIdentityToken
23742
~~~

2) Check the CredentialsRequests created to MachineAPI through Cloud Credentials Operators

- Check the CredentialsRequests secret reference:
~~~
$ oc get credentialsrequests openshift-machine-api-aws \
    -n openshift-cloud-credential-operator \
    -o json | jq .spec.secretRef
{
  "name": "aws-cloud-credentials",
  "namespace": "openshift-machine-api"
}
~~~

- Check the secret content:

~~~
$ oc get secrets aws-cloud-credentials \
>     -n openshift-machine-api \
>     -o jsonpath='{.data.credentials}' \
>     | base64 -d
[default]
role_arn = arn:aws:iam::[redacted]:role/my-cluster-openshift-machine-api-aws-cloud-credentials
web_identity_token_file = /var/run/secrets/openshift/serviceaccount/token
~~~

3) Test the credentials

- Get Token path from AWS credentials mounted to a pod

~~~
TOKEN_PATH=$(oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' \
    | base64 -d \
    | grep ^web_identity_token_file \
    | awk '{print$3}')
~~~

- Get the controller's pod

~~~
CAPI_POD=$(oc get pods -n openshift-machine-api \
    -l api=clusterapi \
    -o jsonpath='{.items[*].metadata.name}')
~~~

- Extract token value from the pod

~~~
TOKEN=$(oc exec -n openshift-machine-api \
        -c machine-controller ${CAPI_POD} \
        -- cat ${TOKEN_PATH})
~~~

- Extract the IAM Role ARN from secret

~~~
IAM_ROLE=$(oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' \
    | base64 -d \
    | grep ^role_arn \
    | awk '{print$3}')
~~~

- Assume the IAM Role with the previously extracted token

~~~
$ aws sts assume-role-with-web-identity \
    --role-arn "${IAM_ROLE}" \
    --role-session-name "my-session" \
    --web-identity-token "${TOKEN}"

An error occurred (InvalidIdentityToken) when calling the AssumeRoleWithWebIdentity operation: Couldn't retrieve verification key from your identity provider,  please reference AssumeRoleWithWebIdentity documentation for requirements
~~~


You also can check the `.iss` field of JSON Web Token to check the URL that the OIDC is trying to access, and should be publicly accessible:

~~~
$ echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null | jq .iss
"https://my-cluster-oidc.s3.us-east-1.amazonaws.com"
~~~

Try to get the OIDC configuration:

> Note: it is expected to return `AccessDenied` when you are facing the issue described in this KCS.

~~~
curl -vvv https://my-cluster-oidc.s3.amazonaws.com/.well-known/openid-configuration
~~~
