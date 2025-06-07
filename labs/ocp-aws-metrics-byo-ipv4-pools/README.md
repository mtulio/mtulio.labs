# Lambda / AWS IPv4 Pool metrics builder

Lambda function to scrap the information (address count) from Public IPv4 Pools from
CI account in the given regions, and publish as a custom metric in CloudWatch.

## Deploy Lambda function

Setup the required credentials and deploy the function in your default region.
You must set the variables `METRICS_REGION` and `REGIONS` to the desired value
when using different than `us-east-1`, where:

- `METRICS_REGION`: is the region when the metrics will be published
- `REGIONS`: is the regions you would like to the function to discover Public IPv4 Pools.

Steps:

- Create required IAM

```sh
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
FUNCTION_NAME=OpenShiftByoIPv4PoolMetrics

aws iam create-policy --region $AWS_REGION --policy-name OcpByoIpMetricsBuilderLambdaPolicy --policy-document file://./hack/iam-policy-document.json

aws iam create-role --region $AWS_REGION --role-name OcpByoIpMetricsBuilderLambdaRole --assume-role-policy-document file://./hack/iam-trust-policy.json

aws iam attach-role-policy --region $AWS_REGION --role-name OcpByoIpMetricsBuilderLambdaRole --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/OcpByoIpMetricsBuilderLambdaPolicy
```

- Create the function:

```sh
zip function.zip handler.py
aws lambda create-function --function-name $FUNCTION_NAME \
--runtime python3.12 \
--role arn:aws:iam::$AWS_ACCOUNT_ID:role/OcpByoIpMetricsBuilderLambdaRole \
--handler handler.lambda_handler \
--zip-file fileb://function.zip \
--region $AWS_REGION
```

- Test/Inoke

```sh
aws lambda invoke --function-name $FUNCTION_NAME outputfile.txt
```

- Deploy the scheduler to call the fcuntion every 5 minutes

```sh
aws events put-rule --name "${FUNCTION_NAME}TriggerEvery5Minutes" --schedule-expression 'rate(5 minutes)'

aws events put-targets --rule "${FUNCTION_NAME}TriggerEvery5Minutes" --targets "Id"="1","Arn"="arn:aws:lambda:us-east-1:$AWS_ACCOUNT_ID:function:${FUNCTION_NAME}"

aws lambda add-permission --function-name $FUNCTION_NAME --statement-id "EventBridgeInvoke" --action "lambda:InvokeFunction" --principal "events.amazonaws.com" --source-arn arn:aws:events:us-east-1:$AWS_ACCOUNT_ID:rule/"${FUNCTION_NAME}TriggerEvery5Minutes" 
```

## Devel

- Call it locally

```sh
export METRICS_REGION=us-east-1
export REGIONS=us-east-1
AWS_PROFILE=my-profile-with-public-pools python3 ./devel-call.py

# or just collect periodically (/5m)
while true; do AWS_PROFILE=ci-openshift python3 devel-call.py ; sleep 300; date; done
```

- [Example][example] plotting the metrics in the CloudWatch graph

[example]: https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#metricsV2?graph=~(metrics~(~(~'CustomMetrics~'TotalAvailableAddressCount~'PoolId~'ipv4pool-ec2-0768267342e327ea9~'NetworkBorderGroup~'us-east-1~(color~'*232ca02c~id~'m1))~(~'.~'TotalAddressCount~'.~'.~'.~'.~(color~'*231f77b4~id~'m2)))~sparkline~false~view~'timeSeries~stacked~false~region~'us-east-1~stat~'Average~period~60~start~'-PT3H~end~'P0D~title~'Public*20IPv4*20Pools~setPeriodToTimeRange~true~legend~(position~'right)~liveData~false~yAxis~(left~(min~100)~right~(showUnits~true)))&query=~'*7bCustomMetrics*2cNetworkBorderGroup*2cPoolId*7d*20MetricName*3d*22TotalAvailableAddressCount*22
