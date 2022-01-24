# Aliyun/AlibabaCloud ResourceManager | Notes

## Examples
### Cleaner

```bash
{
    FILTER1="lab2"
    FILTER_STATUS_="OK"
    mapfile -t RG_TO_DELETE < <(aliyun resourcemanager ListResourceGroups  --endpoint resourcemanager.aliyuncs.com |jq -r ".ResourceGroups.ResourceGroup[] | select (.Status==\"${FILTER_STATUS_}\") | select (.Name |contains(\"${FILTER1}\")) |.Id")
    echo "# Total Resource Groups to be deleted: ${#RG_TO_DELETE[@]}"

    for RG_ID in ${RG_TO_DELETE[@]}; do
        echo "# Getting the RG [${RG_ID}]..."
        aliyun resourcemanager ListResourceGroups  --endpoint resourcemanager.aliyuncs.com |jq -r ".ResourceGroups.ResourceGroup[] | select (.Id |contains(\"${RG_ID}\")) | (.Id, .Name)"

        echo "# Deleting policy [${RG_ID}]..."
        aliyun resourcemanager DeleteResourceGroup --ResourceGroupId ${RG_ID} --endpoint resourcemanager.aliyuncs.com
    done
} | tee -a aliyun-rg-cleaner.log
```
