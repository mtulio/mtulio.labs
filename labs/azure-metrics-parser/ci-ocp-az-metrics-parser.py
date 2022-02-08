# -*- coding: utf-8 -*-
#
# Usage: ci-ocp-az-metrics-parser.py /metrics/path
#
import sys
import json
from glob import glob
from tabulate import tabulate
from pandas import pandas as pd


metrics = {
    "AllocatedSnatPorts": {
        "alias": "AllSnatPorts",
        "field": "average"
    },
    "ByteCount": {
        "alias": "ByteCount",
        "field": "total"
    },
    "PacketCount": {
        "alias": "PacketCount",
        "field": "total"
    },
    "SnatConnectionCount": {
        "alias": "SnatConnCount",
        "field": "total"
    },
    "SnatConnectionCountFailed": {
        "alias": "SnatConnCountFailed",
        "field": "total"
    },
    "UsedSnatPorts": {
        "alias": "UsedSnatPorts",
        "field": "average"
    },
}
data_points = {}
data_points_pd = []
metrics_path = '/home/mtulio/Downloads/azure-metrics'


# Download (ToDo) LoadBalancer metrics and save it to metrics_path,
# could be used when metrics_path is not provided.
# Example of metrics collected from CI:
# https://gcsweb-ci.apps.ci.l2s4.p1.openshiftapps.com/gcs/origin-ci-test/logs/periodic-ci-openshift-release-master-ci-4.10-upgrade-from-stable-4.9-e2e-azure-upgrade/1490974667060547584/artifacts/e2e-azure-upgrade/gather-azure-cli/artifacts/azure-monitor-metrics/


# Dump the data points to a table and print it as humam-readable
def show_results():
    headers = [
        "timestamp"
    ]
    rows=[]

    for mk in metrics.keys(): headers.append(metrics[mk]["alias"])

    for m_ts in data_points.keys():

        is_null = True
        row = []
        row.append(m_ts)
        dp = {
            "timestamp": m_ts
        }
        for m_k in data_points[m_ts].keys():
            v = data_points[m_ts][m_k]
            if v is not None:
                is_null = False
            row.append(v)
            dp[m_k] = v

        if is_null:
            continue
        rows.append(row)
        data_points_pd.append(dp)
    
    print(tabulate(pd.DataFrame.from_dict(data_points_pd), headers='keys', tablefmt='psql'))
    

# Load json file metrics from local directory, parse the datapoints to
# a dictionary data_points with this format:
# {"timstamp": {"metric_name": "metric_value", ...}}
def load_metrics():
    try:
        metrics_path = sys.argv[1]
    except Exception as e:
        print("Unable to get metrics path from argv[1]")
        raise e

    for f_name in glob(metrics_path + '/*.json'):
        with open(f_name) as f:
            data = json.loads(f.read())
        
        metric_name = data["value"][0]["name"]["value"]
        if len(data["value"][0]["timeseries"][0]["metadatavalues"]) != 0:
            # limited to one dimension for one filter 'SnatConnectionCountFailed'
            dimensionValue = data["value"][0]["timeseries"][0]["metadatavalues"][0]["value"]
            metric_name = f"{metric_name}{dimensionValue}"

        metric_alias = metrics[metric_name]["alias"]
        
        for dt_point in data["value"][0]["timeseries"][0]["data"]:
            value = dt_point[metrics[metric_name]["field"]]
            ts = dt_point["timeStamp"].replace(':','-').split('+')[0]
            
            if ts not in data_points:
                data_points[ts] = {}

            if metric_alias not in data_points[ts]:
                data_points[ts][metric_alias] = 0

            data_points[ts][metric_alias] = value

    show_results()


if __name__ == '__main__':
  load_metrics()
