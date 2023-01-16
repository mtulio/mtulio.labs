# AWS Zones

## Opt in Local Zones

Opt in all Local Zones for a specific region:

> Note: Each availability zone are part of one Zone Group. The Local Zone has the API type `local-zone`. To use Local or Wavelength zones you must enable it's group.

```bash
REGION=eu-north-1
for ZONE_GROUP in $(aws ec2 describe-availability-zones \
    --filters Name=region-name,Values=${REGION} Name=zone-type,Values=local-zone \
    --query 'AvailabilityZones[].GroupName' --output text \
    --all-availability-zones --region ${REGION}); do

    echo "# Modifying Zone group ${ZONE_GROUP}"
    aws ec2 modify-availability-zone-group \
        --group-name "${ZONE_GROUP}" \
        --opt-in-status opted-in \
        --region ${REGION}
done
```

Example output

```text
# Modifying Zone group eu-central-1-ham-1
{
    "Return": true
}
# Modifying Zone group eu-central-1-waw-1
{
    "Return": true
}
```

## Describe instances offering in Local Zones

> Note: The script is used to discover and group EC2 offering by Local Zones.

Run using the default region (us-east-1):

```bash
$ podman run --rm \
    -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
    -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
    -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
    quay.io/mrbraga/aws-ec2-offering-by-zone:latest
```

Discovery more regions:

> NOTE1: Default value for `FILTER_REGIONS=us-east-1,us-west-2`

> NOTE2: Only opted in zone groups will be displayed. Otherwise, you should opt in first

```bash
$ podman run --rm \
    -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
    -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
    -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
    -e FILTER_REGIONS=us-east-1,us-west-2,eu-north-1,eu-central-1,ap-south-1,ap-southeast-1,ap-southeast-2,ap-northeast-1,me-south-1 \
    quay.io/mrbraga/aws-ec2-offering-by-zone:latest
```

Example output: https://gist.github.com/mtulio/c98aa15128a7becb06a372f00d824c42
