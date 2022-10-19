//
// ocp-ci-query-flakes check flakes on CI
// $ cat sample-test.txt | ./ocp-ci-query-flakes
//
package main

import (
	"bufio"
	"fmt"
	"os"
	"text/tabwriter"
)

const (
	sippyAPITestURL = "https://sippy.dptools.openshift.org/api/tests"
)

type E2ETest struct {
	Name        string
	FlakesCount int64
}

type E2ETests []*E2ETest

var (
	data     []float64
	failures E2ETests
)

func insertFailure(name string) {
	failures = append(failures, &E2ETest{
		Name: name,
	})
}

func main() {

	s := bufio.NewScanner(os.Stdin)
	for s.Scan() {
		line := s.Text()
		insertFailure(line)

	}

	tbWriter := tabwriter.NewWriter(os.Stdout, 0, 8, 1, '\t', tabwriter.AlignRight)
	fmt.Fprintf(tbWriter, "Flakes\tPerc\t TestName\n")

	api := NewSippyAPI()

	// Fill the failures quering Sippy
	for _, f := range failures {
		resp, _ := api.QueryTests(&SippyTestsRequestInput{
			TestName: f.Name,
		})
		for _, r := range *resp {
			fmt.Fprintf(tbWriter, "%d\t%.3f%%\t%s\n", r.CurrentFlakes, r.CurrentFlakePerc, f.Name)
		}
	}

	tbWriter.Flush()
}
