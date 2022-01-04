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

## User

### Listing users

- List users
```shell
aliyun ram ListUsers --MaxItems 1000 |jq .Users.User[].UserName
```

- Count users

```bash
aliyun ram ListUsers --MaxItems 1000 |jq .Users.User[].UserName  |wc -l
```

- Filter user by name prefix

```bash
aliyun ram ListUsers --MaxItems 1000 |jq -r ".Users.User[] | select (.UserName |contains(\"${USER_PREFIX}\") )"
```

- Double filter user by name prefix AND fixed string `-openshift-machine-api`

```bash
aliyun ram ListUsers --MaxItems 1000 |jq -r ".Users.User[] | select (.UserName |contains(\"${USER_PREFIX}\")) | select (.UserName |contains(\"-openshift-machine-api\")) |.UserName"
```

### Cleaning users

```bash
{
    FILTER1="mrb"
    FILTER2="-openshift-"
    mapfile -t RAM_USERS_TO_DELETE < <(aliyun ram ListUsers --MaxItems 1000 |jq -r ".Users.User[] | select (.UserName |contains(\"${FILTER1}\")) | select (.UserName |contains(\"${FILTER2}\")) |.UserName")
    echo "Total users to be deleted: ${#RAM_USERS_TO_DELETE[@]}"
    for USR in ${RAM_USERS_TO_DELETE[@]}; do
    echo "# Deleting users [${USR}]..."
    echo "## Deleting policies from User..."
    mapfile -t RAM_USER_POLICY_TO_DELETE < <(aliyun ram ListPoliciesForUser \
        --UserName ${USR} \
        | jq -r '.Policies.Policy[] | (.PolicyName, .PolicyType, .DefaultVersion)')
    
    # Removing policy when it exists
    if [[ ${#RAM_USER_POLICY_TO_DELETE[@]} -gt 0 ]]; then
        # Considering only one policy by user
        POL_NAME=${RAM_USER_POLICY_TO_DELETE[0]}
        POL_TYPE=${RAM_USER_POLICY_TO_DELETE[1]}
        POL_VERS=${RAM_USER_POLICY_TO_DELETE[2]}
        echo "### User Policy found: type=[${POL_TYPE}] Name=[${POL_NAME}] version=[${POL_VERS}]"
        echo "### Detaching Policy from User..."
        aliyun ram DetachPolicyFromUser \
            --UserName ${USR} \
            --PolicyName ${POL_NAME} \
            --PolicyType ${POL_TYPE}
        echo "### Deleting Custom Policy..."
        aliyun ram DeletePolicy \
            --PolicyName ${POL_NAME}
    fi
    echo "### Removing User access keys..."
    for UAK in $(aliyun ram ListAccessKeys --UserName ${USR} | jq -r '.AccessKeys.AccessKey[].AccessKeyId'); do
        echo "### Removing User access key=[${UAK}]..."
        aliyun ram DeleteAccessKey \
            --UserName ${USR} \
            --UserAccessKeyId ${UAK};
    done
    echo "### Removing User..."
    aliyun ram DeleteUser \
        --UserName ${USR}

    done
} | tee -a aliyun-user-cleaner.log
```
