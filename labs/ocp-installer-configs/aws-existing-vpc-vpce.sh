cat <<EOF | envsubst > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${CLUSTER_BASE_DOMAIN}
credentialsMode: Manual
metadata:
  name: "${CLUSTER_NAME}"
platform:
  aws:
    region: ${REGION}
    #defaultMachinePlatform:
    #  zones:
    #  - ${REGION}a
# existing VPC: https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-vpc.html
    subnets:
$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" | jq -r '.Subnets[] | ("    - " + .SubnetId )')
# customization: https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-customizations.html
# private: https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-aws-private.html
# restricted: https://docs.openshift.com/container-platform/4.10/installing/installing_aws/installing-restricted-networks-aws-installer-provisioned.html
    serviceEndpoints:
      - name: ec2
        url: https://ec2.us-east-1.amazonaws.com
publish: External
pullSecret: '$(cat ${PULL_SECRET_FILE} |awk -v ORS= -v OFS= '{$1=$1}1')'
sshKey: |
  $(cat ${SSH_PUB_KEY_FILE})
EOF

echo ">> install-config.yaml created: "
cat ${INSTALL_DIR}/install-config.yaml
