# OCP Identity Provider

## Creating IdP htpass

- create the htpasswd

``` shell
htpasswd -c -B -b htpasswd.users user myp@ss
```

- create the secret based on htpass file
``` shell
oc create secret generic htpass-secret \
    --from-file=htpasswd=htpasswd.users \
    -n openshift-config 
```

- create IdP object
``` shell
cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: my_htpasswd_provider 
    mappingMethod: claim 
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret 
EOF
```

- create the user

```shell
oc create user user
```

- grant permissions to the user
``` shell
oc adm policy add-cluster-role-to-user admin user
```

- Login to the cluster

## Reference

- [OpenShift docs](https://docs.openshift.com/container-platform/4.9/authentication/identity_providers/configuring-htpasswd-identity-provider.html#configuring-htpasswd-identity-provider)



