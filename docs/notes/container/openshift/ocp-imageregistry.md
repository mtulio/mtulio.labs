# OpenShift Image Registry

## Storages

- Check current configuration:

```
oc get configs.imageregistry.operator.openshift.io/cluster \
    -n openshift-image-registry \
    -o jsonpath='{.spec.storage}' |jq .
```

### OSS (Alibaba object storage)

- Encrypt OSS storage

```
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/storage/oss","value":{"bucket":"test-mybucket-enc","region":"us-east-1","encryption":{"type":"KMS","kms":{"keyID":"MyMKSKeyID"}}}}]'
```

- Check the storage:

> [oss CLI](https://partners-intl.aliyun.com/help/doc-detail/120075.htm)

```
./ossutil64 ls oss://test-mybucket-enc
```

References:
- [Aliyun KMS](https://partners-intl.aliyun.com/help/doc-detail/189385.htm)
- [Docker Storage / OSS](https://docs.docker.com/registry/storage-drivers/oss/)
