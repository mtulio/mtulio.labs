# OCP Samples - AWS Sample STSGetCallerID

Steps to create a sample application, providing the AWS credentials (projected service account token), in an OCP cluster installed with STS. 

## Build

- Build container image

```bash
podman build -f ContainerFile -t quay.io/ocp-samples/echo-aws-sts-get-callerid:latest .
podman push quay.io/ocp-samples/echo-aws-sts-get-callerid:latest
```

## Usage

### Pre-requisites

Extract the ccoctl related to the cluster version:

```bash
CCO_IMAGE=$(oc adm release info --image-for='cloud-credential-operator')
oc image extract $CCO_IMAGE --file="/usr/bin/ccoctl" -a ${PULL_SECRET_FILE}
chmod 775 ccoctl
```

Extract the cluster name used to create the initial

> The standard ccoctl deployment uses S3 with public URL, and the URL format: `https://${CLUSTER_NAME}-oidc.s3.${REGION}.amazonaws.com`

```bash
CLUSTER_NAME="$(oc get authentication cluster \
    -o jsonpath='{.spec.serviceAccountIssuer}' \
    | grep -Po '([a-zA-Z-0-9]*)-oidc' \
    | sed 's/-oidc//')"
CLUSTER_REGION="$(oc get infrastructures cluster -o jsonpath={.status.platformStatus.aws.region})"
```

Export the OIDC ARN

```bash
AWS_IAM_OIDP_ARN=$(aws iam list-open-id-connect-providers \
    | jq -r ".OpenIDConnectProviderList[] \
    | select(.Arn | contains(\"${CLUSTER_NAME}-oidc\") ).Arn")
```
Export the Sample App information:

```bash
export APP_NAME="sample-echo-sts"
export APP_NS="sample-sts"
```

### Steps to create the application

- create the namespace

```bash
oc create ns ${APP_NS}
oc project ${APP_NS}
```

- create the credential requests

```bash
mkdir -p ${PWD}/cco-credrequests
cat << EOF > ${PWD}/cco-credrequests/my-app-credentials.yaml
apiVersion: cloudcredential.openshift.io/v1
kind: CredentialsRequest
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NS}
spec:
  providerSpec:
    apiVersion: cloudcredential.openshift.io/v1
    kind: AWSProviderSpec
    statementEntries:
    - action:
      - sts:GetCallerIdentity
      effect: Allow
      resource: '*'
  secretRef:
    name: ${APP_NAME}
    namespace: ${APP_NS}
  serviceAccountNames:
  - ${APP_NAME}
EOF
```

- create the IAM Role

```bash
./ccoctl aws create-iam-roles \
  --name ${CLUSTER_NAME} \
  --region ${CLUSTER_REGION} \
  --credentials-requests-dir ${PWD}/cco-credrequests \
  --identity-provider-arn ${AWS_IAM_OIDP_ARN} \
  --output-dir ${PWD}/cco-credrequests
```

- (optional) check the secret

```bash
$ cat cco-credrequests/manifests/*-credentials.yaml 
apiVersion: v1
stringData:
  credentials: |-
    [default]
    role_arn = arn:aws:iam::[redacted:AWS_ACCOUNT]:role/${CLUSTER_NAME}-${APP_NS}-${APP_NAME}
    web_identity_token_file = /var/run/secrets/openshift/serviceaccount/token
kind: Secret
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NS}
```

- create the secret/credential

```bash
oc create -f ${PWD}/cco-credrequests/manifests/*-credentials.yaml
```

- create the service account

```bash
oc create -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NS}
EOF
```


- create the deployment

```bash
oc create -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NS}
spec:
  selector:
    matchLabels:
      app: ${APP_NAME}
  replicas: 1
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      serviceAccount: ${APP_NAME}
      serviceAccountName: ${APP_NAME}
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - image: quay.io/ocp-samples/echo-aws-sts-get-callerid:latest
        imagePullPolicy: Always
        command:
        - /usr/bin/echo-aws-get-caller-id
        imagePullPolicy: Always
        name: ${APP_NAME}
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        env:
        - name: AWS_ROLE_SESSION_NAME
          value: my-app-session
        - name: AWS_REGION
          value: us-east-1
        - name: AWS_SHARED_CREDENTIALS_FILE
          value: /var/run/secrets/cloud/credentials
        - name: AWS_SDK_LOAD_CONFIG
          value: "1"
        volumeMounts:
        - mountPath: /var/run/secrets/openshift/serviceaccount
          name: bound-sa-token
          readOnly: true
        - mountPath: /var/run/secrets/cloud
          name: aws-credentials
          readOnly: false
      volumes:
      - name: bound-sa-token
        projected:
          defaultMode: 420
          sources:
          - serviceAccountToken:
              audience: openshift
              expirationSeconds: 3600
              path: token
      - name: aws-credentials
        secret:
          defaultMode: 420
          optional: false
          secretName: ${APP_NAME}
EOF
```

### Review the results

Check the logs if the application can call the AWS Service/STS API `GetCallerIdentity`.

The sample Go Application will...

- 1. checks the AWS client config, secret `aws-credentials` generated by ccoctl when processing the `CredentialsRequests`;
- 2. calls the `AssumeRoleWithWebIdentity` sending:
  - A. the bound service account token (JWT) defined on the value of the option `web_identity_token_file`,
  - B. and the IAM Role defined on `role_arn`,
- 3. (background) the service API client will be created with temporary tokens provided by the results of `AssumeRoleWithWebIdentity`
- 4. calls the STS API `GetCallerIdentity` and prints on the pod console logs.
- 5. Sleep for 30 seconds to make another API call.

The console logs also have the connection debug, so you can track the results of each HTTP API call.

Sample of the results:

```bash
$ oc logs sample-echo-sts-75b69465d7-vm6g8
2022/10/13 19:30:34 DEBUG: Request sts/AssumeRoleWithWebIdentity Details:
---[ REQUEST POST-SIGN ]-----------------------------
POST / HTTP/1.1
Host: sts.amazonaws.com
User-Agent: aws-sdk-go/1.44.114 (go1.18.7; linux; amd64)
Content-Length: 1527
Content-Type: application/x-www-form-urlencoded; charset=utf-8
Accept-Encoding: gzip

(...)

-----------------------------------------------------
2022/10/13 19:30:34 DEBUG: Response sts/AssumeRoleWithWebIdentity Details:
---[ RESPONSE ]--------------------------------------
HTTP/1.1 200 OK
Content-Length: 2105
Content-Type: text/xml
Date: Thu, 13 Oct 2022 19:30:34 GMT
X-Amzn-Requestid: [redacted]

(...)

2022/10/13 19:30:34 DEBUG: Request sts/GetCallerIdentity Details:
---[ REQUEST POST-SIGN ]-----------------------------
POST / HTTP/1.1
Host: sts.amazonaws.com
User-Agent: aws-sdk-go/1.44.114 (go1.18.7; linux; amd64)
Content-Length: 43
Authorization: AWS4-HMAC-SHA256 Credential=[redacted]/20221013/us-east-1/sts/aws4_request, SignedHeaders=content-length;content-type;host;x-amz-date;x-amz-security-token, Signature=[redacted]
Content-Type: application/x-www-form-urlencoded; charset=utf-8
X-Amz-Date: 20221013T193034Z
X-Amz-Security-Token: [redacted]
Accept-Encoding: gzip

Action=GetCallerIdentity&Version=2011-06-15

(...)

-----------------------------------------------------
2022/10/13 19:30:34 DEBUG: Response sts/GetCallerIdentity Details:
---[ RESPONSE ]--------------------------------------
HTTP/1.1 200 OK
Content-Length: 484
Content-Type: text/xml
Date: Thu, 13 Oct 2022 19:30:34 GMT
X-Amzn-Requestid: [redacted]

{
  Account: "[redacted:AWS_ACCOUNT]",
  Arn: "arn:aws:sts::[redacted:AWS_ACCOUNT]:assumed-role/${CLUSTER_NAME}-${APP_NS}-${APP_NAME}/1665689434850376494",
  UserId: "[redacted]"
}
Sleeping for 30 seconds...
```

## References

- [Installing an OpenShift Container Platform cluster configured for manual mode with STS](https://docs.openshift.com/container-platform/4.11/authentication/managing_cloud_provider_credentials/cco-mode-sts.html#sts-mode-installing)
- [OCP Blog - IRSA](https://cloud.redhat.com/blog/running-pods-in-openshift-with-aws-iam-roles-for-service-accounts-aka-irsa)
