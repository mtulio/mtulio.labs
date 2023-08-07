#!/usr/bin/env python3
#
# Discovery EC2 Offering in Zones within a set of regions.
#
import os
import time
import json
from datetime import datetime
import boto3
import pandas as pd
from pprint import pprint
import subprocess
from bigtree import list_to_tree
import pathlib
import io
from contextlib import redirect_stdout

sess = boto3.session.Session()

instances = {}
all_zones = {}
families = []

tree_regions_root = "AWS_Regions-(public)"
tree_regions = []
tree_regions_status = []
ec2_regions = []
# ec2_regions = ["us-east-1", "us-west-2"]
#ec2_regions = ["us-west-2"]
#ec2_regions = ["us-east-1"]
if os.getenv('FILTER_REGIONS') is not None:
    ec2_regions = os.getenv('FILTER_REGIONS').split(',')

tree_zones_root = "AWS_Zones-(public)"
tree_zones = []
tree_zones_status = []
zone_types = ["local-zone","wavelength-zone"]
#zone_types = ["availability-zone"]
if os.getenv('FILTER_ZONE_TYPES') is not None:
    zone_types = os.getenv('FILTER_ZONE_TYPES').split(',')

tree_offerings_zone_root = "AWS_Regions-(EC2 Offerings Zones)"
tree_offerings_zone = []
ec2_filter = []
if os.getenv('FILTER_EC2_TYPES') is not None:
    ec2_filter = os.getenv('FILTER_EC2_TYPES').split(',')

tree_offerings_type_root = "AWS_EC2-(EC2 Offerings by Type)"
tree_offerings_type = []

pd.set_option('display.max_rows', 1000)
pd.set_option('display.max_columns', 1000)

date = (f"{datetime.now()}")
script_dir=pathlib.Path(__file__).parent.resolve()

run_name = "data-local-wavelength-zones"
if os.getenv('RUN_NAME') is not None:
    run_name = os.getenv('RUN_NAME')


def discover_regions():
    try:
        # Regions API does not require regional endpoint
        ec2 = sess.client('ec2', region_name="us-east-1")
        all_regions = ec2.describe_regions()['Regions']
        for r in all_regions:
            tree_regions.append(f"{tree_regions_root}/{r['RegionName']}/{r['Endpoint']}")
            tree_regions_status.append(f"{tree_regions_root}/{r['OptInStatus']}/{r['RegionName']}")
            ec2_regions.append(r['RegionName'])

    except Exception as e:
        print("Unable to discover regions")
        raise e


def discover_offerings():
    print(f"Starting EC2 Offering discovery into regions: {ec2_regions}")
    for region in ec2_regions:
        print(f"Describing Zones in the region {region}")
        ec2 = sess.client('ec2', region_name=region)
        try:

            zones = [az for az in ec2.describe_availability_zones(
                                AllAvailabilityZones=True,
                                Filters=[{
                                    "Name":"zone-type",
                                    "Values": zone_types,
                                }]
                            )['AvailabilityZones']]

            for az in zones:
                zone = az['ZoneName']
                if zone not in all_zones:
                    all_zones[zone] = []

        except Exception as e:
            print("Error describing local zones")
            raise e

        # Describe Local Zone EC2 offerings
        try:
            try:
                zones_str=",".join([az['ZoneName']for az in zones])
                # describe_instance_type_offerings does not return all instances (mainly in newer zones)
                #offerings = ec2.describe_instance_type_offerings(
                #        LocationType='availability-zone',
                #        Filters=[{"Name": "location", "Values": [az['ZoneName']for az in local_zones]}]
                #    )['InstanceTypeOfferings']
                #$ aws ec2 describe-instance-type-offerings --location-type availability-zone --filters --region=us-east-1
                cmd = ["aws", "ec2", "describe-instance-type-offerings",
                    "--location-type", "availability-zone",
                    "--filters", f"Name=location,Values={zones_str}",
                    "--region", f"{region}"
                ]
                result = subprocess.run(cmd, stdout=subprocess.PIPE)
            except Exception as e:
                print(f"One or more errors was found when running the command: {cmd}")
                print(f"{e}")
                os.exit(1)
            
            try:
                offerings = json.loads(result.stdout.decode('utf-8'))['InstanceTypeOfferings']
            except Exception as e:
                print("Unexpecting error when decoding to json the describe-instance-type-offerings.")
                if 'InstanceTypeOfferings' not in result.stdout.decode('utf-8'):
                    print(f"'InstanceTypeOfferings' is not present on the payload.")
                print(f"{result.stdout.decode('utf-8')}")
                os.exit(1)

            for o in offerings:
                try:
                    itype = o['InstanceType']
                    if (len(ec2_filter) > 0):
                        if itype not in ec2_filter:
                            continue

                    families.append(itype[0])
                    if itype not in instances:
                        instances[itype] = []

                    instances[itype].append(o['Location'])
                    all_zones[o['Location']].append(itype)
                    tree_offerings_zone.append(f"{tree_offerings_zone_root}/{region}/{o['Location']}/{itype}")
                    tree_offerings_type.append(f"{tree_offerings_type_root}/{itype}/{region}/{o['Location']}")
                except Exception  as e:
                    print("Unable to parse the offering: ", e)
                    raise

        except KeyError:
          print(f"InstanceTypeOfferings not found on region {region}")
          continue
        time.sleep(10)


def discover_zone_map():
    for region in ec2_regions:
        print(f"Describing Zones in the region {region}")
        ec2 = sess.client('ec2', region_name=region)
        try:
            zones = ec2.describe_availability_zones(AllAvailabilityZones=True)['AvailabilityZones']
            for az in zones:
                tree_zones_status.append(f"{tree_zones_root}/{az['RegionName']}/{az['OptInStatus']}/{az['ZoneName']}")
                if 'ParentZoneName' in az:
                    tree_zones.append(f"{tree_zones_root}/{az['RegionName']}/{az['ParentZoneName']}/{az['ZoneName']}")
                else:
                    tree_zones.append(f"{tree_zones_root}/{az['RegionName']}/{az['ZoneName']}")

        except Exception as e:
            print("Error describing all zones")
            raise e


def build_ec2_offering_map():
    discover_offerings()
    save_pprint_to_file(f"{run_name}/output-aws-ec2-offering-type-map.txt", f"{date}>> Instance map", instances)
    save_mapkeys_to_file(f"{run_name}/output-aws-ec2-offering-type-map-count.txt", f"{date}>> EC2 Offerings summary (total zones)", instances)
    save_pprint_to_file(f"{run_name}/output-aws-ec2-offering-zone-map.txt", f"{date}>> Zone map by Offering", all_zones)
    save_mapkeys_to_file(f"{run_name}/output-aws-ec2-offering-zone-map-count.txt", f"{date}>> Zone count by offering", all_zones)

    print(f"\n> AWS EC2 Offerings in the Zones for regions: {ec2_regions}")

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

    save_raw_to_file(f"{run_name}/output-aws-ec2-offering-table.txt", f"{date}>> Zones by Family", "", mode="w")
    for d in by_family:
        save_raw_to_file(f"{run_name}/output-aws-ec2-offering-table.txt", "", d, mode="a")
    
    root = list_to_tree(tree_offerings_zone)
    save_tree_to_file(f"{run_name}/output-aws-ec2-offering-zone-tree.txt", f"{date}>> Show EC2 Offerings by Local Zone", root)

    root = list_to_tree(tree_offerings_type)
    save_tree_to_file(f"{run_name}/output-aws-ec2-offering-type-tree.txt", f"{date}>> Show EC2 Offerings by Instance Type", root)


def build_zone_map():
    discover_zone_map()
    root = list_to_tree(tree_zones)
    save_tree_to_file(f"{run_name}/output-aws-zones-parent.txt", f"{date}>> Show Zones by Parent", root)

    root = list_to_tree(tree_zones_status)
    save_tree_to_file(f"{run_name}/output-aws-zones-status.txt", f"{date}>> Show Zones OptIn status", root)


def save_to_file(filename, buf, mode="w"):
        output = buf.getvalue()
        with open(f"{script_dir}/{filename}", mode) as f:
            f.write(output)


def save_tree_to_file(filename, msg, root):
    with io.StringIO() as buf, redirect_stdout(buf):
        print(msg)
        root.show()
        save_to_file(filename, buf)


def save_raw_to_file(filename, msg, d, mode="w"):
    with io.StringIO() as buf, redirect_stdout(buf):
        print(msg)
        print(d)
        save_to_file(filename, buf, mode=mode)


def save_pprint_to_file(filename, msg, d):
    with io.StringIO() as buf, redirect_stdout(buf):
        print(msg)
        pprint(d)
        save_to_file(filename, buf)


def save_mapkeys_to_file(filename, msg, d):
    with io.StringIO() as buf, redirect_stdout(buf):
        print(msg)
        print(f"Total items: {len(d.keys())}")
        for dk in d.keys():
            print(f"{dk}: {len(d[dk])}")
        save_to_file(filename, buf)


def build_region_map():
    if len(ec2_regions) > 0:
        return
    discover_regions()
    root = list_to_tree(tree_regions)
    save_tree_to_file(f"{run_name}/output-aws-regions.txt", f"{date}>> Show Region", root)

    root = list_to_tree(tree_regions_status)
    save_tree_to_file(f"{run_name}/output-aws-regions-status.txt", f"{date}>> Show Region by OptIn status", root)


def init():
    # create base directory
    try:
        print(f"Creating directory {run_name}")
        os.mkdir(run_name)
    except OSError as error:
        print(f"Error creating base dir {run_name}: {error}")


if __name__ == "__main__":
    init()
    # discover_regions()
    build_region_map()
    build_ec2_offering_map()
    build_zone_map()