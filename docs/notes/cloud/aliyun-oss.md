# Aliyun/AlibabaCloud OSS (Object Storage)

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

## HowTos

### Delete unused buckets

Delete unused buckets prefixed with a string defined on `${FORCE_DELETE}`.


```bash

{
    FORCE_DELETE=true
    FILTER_PREFIX="test-"
    mapfile -t ALL_BUCKETS_REGION_NAME < <(aliyun oss ls --region us-east-1 |egrep ^'[0-9]{4}' |awk '{print$5";"$7}')
    echo "# Total buckets found: ${#ALL_BUCKETS_REGION_NAME[@]}"
    echo "# Applying the filter [${FILTER_PREFIX}]"
    for BRN in ${ALL_BUCKETS_REGION_NAME[@]}; do
        # drop oss- from region name
        b_region="$(echo ${BRN} |awk -F';' '{print$1}' |awk -F'oss-' '{print$2}')"
        # drop oss:// to the bucket name to filter
        b_name="$(echo ${BRN} | awk -F';' '{print$2}' |awk -F'oss://' '{print$2}')"
        if [[ ${b_name} == ${FILTER_PREFIX}* ]]; then
            echo "## Sending delete to bucket [${b_name}] on region [${b_region}]"
            if [[ ${FORCE_DELETE} == true ]]; then
                echo "##> Forcing delete.."
                aliyun oss rm \
                    --region ${b_region} \
                    --bucket oss://${b_name} --force
            else
                aliyun oss rm \
                    --region ${b_region} \
                    --bucket oss://${b_name}
            fi
        fi
    done
}

```
