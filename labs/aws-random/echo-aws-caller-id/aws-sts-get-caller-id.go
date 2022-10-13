package main

import (
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sts"
)

const (
	sleepIntervalSeconds time.Duration = 30
)

func main() {
	awsConfig := &aws.Config{
		MaxRetries: aws.Int(8),
	}

	awsConfig.WithLogLevel(aws.LogDebugWithHTTPBody)
	awsConfig.CredentialsChainVerboseErrors = aws.Bool(true)

	sess, err := session.NewSession(awsConfig)
	if err != nil {
		fmt.Printf("ERR creating session: %s\n", err.Error())
	}

	svc := sts.New(sess, awsConfig)
	for {
		input := &sts.GetCallerIdentityInput{}
		result, err := svc.GetCallerIdentity(input)
		if err != nil {
			if aerr, ok := err.(awserr.Error); ok {
				switch aerr.Code() {
				default:
					fmt.Println(aerr.Error())
				}
			} else {
				// Print the error, cast err to awserr.Error to get the Code and
				// Message from an error.
				fmt.Println(err.Error())
			}
			return
		}
		fmt.Println(result)
		fmt.Printf("Sleeping for %d seconds...\n", sleepIntervalSeconds)
		time.Sleep(sleepIntervalSeconds * time.Second)
	}

}
