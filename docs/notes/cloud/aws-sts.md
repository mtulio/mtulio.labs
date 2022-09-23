# notes | aws sts


## Using regional endpoints

> https://docs.aws.amazon.com/sdkref/latest/guide/feature-sts-regionalized-endpoints.html

### AWS-CLI

- Validate using global config

```bash
$ cat ~/.aws/config 
[default]
region = us-east-1

$ aws sts get-caller-identity --debug 2>&1 | grep 'MainThread - botocore.endpoint - DEBUG - Making request' | awk -F "url': " '{print$2}' | cut -f1 -d ' '
'https://sts.amazonaws.com/',

$ cat ~/.aws/config 
[default]
sts_regional_endpoints=regional
region = us-east-1

$ aws sts get-caller-identity --debug 2>&1 | grep 'MainThread - botocore.endpoint - DEBUG - Making request' | awk -F "url': " '{print$2}' | cut -f1 -d ' '
'https://sts.us-east-1.amazonaws.com/',
```

- Validate using environment variable

```bash
$ cat ~/.aws/config 
[default]
region = us-east-1

$ aws sts get-caller-identity --debug 2>&1 | grep 'MainThread - botocore.endpoint - DEBUG - Making request' | awk -F "url': " '{print$2}' | cut -f1 -d ' '
'https://sts.amazonaws.com/',

$ AWS_STS_REGIONAL_ENDPOINTS=regional aws sts get-caller-identity --debug 2>&1 | grep 'MainThread - botocore.endpoint - DEBUG - Making request' | awk -F "url': " '{print$2}' | cut -f1 -d ' '
'https://sts.us-east-1.amazonaws.com/',

```

### python SDK (boto3)

- Create the script (`boto-session`)

```python
import logging
import boto3
  
if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG,format=f'%(asctime)s %(levelname)s %(message)s')
    logger = logging.getLogger()
    cli = boto3.client('sts')
    print(cli.get_caller_identity())
```

- Validate using global config

```bash
$ cat ~/.aws/config 
[default]
region = us-east-1

$ python3 boto-session.py 2>&1 | grep 'Sending http request:' | awk -F "url=" '{print$2}' | cut -f1 -d ' '
https://sts.amazonaws.com/,


$ cat ~/.aws/config 
[default]
sts_regional_endpoints=regional
region = us-east-1

$ python3 boto-session.py 2>&1 | grep 'Sending http request:' | awk -F "url=" '{print$2}' | cut -f1 -d ' '
https://sts.us-east-1.amazonaws.com/,
```

- Validate using environment variable

```bash
$ python3 boto-session.py 2>&1 | grep 'Sending http request:' | awk -F "url=" '{print$2}' | cut -f1 -d ' '
https://sts.amazonaws.com/,


$ AWS_STS_REGIONAL_ENDPOINTS=regional python3 boto-session.py 2>&1 | grep 'Sending http request:' | awk -F "url=" '{print$2}' | cut -f1 -d ' '
https://sts.us-east-1.amazonaws.com/,
```
