> Status: WIP
> Preview on [Dev.to]()
> [PR to Collab]()

Hey! o/

Today I will share some options to install store OpenShift in AWS using IAM STS / manual-STS mode.

## Recap

IAM STS is the best way to provide credentials to access AWS resources as it uses short-lived.

When the application which wants to consume AWS services is the other AWS service (EC2, ECS, Lambda, etc) or application running in any AWS service, usually it uses temporary credentials provided by authentication service (EC2 is the metadata services / IMDS) to assume the role and get the temporary credentials from STS.

When the service is external from AWS (example mobile App), or it uses shared resources (like Kubernetes/OpenShift cluster running in EC2) it needs an extra layer of authentication to avoid any application be able to assume the role allowed by the service (example EC2 instance profile).

For that reason there is the managed service IAM OIDC (which implements OpenID spec) to allow from external services federating access to AWS services through STS when assuming the AWS IAM Role.

Basically the Kubernetes API Server uses the private key to sign service account tokens (JWT), the external service uses that token authenticate the STS API call method AssumeRoleWithWebIdentity informing the IAM Role name desired to be assumed, then the STS service access the **OIDC to validate it by accessing the JWTS files stored on the public URL**, once the token is validated, the IAM Role will be assumed with short-lived credentials returned to the service, then the service can authenticate on the target service endpoint API (S3, EC2, etc).

In OpenShift every cluster service that need to interact with AWS has one different token signed by KAS and IAM Role. Example of services:

- Machine API to create EC2
- Image Registry to create S3 Buckets
- CSI to create EBS block storage

Said that, let’s recap the steps to install OpenShift on AWS with manual-STS:

1. create config
2. Set to manual
3. Create the manifests
4. Extract the credentials requests
5. Process it creating the IAM roles
6. Generate the keys
7. Create the bucket
8. Upload the keys
9. Create the OIdC
10. Save the bucket UrL to manifest
11. Install the cluster

## The problem

The endpoint stores the JWKS keys should be public, as the OIDC will access the endpoint available on the JWT token when it is send by STS API call AssumeRoleWithWebIdentity. You can take a look into those items to confirm it:
- Enable the S3 bucket access log
- Filter the events to access the Bucket on the CloudTrail

The main motivation to write this article is that AWS accounts has restrictions on public S3 Bucket, so it needs more options to serve the files accessed by AWS IAM OpenID Connector.

The flow is something like that:

<diagram>

Said that, let me share some options to install a cluster using different approaches that should not impacting in the IAM OIDC managed service requirements.

## Option#0 : default store in public S3 bucket

> TODO

## Option#1: Serve URL using CloudFront, storing in S3 restricted

> TODO

## Option#2: Serve URL with direct Lambda endpoint

> TODO

## Option#3: Serve URL with APIGW, proxying to Lambda function

> TODO

## Option#4: Serve URL with ALB, using Lambda function as target

> TODO

## Option#5: Serve URL direct from hosted webserver  

> TODO

