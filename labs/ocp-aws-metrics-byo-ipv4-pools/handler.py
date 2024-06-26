#
# This Lambda function retrieves the Public IPv4 Pools in different regions and reports
# the total number of available addresses and total of addresses in each pool to CloudWatch
# as custom metrics TotalAddressCount and TotalAvailableAddressCount. 
#

import os
import boto3


def lambda_handler(event, context):
    try:
        # Create a CloudWatch client
        metrics_region = os.environ.get('METRICS_REGION', 'us-east-1')
        cloudwatch = boto3.client('cloudwatch', region_name=metrics_region)

        # Discover Public IPv4 Pools in different regions
        regions = os.environ.get('REGIONS', 'us-east-1').split(',')
        response = []
        for region in regions:
            ec2_client = boto3.client('ec2', region_name=region)
            response.extend(ec2_client.describe_public_ipv4_pools()['PublicIpv4Pools'])

        # Extract the relevant metrics from the response
        if len(response) == 0:
            raise Exception("No Public IPv4 pools found")

        # process pools
        for pool in response:
            if pool['PoolId'] is None:
                print("Skipping pool with no PoolId")
                continue

            pool_id = pool['PoolId']
            pool_border = pool['NetworkBorderGroup']

            total_addresses = pool['TotalAddressCount']
            total_free_addresses = pool['TotalAvailableAddressCount']

            # Report the metrics to CloudWatch
            metric_data=[
                    {
                        'MetricName': 'TotalAddressCount',
                        'Value': total_addresses,
                        'Dimensions': [
                            {
                                'Name': 'NetworkBorderGroup',
                                'Value': pool_border
                            },
                            {
                                'Name': 'PoolId',
                                'Value': pool_id
                            },
                        ],
                        'Unit': 'Count'
                    },
                    {
                        'MetricName': 'TotalAvailableAddressCount',
                        'Value': total_free_addresses,
                        'Dimensions': [
                            {
                                'Name': 'NetworkBorderGroup',
                                'Value': pool_border
                            },
                            {
                                'Name': 'PoolId',
                                'Value': pool_id
                            },
                        ],
                        'Unit': 'Count'
                    }
                ]
            print(f"Processed metrics for pool {pool_id} in {pool_border}: {metric_data}")
            cloudwatch.put_metric_data(
                Namespace='CustomMetrics',
                MetricData=metric_data
            )
    except Exception as e:
        print(f"An error occurred: {str(e)}")
