# OpenShift Spikes | Installing ALBC

## Installing ALBC

Instructions to install AWS Load Balancer Controller (ALBC) on OpenShift using different options:
- AWS Load Balancer Operator (ALBO)
- Helm

### Installing ALBC with helm


```sh
helm repo add eks https://aws.github.io/eks-charts
#helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=<cluster-name>



cat << EOF| oc apply -f -
apiVersion: cloudcredential.openshift.io/v1
kind: CredentialsRequest
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
spec:
  providerSpec:
    apiVersion: cloudcredential.openshift.io/v1
    kind: AWSProviderSpec
    statementEntries:
      - action:
          - ec2:DescribeSubnets
        effect: Allow
        resource: "*"
      - action:
          - ec2:CreateTags
          - ec2:DeleteTags
        effect: Allow
        resource: arn:aws:ec2:*:*:subnet/*
      - action:
          - ec2:DescribeVpcs
        effect: Allow
        resource: "*"
      - action:
          - "*"
        effect: Allow
        resource: "*"
  secretRef:
    name: aws-load-balancer-controller
    namespace: kube-system
  serviceAccountNames:
    - aws-load-balancer-controller
EOF

# create SA

cat << EOF| oc create -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
    app.kubernetes.io/instance: aws-load-balancer-controller
    app.kubernetes.io/version: "v2.13.4"
automountServiceAccountToken: true
EOF


CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag-key,Values=kubernetes.io/cluster/${CLUSTER_ID}" --query Vpcs[].VpcId --output text)


helm template aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
--set clusterName=$CLUSTER_ID \
--set serviceAccount.create=false \
--set serviceAccount.name=aws-load-balancer-controller \
--set region=us-east-1 \
--set vpcId=$VPC_ID \
| oc apply -f -


oc create -f albc-ocp-helm.yaml 



cat << EOF > ./albc-values.yam
affinity:
  node-role.kubernetes.io/master: ''
enableServiceMutatorWebhook: false
vpcId: $VPC_ID
clusterName: $CLUSTER_ID
serviceAccount:
  create: false
  name: aws-load-balancer-controller

extraVolumes:
  - name: aws-credentials
    secret:
      secretName: aws-load-balancer-controller

extraVolumeMounts:
- mountPath: /aws
  name: aws-credentials

env:
  AWS_DEFAULT_REGION: us-east-1
  AWS_SHARED_CREDENTIALS_FILE: /aws/credentials

EOF

# Helm is not following the config enableServiceMutatorWebhook and deploying the webhook, leading to failures on controllers (TODO review). We are patching to ensure.
helm template aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
--values ./albc-values.yam \
| yq4 e 'select( .kind != "MutatingWebhookConfiguration" and .kind != "ValidatingWebhookConfiguration" and .metadata.name != "aws-load-balancer-webhook-service" )' - \
| oc apply -f -



# creating sample svc

SVC_NAME=$APP_NAME_BASE-albc-lat0
cat << EOF | oc create -f -
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
  namespace: ${APP_NAMESPACE}
spec:
  selector:
    app: $APP_NAME_BASE
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  type: LoadBalancer
  loadBalancerClass: service.k8s.aws/nlb
EOF
```


### Installing ALBC with ALBO


```sh
# Create the Credentials for the Operator:
ALBO_NS=aws-load-balancer-operator
oc create namespace $ALBO_NS

cat << EOF| oc create -f -
apiVersion: cloudcredential.openshift.io/v1
kind: CredentialsRequest
metadata:
  name: aws-load-balancer-operator
  namespace: openshift-cloud-credential-operator
spec:
  providerSpec:
    apiVersion: cloudcredential.openshift.io/v1
    kind: AWSProviderSpec
    statementEntries:
      - action:
          - ec2:DescribeSubnets
        effect: Allow
        resource: "*"
      - action:
          - ec2:CreateTags
          - ec2:DeleteTags
        effect: Allow
        resource: arn:aws:ec2:*:*:subnet/*
      - action:
          - ec2:DescribeVpcs
        effect: Allow
        resource: "*"
  secretRef:
    name: aws-load-balancer-operator
    namespace: aws-load-balancer-operator
  serviceAccountNames:
    - aws-load-balancer-operator-controller-manager
EOF

# Install the Operator from OLM:
cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: $ALBO_NS
  namespace: $ALBO_NS
spec:
  targetNamespaces:
  - $ALBO_NS
EOF

# Create the subscription:
cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: $ALBO_NS
  namespace: $ALBO_NS
spec:
  channel: stable-v0
  installPlanApproval: Automatic 
  name: $ALBO_NS
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Wait for install-plan approved
oc get installplan -w -n $ALBO_NS

# check controller is running
oc get all -n $ALBO_NS
oc get pods -w -n $ALBO_NS


# Create cluster ALBO controller
cat <<EOF | oc create -f -
apiVersion: networking.olm.openshift.io/v1alpha1
kind: AWSLoadBalancerController 
metadata:
  name: cluster 
spec:
  subnetTagging: Auto 
  ingressClass: cloud 
  config:
    replicas: 2 
  enabledAddons: 
    - AWSWAFv2
EOF

# Wait for the pod becamig running
oc get pods -w -n $ALBO_NS -l app.kubernetes.io/name=aws-load-balancer-operator
```
