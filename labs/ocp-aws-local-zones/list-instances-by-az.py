#!/usr/bin/env python3
#
# Discovery EC2 Offering in Local Zones within a set of regions.
#
import json
from datetime import datetime
import boto3
import pandas as pd
from pprint import pprint


sess = boto3.session.Session()
ec2_regions = sess.get_available_regions('ec2')

ec2_regions = ["us-east-1", "us-west-2"]
instances = {}
all_zones = {}
families = []


for region in ec2_regions:
    print(f"Describing Local Zones on the region {region}")
    ec2 = sess.client('ec2', region_name=region)
    try:

        local_zones = [az if az['ZoneType'] == 'local-zone' else None 
                for az in ec2.describe_availability_zones(
                            Filters=[{"Name":"zone-type","Values":["local-zone"]}]
                        )['AvailabilityZones']]

        for az in local_zones:
            zone = az['ZoneName']
            if zone not in all_zones:
                all_zones[zone] = []

    except Exception as e:
        print("Error describing AZs")
        raise e

    # Describe Local Zone EC2 offerings
    try:
        offerings = ec2.describe_instance_type_offerings(
                LocationType='availability-zone',
                Filters=[{"Name": "location", "Values": [az['ZoneName']for az in local_zones]}]
            )['InstanceTypeOfferings']
        for o in offerings:
            try:
                itype = o['InstanceType']
                families.append(itype[0])
                if itype not in instances:
                    instances[itype] = []

                instances[itype].append(o['Location'])
                all_zones[o['Location']].append(itype)
            except Exception  as e:
                print("Unable to parse the offering: ", e)
                raise

    except KeyError:
      print(f"InstanceTypeOfferings not found on region {region}")
      continue
      pass

print(">> Instance map")
pprint(instances)

print(">> Zone map")
pprint(all_zones)

print(f"\n> AWS EC2 Offerings in AWS Local Zones for regions: {ec2_regions}")
print(f">> {datetime.now()}\n")

by_family = []

for f in (sorted(set(families))):
    rows = []
    for z in sorted(all_zones.keys()):
        invalid_family = True
        row = {
            "zone": z
        }

        for i in sorted(instances.keys()):
            if not i.startswith(f):
                continue
            invalid_family = False
            present = '--'
            if z in instances[i]:
                present = 'X'
            row[i] = present

        if invalid_family:
            continue
        rows.append(row)

    df = pd.read_json(json.dumps(rows))
    df.set_index('zone', inplace=True)
    by_family.append(df)


for d in by_family:
    print(d)

