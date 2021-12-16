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
