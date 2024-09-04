# aws-ec2-list-by-zone

Build container:

```
podman build -t quay.io/mrbraga/aws-ec2-offering-by-zone:latest .
```

## Listing EC2 into Local Zones

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

## Opt in Zone group

To opt in all Local Zone groups* from a given Region, run the following command:

> Each Local Zone are part of one group. All zone groups have at least one zone. Most of then have only one, except (currently) us-west-1-lax-1 (1a and 1b)

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

### opt-in wavelength zones in all regions


```bash
ZONE_TYPE=wavelength-zone
for REGION_NAME in $(aws ec2 describe-regions --all-regions --query "Regions[].RegionName" | jq -r .[]); do
    for ZONE_GROUP in $(aws ec2 describe-availability-zones \
        --filters Name=region-name,Values=${REGION_NAME} Name=zone-type,Values=$ZONE_TYPE \
        --query 'AvailabilityZones[].GroupName' --output text \
        --all-availability-zones --region ${REGION_NAME}); do

        echo "# Modifying Zone group ${ZONE_GROUP}"
        aws ec2 modify-availability-zone-group \
            --group-name "${ZONE_GROUP}" \
            --opt-in-status opted-in \
            --region ${REGION_NAME}
    done
done
```

## Custom executions

Describe specific ARM instances in the regions:

- ARM vs Intel

```bash
RUN_NAME="data-ec2-general-arm-vs-intel" \
    FILTER_ZONE_TYPES="availability-zone" \
    FILTER_EC2_TYPES="m6g.xlarge,m7g.xlarge,m6i.xlarge,m7i.xlarge" \
    ./list-instances-by-az.py
```

- ARM Offerings

```bash
RUN_NAME="data-ec2-general-arm-mdrc" \
    FILTER_ZONE_TYPES="availability-zone" \
    FILTER_EC2_TYPES="m6g.xlarge,m6gd.xlarge,r6g.xlarge,c6g.2xlarge" \
    ./list-instances-by-az.py
```

- ARM vs Intel vs AMD

```bash
RUN_NAME="data-ec2-general-arm-vs-intel-vs-amd" \
    FILTER_ZONE_TYPES="availability-zone" \
    FILTER_EC2_TYPES="m6g.xlarge,m7g.xlarge,m6i.xlarge,m6a.xlarge" \
    ./list-instances-by-az.py
```

- EC2 offerings in specific region (il-central-1)

```bash
RUN_NAME="data-ec2-region-filter-il-central-1" \
    FILTER_REGIONS="il-central-1" \
    FILTER_ZONE_TYPES="availability-zone" \
    ./list-instances-by-az.py
```


- EC2 offerings in Wavelength Zones

```bash
RUN_NAME="data-ec2-wavelength-zones" \
    FILTER_ZONE_TYPES="wavelength-zone" \
    ./list-instances-by-az.py
```

- EC2 offerings in Local Zones

```bash
RUN_NAME="data-ec2-local-zones" \
    FILTER_ZONE_TYPES="local-zone" \
    ./list-instances-by-az.py
```