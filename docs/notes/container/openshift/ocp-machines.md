# OpenShift Machines

## Troubleshooting

### Force Machine to `Provisioned` phase

```bash
kubectl proxy &
curl -v -k -s -X PATCH -H "Accept: application/json, */*" \
    -H "Content-Type: application/merge-patch+json" \
    http://127.0.0.1:8001/apis/machine.openshift.io/v1beta1/namespaces/openshift-machine-api/machines/{failed-machine-name}/status/ \
    --data '{"status":{"phase":"Provisioned"}}
```
