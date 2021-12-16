# Aliyun/AlibabaCloud RAM / IAM

## RAM / IAM

- Get help for each RAM API

> `aliyun ram <ApiName> --help`

``` bash
aliyun ram help
```

- Some examples

``` bash
aliyun ram GetPolicy \
    --PolicyName mycluster-machine-api-credentials-policy \
    --PolicyType Custom \
    | jq  -r '.DefaultPolicyVersion.PolicyDocument' | jq .

aliyun ram ListPoliciesForUser \
    --UserName mycluster-machine-api-credentials-policy \
    | jq -r '.Policies.Policy[] | (.PolicyName, .DefaultVersion)'

aliyun ram ListAccessKeys \
    --UserName mycluster-machine-api-credentials \
    | jq -r '.AccessKeys.AccessKey[]';
```
