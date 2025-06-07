{
  "cluster": {
    "region": $CLUSTER_REGION,
    "name": $CLUSTER_NAME,
    "controllerClusterId": $CLUSTER_NAME,
    "autoScaler": {
      "resourceLimits": {
        "maxMemoryGib": 256,
        "maxVCpu": 128
      },
      "down": {
        "maxScaleDownPercentage": 60
      }
    },
    "capacity": {
      "minimum": 0,
      "maximum": 20,
      "target": 0
    },
    "compute": {
      "subnetIds": $SUBNETS,
      "instanceTypes": {
        "whitelist": ${INSTANCES_WL}
      },
      "launchSpecification": {
        "imageId": ${IMAGE_ID},
        "userData": ${USER_DATA},
        "securityGroupIds": [ $SECURITY_GROUP_ID ],
        "iamInstanceProfile": {
          "arn": $INSTANCE_PROFILE_ARN
        },
        "keyPair": $KEY_PAR_NAME,
        "tags": [
          {
            "tagKey": "Owner",
            "tagValue": $TAG_KEY_KUBE
          },
          {
            "tagKey": $TAG_KEY_KUBE,
            "tagValue": "owned"
          },
          {
            "tagKey": "Name",
            "tagValue": $TAG_NAME
          }
        ],
        "associatePublicIpAddress": false
      }
    },
    "scheduling": {},
    "strategy": {
      "utilizeReservedInstances": true,
      "fallbackToOd": true,
      "spotPercentage": 100,
      "gracePeriod": 600,
      "drainingTimeout": 60,
      "utilizeCommitments": false
    }
  }
}
