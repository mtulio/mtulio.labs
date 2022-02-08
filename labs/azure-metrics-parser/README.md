# Azure metrics parser

The script [ci-ocp-az-metrics-parser.py](./ci-ocp-az-metrics-parser.py) parses the 
metrics retrieved from [azure cli (az monitor metrics list)](https://mtulio.net/notes/cloud/az-monitor/) into a table, side-by-side.

The metrics available is hardcoded on the script, to add new metrics
just update the `metrics` dict.

Dependencies:

- pandas
- tabulate

Execution:

- Download metrics collected from AZ Cli. (see [example from OCP CI](https://prow.ci.openshift.org/view/gs/origin-ci-test/logs/periodic-ci-openshift-release-master-ci-4.10-upgrade-from-stable-4.9-e2e-azure-upgrade/1490974667060547584))

- Run the script
```bash
./ci-ocp-az-metrics-parser.py ${PWD}
```

- The results looks like this table:

```
+-----+---------------------+-----------------+------------------+------------------+-----------------+-----------------------+----------------+
|     | timestamp           |   SnatConnCount |        ByteCount |      PacketCount |   UsedSnatPorts |   SnatConnCountFailed |   AllSnatPorts |
|-----+---------------------+-----------------+------------------+------------------+-----------------+-----------------------+----------------|
|   0 | 2022-02-08T09-20-00 |             nan |      0           |      0           |             nan |                   nan |            nan |
|   1 | 2022-02-08T09-21-00 |             nan |      0           |      0           |             nan |                   nan |            nan |
|   2 | 2022-02-08T09-22-00 |             nan |      0           |      0           |             nan |                   nan |            nan |
|   3 | 2022-02-08T09-23-00 |               0 |      0           |      0           |               0 |                     0 |           2048 |
|   4 | 2022-02-08T09-24-00 |              27 |      0           |      0           |               1 |                     0 |           3072 |
|   5 | 2022-02-08T09-25-00 |              39 |    280           |      4           |               2 |                     0 |           3072 |
|   6 | 2022-02-08T09-26-00 |              87 |      1.76617e+09 |      1.30065e+06 |               1 |                     0 |           3072 |
|   7 | 2022-02-08T09-27-00 |              42 |      2.51647e+09 |      1.9066e+06  |               1 |                     0 |           3072 |
|   8 | 2022-02-08T09-28-00 |             292 |    570           |      5           |              15 |                     0 |           3072 |
|   9 | 2022-02-08T09-29-00 |             343 |      2.50835e+09 |      1.7538e+06  |              15 |                     0 |           2048 |
[...]
```
