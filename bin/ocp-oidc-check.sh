#!/usr/bin/env bash

#
# Helper script to troubleshoot OIDC* infrastructure
# when installing an OpenShift cluster on AWS with manual
# credentials mode with STS.
#
# *OpenID Connect / Cloud Authentication on OpenShift/Kubernetes
#

# Show results with PASS/FAIL format with errors when it have.
function show_results() {
  local show_resp=${1-}
  local resp_type='out'
  if [[ ! -s /tmp/oc-oidc-check.err ]];
  then
    echo -ne "PASS"
  else
    resp_type='err'
    echo -ne "FAIL"
  fi
  if [[ -n ${show_resp} ]]; then
    if [[ -f ${show_resp} ]]; then
      echo -e "\n~~~"
      cat /tmp/oc-oidc-check.$resp_type
      echo "~~~"
    fi
  fi
  rm /tmp/oc-oidc-check.* >/dev/null 2>&1
}

function show_results_without() {
  show_results "yes"
}

declare -A aws_credsrequests
declare -A aws_credsrequests_secrets
declare -A aws_creds_pod_controllers

aws_credsrequests["openshift-cluster-csi-drivers"]="aws-ebs-csi-driver-operator"
aws_credsrequests["openshift-machine-api"]="openshift-machine-api-aws"


echo -ne "\n--- Validate infrastructure"

# https://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation
# .2
# Checking issuer
echo -e "\n---"

echo -en "\n=> Getting Issuer URL in Auth\t: "
ISSUER_AUTH=$(oc get authentication cluster -o jsonpath='{.spec.serviceAccountIssuer}')
echo -n $ISSUER_AUTH

echo -en "\n=> Getting Issuer URL in KAS\t: "
ISSUER_KUBE=$(kubectl get --raw /.well-known/openid-configuration | jq -r .issuer)
echo -n $ISSUER_KUBE

echo -en "\n=> Getting Issuer URL in OIDC\t: "
ISSUER_OIDC=$(curl -sk $(kubectl get --raw /.well-known/openid-configuration | jq -r .issuer)/.well-known/openid-configuration | jq -r .issuer)
echo -n $ISSUER_OIDC

echo -e "\n---"
echo -en "\n=> ServiceAccountIssuer can be accessed through the internet... "
curl -sk $ISSUER_AUTH/.well-known/openid-configuration | jq -cr .issuer \
  >/tmp/oc-oidc-check.out 2> /tmp/oc-oidc-check.err
  show_results

echo -ne "\n--- Validate credential requests / tokens by component"

for key in "${!aws_credsrequests[@]}"; do
  echo -ne "\n=> AWS STS | discoverying secret name from CredRequest | ${aws_credsrequests[$key]}"
  aws_credsrequests_secrets[$key]="$(oc get -n openshift-cloud-credential-operator credentialsrequests ${aws_credsrequests[$key]} -o jsonpath='{.spec.secretRef.name}')"
done

echo -ne "\n---"
function check_log_error() {
  local namespace=$1
  local pod_container_name=""
  local pod_filter=""
  local check_logs=false
  
  if [[ "${namespace}" == "openshift-machine-api" ]]; then
    pod_container_name=machine-controller
    pod_filter="api=clusterapi,k8s-app=controller"
    check_logs=true
  fi

  if [[ $check_logs == true ]]; then
    # Checking log pattern: InvalidIdentityToken
    echo -ne "\n=> AWS STS | Component Check | $namespace | Controller reporting errors | InvalidIdentityToken..."
    ERR_COUNT=$(oc logs -n $namespace -c $pod_container_name $(oc get pods -l $pod_filter -n $namespace -o jsonpath='{.items[0].metadata.name}'
) | grep InvalidIdentityToken | wc -l)
    if [[ $ERR_COUNT -ge 1 ]]; then
      echo -e "ERROR COUNT: $ERR_COUNT \nSAMPLE:" > /tmp/oc-oidc-check.err
      oc logs -n $namespace -c $pod_container_name $(oc get pods -l $pod_filter -n $namespace -o jsonpath='{.items[0].metadata.name}'
) | grep InvalidIdentityToken | tail -n1 >> /tmp/oc-oidc-check.err
    fi
    show_results "yes"
  fi
}

for key in "${!aws_credsrequests_secrets[@]}"; do
  echo -ne "\n=> AWS STS | Component Check | $key | secret | $key/${aws_credsrequests_secrets[$key]} ..."
  # Check if credentials secret has been created
  oc get secrets ${aws_credsrequests_secrets[$key]} \
      -n $key \
      -o jsonpath='{.data.credentials}' \
      | base64 -d \
      >/tmp/oc-oidc-check.out 2> /tmp/oc-oidc-check.err
  show_results

  check_log_error "${key}"
done

echo
exit

# TODO
# Exiting for now, the next steps need to be validated to provide a better pass/fail summary.

# Fields to validate:

# > Essential JWT Header Fields
# kid (Key ID): Must match a valid key in the JWKS endpoint exposed by your Kubernetes cluster. AWS uses this to retrieve the correct public key for signature verification
# Algorithm: Ensure the alg header matches the expected algorithm (typically RS256 for Kubernetes)

# > Core Token Claims
# iss (Issuer): Must exactly match the OIDC provider URL configured in AWS IAM. For Kubernetes, this is typically https://<K8s-API-Server>/clusters/<cluster-id>.
# aud (Audience): Must contain the AWS role ARN or STS audience (sts.amazonaws.com) that the token is intended for.
# sub (Subject): Should follow the Kubernetes service account format system:serviceaccount:<namespace>:<serviceaccount-name>

# > Time Validation
# exp (Expiration): Token must not be expired (AWS rejects tokens with ≤15min validity remaining).
# iat (Issued At): Ensure token wasn't issued too far in the past (AWS allows up to 6hr clock skew).

# > Signature Validation
# Verify the JWT signature matches the public key in your Kubernetes cluster's JWKS endpoint.
# Confirm the JWKS endpoint is accessible to AWS and returns valid keys (common failure point in the error message)

# > AWS
# Check OIDC Identity Provider Configuration: Verify the Url matches iss claim exactly and thumbprints are correct.
# aws iam get-open-id-connect-provider --open-id-connect-provider-arn <your-oidc-provider-arn>


# echo -ne "\n---\n=> Component | Secret has been created: "
# # Extracts the token
# # Get Token path from AWS credentials mounted to pod
# TOKEN_PATH=$(oc get secrets aws-cloud-credentials \
#     -n openshift-machine-api \
#     -o jsonpath='{.data.credentials}' |\
#     base64 -d |\
#     grep ^web_identity_token_file |\
#     awk '{print$3}')

echo -e "\n---"
echo "=> Component | Can read signed service account token: "
# Get Controler's pod
CAPI_POD=$(oc get pods -n openshift-machine-api \
    -l api=clusterapi \
    -o jsonpath='{.items[*].metadata.name}')

# Extract tokens from pod
TOKEN=$(oc exec -n openshift-machine-api ${CAPI_POD} \
    -c machine-controller -- cat ${TOKEN_PATH})

echo "Token size from pod $CAPI_POD: $(echo $TOKEN|wc)"

echo "---"
echo "=> Component | Can extract information from JWT token: "

# Get insigits
echo $TOKEN | awk -F. '{ print $1 }' | base64 -d 2>/dev/null | jq .alg
echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null | jq .iss


echo "---"
echo "=> Component | Can extract IAM Role from secret: "

# Test token
IAM_ROLE=$(oc get secrets aws-cloud-credentials \
    -n openshift-machine-api \
    -o jsonpath='{.data.credentials}' |\
    base64 -d |\
    grep ^role_arn |\
    awk '{print$3}')

echo $IAM_ROLE

echo "---"
echo "=> Component | Can assume IAM role with bound token: "
AWS_SHARED_CREDENTIALS_FILE=$HOME/.aws/credentials aws sts assume-role-with-web-identity \
    --role-arn "${IAM_ROLE}" \
    --role-session-name "my-session" \
    --web-identity-token "${TOKEN}"


echo "=> Issuer in the token: "
echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null  | jq -r .iss

# Checking kid
echo "---"
echo "=> kid in public JWKS: "
kid_public=$(curl -sk $(kubectl get --raw /.well-known/openid-configuration | jq -r .issuer)/keys.json  | jq -r .keys[0].kid)
echo $kid_public

echo "=> kid kube keys: "
kubectl get --raw /openid/v1/jwks | jq -r ".keys[] | select(.kid==\"${kid_public}\")"

if [[ -z $(kubectl get --raw /openid/v1/jwks | jq -r ".keys[] | select(.kid==\"${kid_public}\")") ]]; then
  echo "ERROR kid published in S3 not found in kube"
fi

echo "=> kid token: "
kid_token=$(echo $TOKEN | awk -F. '{ print $1 }' | base64 -d 2>/dev/null  | jq -r .kid)
echo $kid_token

echo "=> kid token in kube: "
kubectl get --raw /openid/v1/jwks | jq -r ".keys[] | select(.kid==\"${kid_token}\").kid"

if [[ "${kid_public}" != "${kid_token}" ]]; then
  echo "ERROR kid missmatch from signed token and published public keys"
fi

# check if public keys are accessible
curl -sk $(echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null  | jq -r .iss)/keys.json

# checkif config is accessible
curl -sk $(echo $TOKEN | awk -F. '{ print $2 }' | base64 -d 2>/dev/null  | jq -r .iss)/.well-known/openid-configuration

kubectl get --raw /.well-known/openid-configuration | jq .
kubectl get --raw /openid/v1/jwks | jq .
