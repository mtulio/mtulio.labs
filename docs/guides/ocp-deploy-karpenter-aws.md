# Deploy Karpenter with OpenShift (standalone) on AWS | Day-2

Steps to deploy Karpenter on OpenShift (standalone) on AWS as Day-2 operation.

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

- Install on AWS:

```sh
VERSION="4.18.0-ec.2"
PULL_SECRET_FILE="${HOME}/.openshift/pull-secret-latest.json"
RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:${VERSION}-x86_64
SSH_PUB_KEY_FILE=$HOME/.ssh/id_rsa.pub

CLUSTER_NAME=kpt-aws3
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
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

echo ">> install-config.yaml created: "
cp -v ${INSTALL_DIR}/install-config.yaml ${INSTALL_DIR}/install-config.yaml-bkp

./../openshift-install create cluster --dir $INSTALL_DIR --log-level=debug

export KUBECONFIG=$PWD/auth/kubeconfig
```

## Prepare the environment

Prepare the OpenShift cluster to install Karpenter.

### Create deployment variables

Export the environment variables used in the steps during this
guide:

```sh
# Extract the InfraName (unique cluster name) used to
# prepend resource names.
OCP_INFRA_NAME=$(oc get infrastructures cluster -o jsonpath='{.status.infrastructureName}')

# Select one base MachineSet to extract information to compose
# the pool configuration when creating the Karpenter EC2NodeClass
MACHINESET_AMI_ID=$(oc get machinesets -n openshift-machine-api \
  -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}')

# Extracts the user data value of the compute pool from MachineAPI secret.
MACHINESET_USER_DATA=$(oc get secret -n openshift-machine-api worker-user-data -o jsonpath='{.data.userData}' | base64 -d)

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

- Review controller:

```sh
oc get all -n ${KARPENTER_NAMESPACE}
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
    - id: "${MACHINESET_AMI_ID}"
  instanceProfile: "${OCP_INFRA_NAME}-worker-profile"
  subnetSelectorTerms:
    - tags:
        kubernetes.io/cluster/${OCP_INFRA_NAME}: "owned"
        kubernetes.io/role/internal-elb: "1"
  securityGroupSelectorTerms:
    - tags:
        Name: "${OCP_INFRA_NAME}-node"
    - tags:
        Name: "${OCP_INFRA_NAME}-lb"
  tags:
    Name: "${OCP_INFRA_NAME}-compute-karpenter"
    #kubernetes.io/cluster/${OCP_INFRA_NAME}: "owned"
    Environment: karpenter
  userData: |
    ${MACHINESET_USER_DATA}
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
        deleteOnTermination: true
  associatePublicIPAddress: false
EOF
```

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

Where:

- `spec.template.selector.matchLabels`: defines the matching criteria to trigger
  the Karpenter autoscaler `Environment=karpenter`, the
  label `karpenter.sh/capacity-type=spot` instruct Karpenter to launch spot instance
  to accommodate the workload.


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

### Review and Monitor resources

Check if objects have been created:

```sh
oc get EC2NodeClass 
oc get EC2NodeClass default -o json | jq .status

oc get NodePool
oc get NodePool -o yaml
```

Check the logs (expected no errors):

```sh
oc logs -f -c controller deployment.apps/karpenter -n karpenter
```

## Clean up the environment

```sh
# Uninstall Karpenter
oc delete NodePools $POOL_NAME
oc delete EC2NodeClass default
helm uninstall karpenter --namespace karpenter
```

- Optionally, destroy OpenShift cluster

```sh
# installer bug: will keep in loop trying to delete an unknown object:
# DEBUG unrecognized EC2 resource type fleet          arn=arn:aws:ec2:us-east-1:269733383066:fleet/fleet-73b7938c-a3a6-ec3c-24ba-8fa29b791d43
# Workarounds:
# 1) Cancel all requests for the cluster
aws ec2 cancel-spot-instance-requests --spot-instance-request-ids $(aws ec2 describe-spot-instance-requests --filters Name=tag:Name,Values="${OCP_INFRA_NAME}-compute-karpenter" --query "SpotInstanceRequests[].SpotInstanceRequestId" --output text)

# 2) Modify cluster tag to prevent destroy flow keep trying to remove the resource (eventually the request will expire)
aws ec2 create-tags --tags Key=kubernetes.io/cluster/kpt-aws1-rv79z,Value=shared \
 --resources $(aws ec2 describe-spot-instance-requests --filters Name=tag:Name,Values="${OCP_INFRA_NAME}-compute-karpenter" --query "SpotInstanceRequests[].SpotInstanceRequestId" --output text)

./openshift-install destroy cluster --dir $INSTALL_DIR
```
