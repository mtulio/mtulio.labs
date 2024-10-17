# Deploy Karpenter with OpenShift (standalone) on AWS | Day-2

> **NOTE: this document is under development, with critical action items to be addressed before running workloads.**

Steps to deploy Karpenter on OpenShift (HCP) on AWS as Day-2 operation.

Steps:

- [Prerequisites](#prerequisites)
    - [Install OpenShift cluster on AWS (optional)](#install-openshift-cluster-on-aws-optional)
- [Prepare the environment](#prepare-the-environment)
    - [Create deployment variables](#create-deployment-variables)
    - [Deploy Node certificate approver](#deploy-node-certificate-approver)
    - [Setup Credentials](#setup-credentials)
- [Install Karpenter controller](#install-karpenter-controller)
    - [Create configuration](#create-configuration)
    - [Install Karpenter](#install-karpenter)
        - [Apply fixes to fit OpenShift constraints](#apply-fixes-to-fit-openshift-constraints)
- [Using Karpenter on OpenShift](#using-karpenter-on-openshift)
    - [Create NodePool](#creating-the-nodepool)
    - [Create sample workload](#creating-sample-workload)

## Prerequisites

OpenShift cluster installed in the following platform:
- AWS (standalone), tested on 4.18.0-ec.2

Export the variables used in the following steps:

```sh
AWS_PROFILE=openshift-dev
```

### Install OpenShift cluster on AWS (optional)

Skip this section if you have already a cluster installed.

- Create the management cluster - AWS:

```sh
VERSION="4.17.1"
PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64
SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

CLUSTER_NAME=kpt-hcpaws1
REGION=us-east-1
AWS_REGION=$REGION
CLUSTER_BASE_DOMAIN=devcluster.openshift.com
PLATFORM_CONFIG="
  aws:
    region: ${REGION}"

# Extract binary
oc adm release extract \
    --tools quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64 \
    -a ${PULL_SECRET_FILE}

tar xvfz openshift-client-linux-${VERSION}.tar.gz
tar xvfz openshift-install-linux-${VERSION}.tar.gz

# Setup cluster
INSTALL_DIR=${HOME}/openshift-labs/karpenter/${CLUSTER_NAME}
mkdir -p ${INSTALL_DIR} && cd ${INSTALL_DIR}

echo "> Creating install-config.yaml"
mkdir -p ${INSTALL_DIR}
cat <<EOF | envsubst > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${CLUSTER_BASE_DOMAIN}
metadata:
  name: "${CLUSTER_NAME}"
platform: ${PLATFORM_CONFIG}
publish: External
pullSecret: '$(awk -v ORS= -v OFS= '{$1=$1}1' < ${PULL_SECRET_FILE})'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

echo ">> install-config.yaml created: "
cp -v ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config.yaml-bkp

./../openshift-install create cluster --dir $INSTALL_DIR --log-level=debug

export KUBECONFIG=$PWD/auth/kubeconfig
```

### Setting up hosted cluster

#### Installing hypershift

- Install hypershift CLI

```sh
git clone https://github.com/openshift/hypershift.git && cd hypershift
make build
install  -m 0755 bin/hypershift ~/bin/hypershift
```

- Setup bucket for OIDC assets

```sh
export BUCKET_NAME=${CLUSTER_NAME}-hypershift-oidc
aws s3api create-bucket --bucket $BUCKET_NAME
aws s3api delete-public-access-block --bucket $BUCKET_NAME
echo '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}' | envsubst > policy.json
aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://policy.json
```

- Install hypershift controller:

```sh
REGION=us-east-1
BUCKET_NAME=${CLUSTER_NAME}-hypershift-oidc
AWS_CREDS="$HOME/.aws/credentials"

hypershift install \
  --oidc-storage-provider-s3-bucket-name $BUCKET_NAME \
  --oidc-storage-provider-s3-credentials $AWS_CREDS \
  --oidc-storage-provider-s3-region $REGION \
  --enable-defaulting-webhook true

# Check controller
oc get all -n hypershift
```

#### Creating Hostead cluster

- Create a hostead cluster:

```sh
REGION=us-east-1
HOSTED_CLUSTER_NAME=${CLUSTER_NAME}-hc1
BASE_DOMAIN=${CLUSTER_BASE_DOMAIN}
AWS_CREDS="$HOME/.aws/credentials"
PULL_SECRET="$PULL_SECRET_FILE"

hypershift create cluster aws \
  --name ${HOSTED_CLUSTER_NAME} \
  --node-pool-replicas=3 \
  --base-domain $BASE_DOMAIN \
  --pull-secret $PULL_SECRET \
  --aws-creds $AWS_CREDS \
  --region $REGION \
  --ssh-key ${SSH_PUB_KEY_FILE}
```

- Check the cluster information:
```sh
# check the cluster
oc get --namespace clusters hostedclusters
oc get --namespace clusters nodepools
```

- When completed, get the KUBECONFIG

```sh
hypershift create kubeconfig --name ${HOSTED_CLUSTER_NAME} > kubeconfig-${HOSTED_CLUSTER_NAME}
export KUBECONFIG=$PWD/kubeconfig-${HOSTED_CLUSTER_NAME}
```


## Setting up Karpenter in a hosted cluster

### Prerequisites

- Hosted cluster installed and ready
- `KUBECONFIG` environment variable exported with hosted cluster credentials

### Create deployment variables

Export the environment variables used in the steps during this
guide:

```sh
# Export KUBECONFIG for each cluster
KC_MANAGEMENT=${INSTALL_DIR}/auth/kubeconfig
KC_HOSTED=${KUBECONFIG}

# Extract the InfraName (unique cluster name) used to
# prepend resource names.
OCP_INFRA_NAME=$(oc get infrastructures cluster -o jsonpath='{.status.infrastructureName}')

# Extract the AMI ID from the hosted cluster NodePool
# TODO discovery from hypershift
MACHINE_AMI_ID=$(oc --kubeconfig $KC_MANAGEMENT get awsmachines.infrastructure.cluster.x-k8s.io -n clusters-$HOSTED_CLUSTER_NAME -o jsonpath='{.items[0].spec.ami.id}')

MACHINE_USER_DATA=$(oc --kubeconfig $KC_MANAGEMENT get secrets -n clusters-$HOSTED_CLUSTER_NAME -o json | jq -r '.items[] | select(.metadata.name | startswith("user-data")) | .data.value' | base64 -d)

# Karpenter version and helm registry
KARPENTER_NAMESPACE=karpenter
KARPENTER_VERSION=1.0.6
KARPENTER_REGISTRY=oci://public.ecr.aws/karpenter/karpenter
```

Create the multi-document manifest to setup karpenter prerequisites:
```sh
cat << EOF > ./ocp-karpenter-pre-install.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${KARPENTER_NAMESPACE}
  labels:
    pod-security.kubernetes.io/enforce: privileged
EOF
```

### Deploy Node certificate approver

When using OpenShift deployment with integrated components
to managed machines, such as Machine API, it used to ensure
the node certificate signing requests are approved according
to the security constraints.

Karpenter does not provide an official method to approve CSR,
the following example provides a minimum example how to do it
in showing some information of certificate when approving it
automatically:

```sh
cat << EOF >> ./ocp-karpenter-pre-install.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: csr-approver
  namespace: ${KARPENTER_NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: csr-approver
rules:
  - apiGroups: ["certificates.k8s.io"]
    resources: ["certificatesigningrequests"]
    verbs: ["get", "list", "watch", "approve", "update"]
  - apiGroups: ["certificates.k8s.io"]
    resources: ["certificatesigningrequests/approval"]
    verbs: ["update", "create"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["list"]
  - apiGroups: ["certificates.k8s.io"]
    resources: ["signers"]
    resourceNames: ["kubernetes.io/kube-apiserver-client-kubelet", "kubernetes.io/kubelet-serving"]
    verbs: ["approve"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: csr-approver
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: csr-approver
subjects:
  - kind: ServiceAccount
    name: csr-approver
    namespace: ${KARPENTER_NAMESPACE}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: csr-approver
  name: csr-approver
  namespace: ${KARPENTER_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: csr-approver
  strategy: {}
  template:
    metadata:
      labels:
        app: csr-approver
    spec:
      serviceAccountName: csr-approver
      containers:
      - name: csr-approver
        image: image-registry.openshift-image-registry.svc:5000/openshift/tools:latest
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
        env:
          - name: KUBECONFIG
            value: /tmp/kubeconfig
          - name: TOKEN_PATH
            value: /var/run/secrets/kubernetes.io/serviceaccount/token
          - name: CA_PATH
            value: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        command:
        - /bin/bash
        - -c
        - |
          oc login https://kubernetes.default.svc:443 \\
            --token=\$(cat \${TOKEN_PATH}) \\
            --certificate-authority=\${CA_PATH} || true;
          echo "\$(date)> Starting... checking existing nodes...";
          while true; do
            oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' > /tmp/pending-csrs.txt
            if [[ -s /tmp/pending-csrs.txt ]]; then
              echo "\$(date)> Found CSRs to approve:";
              cat /tmp/pending-csrs.txt
              for csr in \$(cat /tmp/pending-csrs.txt); do \\
                echo "\$(date)> Approving CSR \${csr}"; \\
                oc get csr \${csr} -o json | jq -cr '. | [.metadata.name, .spec.signerName, .spec.username]'; \\
                oc adm certificate approve \${csr}; \\
              done
            fi
            sleep 10
          done
EOF
```

### Setup Credentials

Karpenter supports different authentication methods, such as
short-lived tokens, manual IAM User, etc.

The example below will create an IAM User created by
CCO using mint mode.

- Create the CredentialsRequest:

> Source: https://raw.githubusercontent.com/aws/karpenter-provider-aws/refs/heads/main/website/content/en/v1.0/getting-started/getting-started-with-karpenter/cloudformation.yaml

> TODO: review policies according to the Karpenter-provided cloudformation template on v1.0

```sh
cat << EOF >> ./ocp-karpenter-pre-install.yaml
---
apiVersion: cloudcredential.openshift.io/v1
kind: CredentialsRequest
metadata:
  name: karpenter-aws
  namespace: openshift-cloud-credential-operator
spec:
  providerSpec:
    apiVersion: cloudcredential.openshift.io/v1
    kind: AWSProviderSpec
    statementEntries:
    # TODO: refine the permissions provided by the karpenter. Ref:
    # https://raw.githubusercontent.com/aws/karpenter-provider-aws/refs/heads/main/website/content/en/v1.0/getting-started/getting-started-with-karpenter/cloudformation.yaml
    - action:
      - "ssm:GetParameter"
      - "ec2:DescribeImages"
      - "ec2:RunInstances"
      - "ec2:DescribeSubnets"
      - "ec2:DescribeSecurityGroups"
      - "ec2:DescribeLaunchTemplates"
      - "ec2:DescribeInstances"
      - "ec2:DescribeInstanceTypes"
      - "ec2:DescribeInstanceTypeOfferings"
      - "ec2:DescribeAvailabilityZones"
      - "ec2:DeleteLaunchTemplate"
      - "ec2:CreateTags"
      - "ec2:CreateLaunchTemplate"
      - "ec2:CreateFleet"
      - "ec2:DescribeSpotPriceHistory"
      - "pricing:GetProducts"
      - "sqs:DeleteMessage"
      - "sqs:GetQueueUrl"
      - "sqs:ReceiveMessage"
      - "iam:GetInstanceProfile"
      effect: Allow
      resource: '*'
    - action:
      - ec2:TerminateInstances
      effect: Allow
      # TODO create conditional for karpenter
      resource: '*'
      policyCondition:
        StringLike:
          "ec2:ResourceTag/Name": "*karpenter*"
    - action:
      - "iam:PassRole"
      effect: Allow
      # TODO create conditional for IAM Worker or Master role
      resource: '*'
  secretRef:
    name: karpenter-aws-credentials
    namespace: ${KARPENTER_NAMESPACE}
  serviceAccountNames:
  - karpenter
EOF
```

Apply the manifest bundle with prerequisites to install
Karpenter on OpenShift:

```sh
oc apply -f ./ocp-karpenter-pre-install.yaml
```

## Install Karpenter controller

### Create configuration

- Create karpenter configuration by setting helm values file:

> Documentation/options: https://github.com/aws/karpenter-provider-aws/blob/release-v1.0.6/charts/karpenter/README.md

> Deployment template: https://github.com/aws/karpenter-provider-aws/blob/main/charts/karpenter/templates/deployment.yaml


```sh
cat << EOF > ./ocp-karpenter-helm-values.yaml
aws:
  defaultInstanceProfile: ${OCP_INFRA_NAME}
settings:
  clusterName: ${OCP_INFRA_NAME}
  #interruptionQueue: ${OCP_INFRA_NAME}
  clusterEndpoint: https://kubernetes.default.svc:443
tolerations:
  - key: "node-role.kubernetes.io/master"
    operator: "Exists"
    effect: "NoSchedule"
controller:
  env:
    - name: LOG_LEVEL
      value: debug
    - name: AWS_REGION
      value: ${AWS_REGION}
    - name: AWS_SHARED_CREDENTIALS_FILE
      value: /var/secrets/karpenter/credentials
    - name: CLUSTER_ENDPOINT
      value: https://kubernetes.default.svc:443
  extraVolumeMounts:
    - name: credentials
      readOnly: true
      mountPath: "/var/secrets/karpenter"
extraVolumes:
  - name: credentials
    secret:
      secretName: karpenter-aws-credentials
podSecurityContext:
  fsGroup: 1000710000
EOF
```

!!! info "Tip 💡"
    Save the rendered manifests alongside the `*-values.yaml`
    running:

    ```sh
    helm template karpenter ${KARPENTER_REGISTRY} \
      --namespace ${KARPENTER_NAMESPACE} --debug \
      --version ${KARPENTER_VERSION} \
      -f ./ocp-karpenter-helm-values.yaml \
      >> ./ocp-karpenter-helm-manifests.yaml
    ```

- Save the `*-values.yaml` and the `*-manifests.yaml` if you want to keep it versioned.



### Install Karpenter

- Deploy Karpenter controller:

```sh
helm upgrade --install karpenter ${KARPENTER_REGISTRY} \
  --namespace ${KARPENTER_NAMESPACE} --debug \
  --version ${KARPENTER_VERSION} \
  -f ./ocp-karpenter-helm-values.yaml
```


### Apply fixes to fit OpenShift constraints

```sh
# Patch 1) SecurityContext
# Its required as karpenter does not provide interface to customize securityContext for container, only for pod and it's not enough:
# https://github.com/aws/karpenter-provider-aws/blob/main/charts/karpenter/templates/deployment.yaml#L59-L71
oc patch deployment.apps/karpenter -n ${KARPENTER_NAMESPACE} \
  --type=json --patch '[
    {"op": "remove", "path": "/spec/template/spec/securityContext"},
    {"op": "remove", "path": "/spec/template/spec/containers/0/securityContext"}]'

# Patch 2) RBAC
oc patch clusterrole karpenter --type=json -p '[{
    "op": "add",
    "path": "/rules/-",
    "value": {"apiGroups":["karpenter.sh"], "resources": ["nodeclaims","nodeclaims/finalizers", "nodepools","nodepools/finalizers"], "verbs": ["create","update","delete","patch"]}
  }]'
```

- Patch 3) IAM: TODO: credentialsrequest is not working in hosted cluster (need to check good practice). Duplicating creds from mgt to hosted

```sh
oc --kubeconfig $KC_MANAGEMENT get secret aws-creds -n kube-system -o yaml | sed 's/namespace: kube-system/namespace: karpenter/' | sed 's/name: aws-creds/name: karpenter-aws-credentials/' | oc --kubeconfig $KC_HOSTED apply -n karpenter -f -

$ oc get pods -w -n karpenter

# Manual change: create 'credentials' key inside the secret
```

## Using Karpenter on OpenShift

### Create NodePool

Create the NodePool according to your needs. You can revisit
the Karpenter documentation to customized according to your
environment.

The example below will create a `default` NodePool filtering
instances well-known instances for OpenShift in 5th generation
or newer.

A `EC2NodeClass` object `default` is created with
details of AWS environment which the cluster has been deployed,
and compute nodes based on MachineSet objects.

```sh
cat <<EOF | envsubst | oc apply -f -
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
  namespace: karpenter
spec:
  template:
    metadata:
      labels:
        Environment: karpenter
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["5"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      nodeLabels:
        karpenterNodePool: default
      startupTaints:
        - key: karpenter.sh/unregistered
          effect: NoExecute
      expireAfter: 720h # 30 * 24h = 720h
  limits:
    cpu: "40"
    memory: 160Gi
  weight: 10
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 10m
---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
  namespace: karpenter
spec:
  amiFamily: Custom
  amiSelectorTerms:
    - id: "${MACHINE_AMI_ID}"
  instanceProfile: "${OCP_INFRA_NAME}-worker"
  subnetSelectorTerms:
    - tags:
        kubernetes.io/cluster/${OCP_INFRA_NAME}: "owned"
        kubernetes.io/role/internal-elb: "1"
  securityGroupSelectorTerms:
    - tags:
        Name: "${OCP_INFRA_NAME}-default-sg"
  tags:
    Name: "${OCP_INFRA_NAME}-compute-karpenter"
    Environment: karpenter
  userData: |
    ${MACHINE_USER_DATA}
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
        deleteOnTermination: true
  associatePublicIPAddress: false
EOF
```
https://github.com/aws/karpenter-provider-aws/issues/6821#issuecomment-2302488038
https://karpenter.sh/docs/upgrading/v1-migration/#changes-required-before-upgrading-to-v100

oc adm taint node ip-10-0-136-235.ec2.internal karpenter.sh/unregistered=true:NoExecute


### Create sample workload

Create an empty pod to allow to inflate the pending pods,
forcing the Karpenter to launch new nodes.

```sh
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 0
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    selector:
      matchLabels:
        Environment: karpenter
        karpenter.sh/capacity-type: spot
    spec:
      terminationGracePeriodSeconds: 0
      containers:
      - name: inflate
        image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        resources:
          requests:
            cpu: 1
        securityContext:
          allowPrivilegeEscalation: false
EOF
```



Scale the deployment and observe the karpenter in action:

```sh
# Scale up the deployment
oc scale deployment inflate --replicas 50

# Pending pods
oc get pods --all-namespaces --field-selector=status.phase=Pending

# Karpenter controler logs
oc logs -f -n karpenter -l app.kubernetes.io/name=karpenter -c controller

# Karpenter NodeClaim
oc get NodeClaims -n karpenter

# Certificates must be automatically approved
oc get csr

# Nodes
oc get nodes -w
```


Existing Issues:

1) NodeClaim object for EC2 is never becoming ready:

The Ec2 is created, booted, joined to cluster, but it is being replaced
to another EC2 by Karpenter due karpenter initialization error.

Karpenter NodeClaims' nodes are never becaming ready raising the
following error in controller:

> Note: the related taint has been added to `startupTaint` to the NodePool.

```json
{"level":"ERROR","time":"2024-10-17T03:49:18.849Z","logger":"controller","caller":"controller/controller.go:261","message":"Reconciler error","commit":"6174c75","controller":"nodeclaim.lifecycle","controllerGroup":"karpenter.sh","controllerKind":"NodeClaim","NodeClaim":{"name":"default-68qvg"},"namespace":"","name":"default-68qvg","reconcileID":"08ac905e-eac8-4f15-9a4c-dc8298cf828e","error":"missing required startup taint, karpenter.sh/unregistered"}
```



END
------>> Not working:


### Setting up hosting cluster (multicluster engine Operator) (not working)

References:

- Product documentation: https://docs.openshift.com/container-platform/4.17/hosted_control_planes/index.html

- Install HCP: https://docs.openshift.com/container-platform/4.17/hosted_control_planes/hcp-prepare/hcp-cli.html

- https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.11/html/clusters/cluster_mce_overview#installing-from-the-operatorhub-mce

Steps:

- Download HCP CLI:

```sh
version=2.6.3-8
file=hcp-cli-${version}-linux-amd64.tar.gz
wget https://developers.redhat.com/content-gateway/file/pub/mce/clients/hcp-cli/${version}/${file}
tar xfz ${file} -C /tmp
chmod +x /tmp/hcp
mv /tmp/hcp ~/bin/hcp
```

- Install Multicluster Engine Operator
 > Not working
```sh
cat << EOF | oc apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: multicluster-engine
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: multicluster-engine
  namespace: multicluster-engine
spec:
  targetNamespaces:
  - multicluster-engine
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: multicluster-engine
  namespace: multicluster-engine
spec:
  sourceNamespace: openshift-marketplace
  source: redhat-operators
  channel: stable-2.3
  installPlanApproval: Automatic
  name: multicluster-engine
EOF

---
apiVersion: multicluster.openshift.io/v1
kind: MultiClusterEngine
metadata:
  name: multiclusterengine
  namespace: mce
spec: {}

# Check if operators are running
```

- Deploy the ClusterManager

```sh

```

- Create the workload cluster - AWS:

> HCP documentation (not working, operator is not availbale in the OperatorHub)

## Draft karpenter using OLM

```sh
cat << EOF > karpenter.old.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: karpenter
---
apiVersion: apps.open-cluster-management.io/v1
kind: Channel
metadata:
  name: karpenter-helmrepo
  namespace: karpenter
spec:
    type: HelmRepo
    pathname: oci://public.ecr.aws/karpenter/karpenter
    configRef: 
      name: skip-cert-verify
      apiVersion: v1
      kind: ConfigMap
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: skip-cert-verify
  namespace: karpenter
data:
  insecureSkipVerify: "true"

---
apiVersion: apps.open-cluster-management.io/v1
kind: Subscription
metadata:
  name: karpenter-helm
spec:
  channel: dev/dev-helmrepo
  name: karpenter
  placement:
    local: false
  packageFilter:
    version: "1.0.6"
  packageOverrides:
  - packageName: karpenter
    packageAlias: karpenter
    packageOverrides:
    - path: spec
      value:
        defaultBackend:
          replicaCount: 3
  overrides:
  - clusterName: "/"
    clusterOverrides:
    - path: "metadata.namespace"
      value: karpenter
EOF

kubectl patch subscriptions.apps.open-cluster-management.io karpenter-helm --type='json' -p='[{"op": "replace", "path": "/spec/placement/local", "value": true}]'
```
