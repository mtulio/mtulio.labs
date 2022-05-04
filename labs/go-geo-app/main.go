package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
)

const (
	ip_api_url    string = "http://ip-api.com/json"
	serverAddress string = ":8000"
)

type GeoIP map[string]interface{}

// Get IP's Geo information from API
func getGeoIP(ip string) (*GeoIP, error) {

	resp, err := http.Get(fmt.Sprintf("%s/%s", ip_api_url, ip))
	if err != nil {
		log.Printf("Error getting caller IP info: %v\n", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		bodyBytes, err := io.ReadAll(resp.Body)
		if err != nil {
			log.Fatal(err)
		}
		var geo GeoIP
		json.Unmarshal(bodyBytes, &geo)
		return &geo, nil
	}
	return nil, nil
}

// http writer to
func geoLookup(w http.ResponseWriter, ip string) {
	geoData, err := getGeoIP(ip)
	if err != nil {
		msg := fmt.Sprintf("{\"error\":\"Unable to get results from GeoAPI API: %v\"}", err)
		fmt.Fprintf(w, "%s", msg)
		return
	}
	geo, err := json.Marshal(geoData)
	if err != nil {
		msg := fmt.Sprintf("{\"error\":\"Unable to parse results from GeoAPI API: %v\"}", err)
		fmt.Fprintf(w, "%s", msg)
		return
	}
	fmt.Fprintf(w, "%s", string(geo))
}

// Handler to discover the GeoIP for QueryString (?ip=<ip>), or
// discover from request (initially headers, them remote address).
func Handler(w http.ResponseWriter, r *http.Request) {

	ipQS, ok := r.URL.Query()["ip"]
	if ok && len(ipQS[0]) > 0 {
		geoLookup(w, ipQS[0])
		return
	}

	ip := r.Header.Get("X-Real-Ip")
	if ip != "" {
		geoLookup(w, ip)
		return
	}
	ip = r.Header.Get("X-Forward-For")
	if ip != "" {
		geoLookup(w, ip)
		return
	}
	ip = strings.Split(r.RemoteAddr, ":")[0]
	if ip != "127.0.0.1" {
		geoLookup(w, ip)
		return
	}

	geoLookup(w, "1.1.1.1")
}

func main() {
	http.HandleFunc("/", Handler)

	log.Printf("Listening to address %s\n", serverAddress)
	http.ListenAndServe(serverAddress, nil)
}
