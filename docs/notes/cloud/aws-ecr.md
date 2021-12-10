# AWS ECR (Container Registry)


## HowTo

### Automate ECR token refresh on Kubernetes

Dependencies:
- kube node need to have access to ECR through IMDS (no restriction in SDN/network/etc to IMDS/instance metadata service)
- IAM instance profile for node need to have policies to access ECR
- contianer should have access to create/update the secret

Credits for [@guessi gist](https://gist.github.com/guessi/89eb1a8227d3ffea06e10ecd9d890b0f):

``` shell
#!/bin/bash

# prerequisite:
# - ec2 instance should attached proper iam role
# - awscli
# - kubectl

# Usage:
#
# define the following variales in your environment (root account)
# - ECR_ACCOUNT
# - ECR_REGION
# - SECRET_NAME
#
# $ cp <script-file> /etc/cron.hourly/refresh_ecr_token
# $ chmod +x /etc/cron.hourly/refresh_ecr_token

# define ecr related information
ECR_ACCOUNT="${ECR_ACCOUNT:-123456789012}"
ECR_REGION="${ECR_REGION:-ap-northeast-1}"
SECRET_NAME="${SECRET_NAME:-ecr-auth}"
DOCKER_REGISTRY="https://${ECR_ACCOUNT}.dkr.ecr.${ECR_REGION}.amazonaws.com"

refresh_token() {
  # get latest ecr login token via awscli
  TOKEN=$(aws ecr get-authorization-token                    \
            --region=${REGION}                               \
            --output text                                    \
            --query authorizationData[].authorizationToken | \
          base64 -d | cut -d: -f2)

  # abort if token retrieval failed
  if [ -z "${TOKEN}" ]; then
    echo "==> Abort, get token failed"
    exit 1
  fi

  # remove previous created secret (any failure will be ignored)
  kubectl delete secret --ignore-not-found "${SECRET_NAME}" || true

  # refresh ecr token with new token
  kubectl create secret docker-registry "${SECRET_NAME}"     \
    --docker-server=${DOCKER_REGISTRY}                       \
    --docker-username=AWS                                    \
    --docker-password="${TOKEN}"                             \
    --docker-email="no-reply@example.com"
}

refresh_token "${ECR_REGION}"
```
