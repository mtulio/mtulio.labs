# OCP on AWS - Interrupt Spot instances with FIS

This guide shows how to create a AWS FIS (Fault Injection Service) experiment to interrupt spot instances in OpenShift clusters running on AWS.

The experiment creates a rule to trigger the spot interruption signal for N nodes matching
the kubernetes cluster tags (used by default in OpenShift clusters).

## Prerequisites

- AWS CLI installed
- AWS Permissions to create CloudFormation stack setting IAM capabilities
- OpenShift cluster installed on AWS with instance SPOT lifecycle created (machineset)
- **Each group of instances (MachineSet) must be created with EC2 Tag `fis:spot-interrupt` to match the FIS experiment.**

## Steps

Steps to run it:

- Download the CloudFormation template to create the experiment:

```sh
curl -Lso ./50_fips_spot_interruption.yaml https://raw.githubusercontent.com/mtulio/mtulio.labs/master/labs/ocp-install-iac/aws-cloudformation-templates/50_fips_spot_interruption.yaml
```

- Create the CloudFormation stack targetting the cluster:

```sh
# Create the experiment triggering many spot instances (100)
## Time before Interrupt in minutes
BEFORE_INTERRUPTION_TIME=2
SPOT_INSTANCE_COUNT=10
TEMPLATE_PATH=file://./50_fips_spot_interruption.yaml
# TEMPLATE_PATH=file://./labs/ocp-install-iac/aws-cloudformation-templates/50_fips_spot_interruption.yaml
aws cloudformation create-stack \
    --region ${AWS_REGION} \
    --stack-name "${INFRA_ID}-spot-interrupt" \
    --template-body ${TEMPLATE_PATH} \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=InstancesToInterrupt,ParameterValue=${SPOT_INSTANCE_COUNT} \
        ParameterKey=DurationBeforeInterruption,ParameterValue=${BEFORE_INTERRUPTION_TIME}

aws cloudformation wait stack-create-complete \
    --region ${AWS_REGION} \
    --stack-name "${INFRA_ID}-spot-interrupt"

aws cloudformation describe-stacks \
    --region ${AWS_REGION} \
    --stack-name "${INFRA_ID}-spot-interrupt" \
    --query 'Stacks[]'
```

- Run the experiment

```sh
export EXPERIMENT_TEMPLATE_ID=$(aws cloudformation describe-stacks --region ${AWS_REGION} \
    --stack-name "${INFRA_ID}-spot-interrupt"  \
    --query 'Stacks[].Outputs[?OutputKey==`FISExperimentTemplateID`][].OutputValue' \
    --output text)

aws fis start-experiment --experiment-template-id $EXPERIMENT_TEMPLATE_ID
```

- Check the experiments:

    - AWS Console: https://us-east-1.console.aws.amazon.com/fis/home?region=us-east-1#Experiments
    - CLI:

```sh
EXPERIMENT_ID=$(aws fis list-experiments \
    | jq -r ".experiments[] \
        | select (.state.status==\"completed\") \
        | select(.experimentTemplateId==\"$EXPERIMENT_ID\").id")

# Show the experiment (tip: AWS Console shows nodes affected, the CLI is not returning it.)
aws fis get-experiment --id $EXPERIMENT_ID
```

References:

- https://docs.aws.amazon.com/fis/latest/userguide/fis-actions-reference.html#send-spot-instance-interruptions
- https://ec2spotworkshops.com/karpenter/060_scaling/fis_experiment.html
- https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-fis-experimenttemplate.html#cfn-fis-experimenttemplate-actions