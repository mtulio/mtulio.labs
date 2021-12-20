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

- create the file `htpasswd-idp.yaml` with IdP object
``` yaml
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
```

- apply the config
``` shell
oc apply -f htpasswd-idp.yaml
```

- grant permissions to the user
``` shell
oc adm policy add-cluster-role-to-user admin user
```

## Reference

- [OpenShift docs](https://docs.openshift.com/container-platform/4.9/authentication/identity_providers/configuring-htpasswd-identity-provider.html#configuring-htpasswd-identity-provider)



