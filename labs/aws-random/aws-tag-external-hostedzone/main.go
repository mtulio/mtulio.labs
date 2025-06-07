package main

import (
	"context"
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/route53"
	"github.com/davecgh/go-spew/spew"
)

func main() {
	awsRegion := os.Getenv("LAB_AWS_REGION")
	cfg := aws.NewConfig().WithRegion(awsRegion).WithCredentialsChainVerboseErrors(true)

	sess := session.Must(session.NewSession(cfg))
	spew.Println("Attempting tagging with default session")
	tagPHZ(sess)

	xvpcOpts := session.Options{Config: *cfg, Profile: "openshift-shared-vpc", SharedConfigState: session.SharedConfigEnable}
	xvpcSess := session.Must(session.NewSessionWithOptions(xvpcOpts))
	spew.Println("Attempting tagging with named profile to assume role in phz account")
	tagPHZ(xvpcSess)

}

func tagPHZ(sess *session.Session) {
	route53Client := route53.New(sess)
	tagPrefix := os.Getenv("LAB_KEY_PREFIX")
	hostedZoneID := os.Getenv("LAB_HOSTEDZONE")

	if _, err := route53Client.ChangeTagsForResourceWithContext(context.TODO(), &route53.ChangeTagsForResourceInput{
		ResourceType: aws.String("hostedzone"),
		ResourceId:   aws.String(hostedZoneID),
		AddTags: []*route53.Tag{{
			Key:   aws.String(fmt.Sprintf("%s-shared-vpc-key", tagPrefix)),
			Value: aws.String(fmt.Sprintf("%s-shared-vpc-value", tagPrefix)),
		}},
	}); err != nil {
		spew.Println("===ERROR===")
		spew.Dump(err)
	} else {
		spew.Println("Success!")
	}
}
