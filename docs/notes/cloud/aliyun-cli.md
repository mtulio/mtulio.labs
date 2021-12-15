# Aliyun/AlibabaCloud CLI

## Install

- Install CLI
Check the [doc](https://github.com/aliyun/aliyun-cli#installation).

- Check available regions:

```
./aliyun ecs DescribeRegions
```

- Configure

```
./aliyun configure
```

## Usage common

### RAM / IAM

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

### OSS / block storage

- Install [OSS CLI](https://partners-intl.aliyun.com/help/doc-detail/120075.htm)

- Configure

``` bash
./ossutil64 config
Please enter language(CH/EN, default is:EN, the configuration will go into effect after the command successfully executed):EN
Please enter endpoint:https://oss-us-east-1.aliyuncs.com
Please enter accessKeyID:X
Please enter accessKeySecret:Y
Please enter stsToken:
```

- list OSS buckets

```
$ ./ossutil64 ls oss://mybucket-test
```

## Reference

- [github project/src](https://github.com/aliyun/aliyun-cli)
- []()
- []()

