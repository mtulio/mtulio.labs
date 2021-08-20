# EC2

## Instance offering by Region

Query instance type offerings for each available region that has EC2 service.

~~~python
import boto3

data = []
columns = ['region', 'count(m5.large)', 'count(m4.large)', 'count(m5VSm4)']

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
    "m5.large": [],
    "m4.large": []
  }
  ec2 = sess.client('ec2', region_name=region)
  try:
    offerings = ec2.describe_instance_type_offerings(
            LocationType='availability-zone',
            Filters=[{"Name": "instance-type", "Values": ["m5.large", "m4.large"]}]
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
    row.append(len(azByRegion[rg]['m5.large']))
    row.append(len(azByRegion[rg]['m4.large']))
    row.append(len(azByRegion[rg]['m5.large']) - len(azByRegion[rg]['m4.large']))
    data.append(row)

df = pd.DataFrame(data, columns=columns, index=['region'])
df.set_index('region', inplace=True)
df
~~~
