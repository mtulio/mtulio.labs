# S3

## `aws cp`

- Copy files listing from output

> That's not the cost effective way

``` shell
BUCKET_NAME="mrbcco-oidc"
aws s3 ls "s3://${BUCKET_NAME}/_logs2021" \
    |awk '{print$4}' \
    |xargs -I % aws s3 cp s3://${BUCKET_NAME}/% logs
```

## Bucket Access Log

Exploring access log.

### Bucket access log

### Bucket access log parsers

- extract IP source from access log
``` shell
$ cat s3-access-log/*   |awk -F'] ' '{print$2}' |awk '{print$1}'|sort |uniq -c
      2 10.246.71.124
    131 18.4.3.2
```

- requests over the time

 cat s3-access-log-2/*   |awk -F'\[' '{print$2}' |awk '{print$1" "$3}' |awk -F':' '{print$1"-"$2"-"$3" "$4}' |awk '{print$1 " "$3}' |sort |uniq -c

- requests over the time with path

 cat s3-access-log-2/*   |awk -F'\[' '{print$2}' |awk '{print$1" "$3}' |awk -F':' '{print$1"-"$2"-"$3" "$4}' |awk '{print$1 " "$3}' |sort |uniq -c

### Cloud Trail S3 access

ToDo: steps to collect the Cloud Trail data.

- exploring all access to specific bucket

``` shell
BUCKET_NAME="mrbcco-oidc"
BUCKET_ARN="arn:aws:s3:::${BUCKET_NAME}"

jq -r ".Records[] \
    | select (.resources!=null) \
    | select(.resources[].ARN==\"${BUCKET_ARN}\") \
    | [ {requestUA: .userAgent, eventName: .eventName, eventType: .eventType, sourceIP: .sourceIPAddress} ]" cloud-trail-event-history-s3-v2.json
```

- filter access by User Agent

``` shell
BUCKET_NAME="mrbcco-oidc"
BUCKET_ARN="arn:aws:s3:::${BUCKET_NAME}"

$ jq -r ".Records[] \
    | select (.userAgent==\"AWS Internal\") \
    | select (.resources!=null) \
    | select(.resources[].ARN==\"${BUCKET_ARN}\") | ."  \
    cloud-trail-event-history-s3-v2.json
```

- filter access by IP

``` shell
BUCKET_NAME="mrbcco-oidc"
BUCKET_ARN="arn:aws:s3:::${BUCKET_NAME}"

$ jq -r ".Records[] \
    | select (.userAgent==\"AWS Internal\") \
    | [ {requestUA: .userAgent, eventName: .eventName, eventType: .eventType, sourceIP: .sourceIPAddress} ]"  \
    cloud-trail-event-history-s3-v2.json
```
