# OCP Samples - AWS Sample STSGetCallerID

Steps to create sample application with AWS credentials in an OCP cluster installed with STS. 

## Build

- Build container image

```bash
podman build -f ContainerFile -t quay.io/ocp-samples/echo-aws-sts-get-callerid:latest .
podman push quay.io/ocp-samples/echo-aws-sts-get-callerid:latest
```

## Usage

### Pre-requisites

Extract the ccoctl related to the cluster vesion:

```bash
RELEASE_IMAGE=$(oc get clusterversion version -o jsonpath='{.status.desired.image}')
CCO_IMAGE=$(oc adm release info --image-for='cloud-credential-operator')
oc image extract $CCO_IMAGE --file="/usr/bin/ccoctl" -a ${PULL_SECRET_FILE}
chmod 775 ccoctl
```

Extract the cluster name used to create the inital

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


### Steps

- create the namespace

```bash
oc create ns my-namespace
```

- create the credential requests

```bash
mkdir -p ${PWD}/cco-credrequests
cat << EOF > ${PWD}/cco-credrequests/my-app-credentials.yaml
apiVersion: cloudcredential.openshift.io/v1
kind: CredentialsRequest
metadata:
  name: my-app-credentials
  namespace: my-namespace
spec:
  providerSpec:
    apiVersion: cloudcredential.openshift.io/v1
    kind: AWSProviderSpec
    statementEntries:
    - action:
      - sts:GetCallerIdentity
      - sts:AssumeRoleWithWebIdentity
      effect: Allow
      resource: '*'
  secretRef:
    name: my-app-credentials
    namespace: my-namespace
  serviceAccountNames:
  - my-serviceaccount-token
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
  name: my-app-credentials
  namespace: my-namespace
EOF
```


- create the deployment

```bash
oc create -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-namespace
spec:
  selector:
    matchLabels:
      app: my-app
  replicas: 1
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: my-app-credentials
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - image: quay.io/ocp-samples/echo-aws-sts-get-callerid:latest
        imagePullPolicy: Always
        #command:
        #- /usr/bin/echo-aws-get-caller-id
        command: [ "/bin/sh", "-c", "--" ]
        args: [ "while true; do echo 'sleeping...'; sleep 30; done;" ]
        imagePullPolicy: Always
        name: my-app
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
          secretName: my-app-credentials
EOF
```

- Check the logs


## References

- [OCP Blog - IRSA](https://cloud.redhat.com/blog/running-pods-in-openshift-with-aws-iam-roles-for-service-accounts-aka-irsa)
