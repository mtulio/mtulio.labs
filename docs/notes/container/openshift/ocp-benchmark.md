# OCP Benchmark notes

(Used on project https://github.com/mtulio/openshift-benchmark-orchestrator )

## etcd:

References:
https://github.com/etcd-io/etcd/tree/main/tools/benchmark
https://etcd.io/docs/v3.5/op-guide/performance/

- Download

go get go.etcd.io/etcd/v3/tools/benchmark

- Copy

./oc-4.9 cp /home/mtulio/go/bin/benchmark -c etcd etcd-ip-10-0-139-37.ec2.internal:/var/lib/etcd/bench -n openshift-etcd

- setup

~~~
oc -n openshift-etcd get secrets etcd-all-peer -o json | jq -r '.data | to_entries | map(select(.key | match("master-0.crt"))) | map(.value)[0]' | base64 -d > master-0.crt
oc -n openshift-etcd get secrets etcd-all-peer -o json | jq -r '.data | to_entries | map(select(.key | match("master-0.key"))) | map(.value)[0]' | base64 -d > master-0.key
oc -n openshift-etcd get cm etcd-serving-ca -o go-template='{{ index .data "ca-bundle.crt"}}' > ca-cert.crt


 ./benchmark --cacert ca-cert.crt --cert master-0.crt --key master-0.key --endpoints 10.0.0.5:2379 put
~~~

BENCH_ETCD_CERT="/etc/kubernetes/static-pod-resources/etcd-certs/secrets/etcd-all-certs/etcd-peer-$(hostname).ec2.internal.crt"
BENCH_ETCD_CERTK="/etc/kubernetes/static-pod-resources/etcd-certs/secrets/etcd-all-certs/etcd-peer-$(hostname).ec2.internal.key"

BENCH_ETCD_CERT="/etc/kubernetes/static-pod-resources/etcd-certs/secrets/etcd-all-certs/etcd-serving-$(hostname).ec2.internal.crt"
BENCH_ETCD_CERTK="/etc/kubernetes/static-pod-resources/etcd-certs/secrets/etcd-all-certs/etcd-serving-$(hostname).ec2.internal.key"


BENCH_ETCD_CA=/etc/kubernetes/static-pod-resources/etcd-certs/configmaps/etcd-serving-ca/ca-bundle.crt
IP_ADDR=$(ip ad show ens5 |grep 'inet ' |awk '{print$2}' |awk -F'/' '{print$1}')

BENCH_PATH=/var/lib/etcd/benchmark

${BENCH_PATH} --cacert ${BENCH_ETCD_CERT} --cert ${BENCH_ETCD_CA} --key ${BENCH_ETCD_CERTK} --endpoints ${IP_ADDR}:2379 put


## runner

fio opts / Refs:
- https://github.com/jcpowermac/etcd-thin-vs-thick-perf-test/blob/main/fio.sh
- https://hub.docker.com/r/ljishen/fio



