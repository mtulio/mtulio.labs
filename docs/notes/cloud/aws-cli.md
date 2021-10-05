# AWS-CLI

## EC2

* Basic filter instances by tag Name

`aws ec2 describe-instances --filters "Name=tag:Name,Values=cache-master*"`

* Basic Query by Tag Name returning only the `InstanceId`, `ImageId` and `tag Name`

```
aws ec2 describe-instances --filters "Name=tag:Name,Values=cache-master*" --query 'Reservations[*].Instances[*].[InstanceId,ImageId,Tags[?Key==`Name`].Value]'
```

* Batch **Modify termination protection** (disable it)

> This is not recommended, but for massive maintanence sometimes we need to do this. For your own risk =)

> Please have a look in `aws cli` documentation: https://docs.aws.amazon.com/cli/latest/reference/ec2/modify-instance-attribute.html

```
COUNT=0;
for i in $(aws ec2 describe-instances --filters "Name=tag:Name,Values=cache-bf2018*" --query 'Reservations[*].Instances[*].[InstanceId]'  |jq .[].[] |grep ^'"i-' |tr -d '"'); do \
  let "COUNT++"; \
  echo "[$COUNT] Running in Instance: $i"; aws ec2 modify-instance-attribute --instance-id $i --no-disable-api-termination; \
done
```

* Batch **terminate** instances based on TAG

> This is not recommended, but for massive maintanence sometimes we need to do this. For your own risk =)

> Please have a look in `aws cli` documentation: https://docs.aws.amazon.com/cli/latest/reference/ec2/terminate-instances.html

```
COUNT=0;
for i in $(aws ec2 describe-instances --filters "Name=tag:Name,Values=cache-bf2018*" --query 'Reservations[*].Instances[*].[InstanceId]'  |jq .[].[] |grep ^'"i-' |tr -d '"'); do \
  let "COUNT++"; \
  echo "[$COUNT] Running in Instance: $i"; aws ec2 terminate-instances --instance-id $i; \
done
```

## S3

* Upload 'multi-part' object

`aws s3 cp --region ${AWS_REGION} ${LOCAL_FILE} s3://{BUCKET_NAME}/${OBJECT_NAME}`

* Upload 'single-part' object

```
aws s3api put-object --bucket ${BUCKET_NAME} --key ${OBJECT_NAME} --body ${LOCAL_FILE}
```
>> The command won't display stdout, I didn't find any verbose option... have a seat and take a coffe =p

* Upload object with ACL

> TODO

## Route53

* Authorize DNS resolution between VPC in different accounts

> TODO

## Beanstalk

* List env var for an application

1. export the env config using aws cli

```bash
aws --region sa-east-1 elasticbeanstalk describe-configuration-settings \
  --application-name "MyApp" \
  --environment myapp-env-prod \
  |jq '.ConfigurationSettings[].OptionSettings' > app-env-vars.json
```

2. Use an simple python script to parse it. =D

```python
import json
filename = 'app-env-vars.json'

if filename:
	with open(filename, 'r') as f:
		datastore = json.load(f)

for d in datastore:
	if d["Namespace"] == "aws:elasticbeanstalk:application:environment":
		print("{}={}".format(d["OptionName"], d["Value"]))

```


