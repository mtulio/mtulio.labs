//
// insights-ocp-etd-logs parses the logs of etcd from stdin
//  grep 'apply request took too long' \
//  	must-gather.local.*/*/namespaces/openshift-etcd/pods/*/etcd/etcd/logs/current.log  \
//      | awk -F'Z ' '{print$2}'  |jq .took | binary
//
package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"text/tabwriter"
)

var (
	data    []float64
	buckets = map[string][]float64{
		"low-200": []float64{},
		"200-300": []float64{},
		"300-400": []float64{},
		"400-500": []float64{},
		"500-600": []float64{},
		"600-700": []float64{},
		"700-800": []float64{},
		"800-900": []float64{},
		"900-1s":  []float64{},
		"1s-inf":  []float64{},
		"all":     []float64{},
	}
	buckets500 = map[string][]float64{
		"low-200": []float64{},
		"200-300": []float64{},
		"300-400": []float64{},
		"400-500": []float64{},
		"500-inf": []float64{},
		"all":     []float64{},
	}
)

func insertBucket(v float64) {
	switch {
	case v < 200.0:
		k := "low-200"
		buckets[k] = append(buckets[k], v)
		buckets500[k] = append(buckets500[k], v)
	case ((v >= 200.0) && (v <= 299.0)):
		k := "200-300"
		buckets[k] = append(buckets[k], v)
		buckets500[k] = append(buckets500[k], v)
	case ((v >= 300.0) && (v <= 399.0)):
		k := "300-400"
		buckets[k] = append(buckets[k], v)
		buckets500[k] = append(buckets500[k], v)
	case ((v >= 400.0) && (v <= 499.0)):
		k := "400-500"
		buckets[k] = append(buckets[k], v)
		buckets500[k] = append(buckets500[k], v)
	case ((v >= 500.0) && (v <= 599.0)):
		k := "500-600"
		buckets[k] = append(buckets[k], v)
		k = "500-inf"
		buckets500[k] = append(buckets500[k], v)
	case ((v >= 600.0) && (v <= 699.0)):
		k := "600-700"
		buckets[k] = append(buckets[k], v)
		k = "500-inf"
		buckets500[k] = append(buckets500[k], v)
	case ((v >= 700.0) && (v <= 799.0)):
		k := "700-800"
		buckets[k] = append(buckets[k], v)
		k = "500-inf"
		buckets500[k] = append(buckets500[k], v)
	case ((v >= 800.0) && (v <= 899.0)):
		k := "800-900"
		buckets[k] = append(buckets[k], v)
		k = "500-inf"
		buckets500[k] = append(buckets500[k], v)
	case ((v >= 900.0) && (v <= 999.0)):
		k := "900-1s"
		buckets[k] = append(buckets[k], v)
		k = "500-inf"
		buckets500[k] = append(buckets500[k], v)
	case (v >= 1000.0):
		k := "1s-inf"
		buckets[k] = append(buckets[k], v)
		k = "500-inf"
		buckets500[k] = append(buckets500[k], v)
	default:
		k := "unkw"
		buckets[k] = append(buckets[k], v)
		buckets500[k] = append(buckets500[k], v)
	}
	k := "all"
	buckets[k] = append(buckets[k], v)
	buckets500[k] = append(buckets500[k], v)
}

func main() {

	rMili, _ := regexp.Compile("([0-9]+.[0-9]+)ms")
	rSec, _ := regexp.Compile("([0-9]+.[0-9]+)s")

	s := bufio.NewScanner(os.Stdin)
	for s.Scan() {
		line := s.Text()
		// Extract milisseconds
		if match := rMili.MatchString(line); match {
			matches := rMili.FindStringSubmatch(line)
			if len(matches) == 2 {
				if v, err := strconv.ParseFloat(matches[1], 64); err == nil {
					data = append(data, v)
					insertBucket(v)
				}
			}
			// Extract seconds
		} else if match := rSec.MatchString(line); match {
			matches := rSec.FindStringSubmatch(line)
			if len(matches) == 2 {
				if v, err := strconv.ParseFloat(matches[1], 64); err == nil {
					v = v * 1000
					insertBucket(v)
				}
			}
		} else {
			fmt.Printf("No bucket for: %v\n", line)
		}

	}

	tbWriter := tabwriter.NewWriter(os.Stdout, 0, 8, 1, '\t', tabwriter.AlignRight)
	show := func(k string) {
		v := buckets[k]
		perc := fmt.Sprintf("(%.3f %%)", (float64(len(v))/float64(len(buckets["all"])))*100)
		if k == "all" {
			perc = ""
		}
		fmt.Fprintf(tbWriter, "%s\t %d\t%s\n", k, len(v), perc)
	}
	show("all")
	v500 := buckets500["500-inf"]
	fmt.Fprintf(tbWriter, ">500ms\t %d\t(%.3f %%)\n", len(v500), (float64(len(v500))/float64(len(buckets500["all"])))*100)
	fmt.Fprintf(tbWriter, "---\n")
	show("low-200")
	show("200-300")
	show("300-400")
	show("400-500")
	show("500-600")
	show("600-700")
	show("700-800")
	show("800-900")
	show("900-1s")
	show("1s-inf")
	show("unkw")

	tbWriter.Flush()
}
