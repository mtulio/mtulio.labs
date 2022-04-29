# EC2

## Simple run instance (FCOS)

```bash
NAME='fcos-instance'
IMAGE='ami-0389fff7e72ebe8e0'
REGION='us-east-1'
TYPE='m5.large'
SUBNET='subnet-XX'
SECURITY_GROUPS='sg-XX'

aws ec2 run-instances                     \
    --region $REGION                      \
    --image-id $IMAGE                     \
    --instance-type $TYPE                 \
    --subnet-id $SUBNET                   \
    --security-group-ids $SECURITY_GROUPS
```

## Instance offering by Region

Query instance type offerings for each available region that has EC2 service.

~~~python
import boto3
import pandas as pd

diff_left="m5"
diff_right="m6i"

type_left=f"{diff_left}.xlarge"
type_right=f"{diff_right}.xlarge"

data = []
columns = [
	'region',
	f'count({type_left})',
	f'count({type_right})',
	f'diff({diff_left}_{diff_right})'
]

azByRegion = {}
# {
#     "region": {
#         "m5.large": [],
#         "m4.large": [],
#     }
# }

sess = boto3.session.Session()
ec2_regions = sess.get_available_regions('ec2')

for region in ec2_regions:
  print(f"Checkiing region {region}")
  azByRegion[region] = {
    f"{type_left}": [],
    f"{type_right}": []
  }
  ec2 = sess.client('ec2', region_name=region)
  try:
    offerings = ec2.describe_instance_type_offerings(
            LocationType='availability-zone',
            Filters=[{"Name": "instance-type", "Values": [type_left, type_right]}]
        )['InstanceTypeOfferings']
  except KeyError:
    print(f"InstanceTypeOfferings not found on region {region}")
    continue
    pass

  for of in offerings:
    azByRegion[region][of['InstanceType']].append(of['Location'])

print(azByRegion)
data = []
for rg in azByRegion.keys():
    row = []
    row.append(rg)
    row.append(len(azByRegion[rg][type_left]))
    row.append(len(azByRegion[rg][type_right]))
    row.append(len(azByRegion[rg][type_left]) - len(azByRegion[rg][type_right]))
    data.append(row)

df = pd.DataFrame(data, columns=columns)
df.set_index('region', inplace=True)
print(df)
~~~
