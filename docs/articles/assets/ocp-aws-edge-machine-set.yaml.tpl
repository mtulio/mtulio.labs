---
# Template used to create MachineSet in Local Zones subnets
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  name: ${CLUSTER_INFRA_NAME}-edge-${CLUSTER_REGION}
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_INFRA_NAME}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_INFRA_NAME}-edge-${ZONE_NAME}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_INFRA_NAME}
        machine.openshift.io/cluster-api-machine-role: edge
        machine.openshift.io/cluster-api-machine-type: edge
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_INFRA_NAME}-edge-${ZONE_NAME}
    spec:
      metadata:
        labels:
          location: ${LOCATION_TYPE}
          node-role.kubernetes.io/edge: ""
      taints:
        - key: node-role.kubernetes.io/edge
          effect: NoSchedule
      providerSpec:
        value:
          kind: AWSMachineProviderConfig
          ami:
            id: ${AMI_ID}
          apiVersion: awsproviderconfig.openshift.io/v1beta1
          blockDevices:
          - ebs:
              encrypted: true
              iops: 0
              kmsKey:
                arn: ""
              volumeSize: ${DISK_SIZE}
              volumeType: ${DISK_TYPE}
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: ${CLUSTER_INFRA_NAME}-edge-profile
          instanceType: ${INSTANCE_TYPE}
          placement:
            availabilityZone: ${ZONE_NAME}
            region: ${CLUSTER_REGION}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - ${CLUSTER_INFRA_NAME}-worker-sg
          subnet:
            filters:
            - name: tag:Name
              values:
              - ${SUBNET_NAME}
          tags:
          - name: kubernetes.io/cluster/${CLUSTER_INFRA_NAME}
            value: owned
          - name: red-hat-clustertype
            value: rosa
          userDataSecret:
            name: worker-user-data
