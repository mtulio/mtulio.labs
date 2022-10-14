# OpenShift etcd

```bash
for node in $(oc get nodes -l node-role.kubernetes.io/master='' -o jsonpath='{.items[*].metadata.name}'); do \
    oc debug node/${node} -- chroot /host /bin/bash -c \
        "mkdir -p /var/lib/etcd/_test_perf;\
        podman run \
            --volume /var/lib/etcd/_test_perf:/var/lib/etcd:Z quay.io/openshift-scale/etcd-perf;\
            rm -rf /var/lib/etcd/_test_perf" \
        > ./results-${node}-fio_etcd.txt;\
done
```

## References

- [Blog/Ask an OpenShift Admin Office Hour - etcd: The heart of Kubernetes](https://cloud.redhat.com/blog/ask-an-openshift-admin-office-hour-etcd-the-heart-of-kubernetes)
- [KCS/How to Use 'fio' to Check Etcd Disk Performance in OCP](https://access.redhat.com/solutions/4885641)
- [KCS/Mounting separate disk for OpenShift 4 container storage](https://access.redhat.com/solutions/4952011)
- [DOC/Install/Creating a separate /var partition](https://docs.openshift.com/container-platform/4.6/installing/installing_azure/installing-azure-user-infra.html#installation-disk-partitioning-upi-templates_installing-azure-user-infra)
