/*
Dummy http appcode to retrieve GeoIP information from client and server.
*/
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
	geoip_api_url string = "http://ip-api.com/json"
	pubip_api_url string = "https://mtulio.net/api/ip"
	serverAddress string = ":8000"
)

var (
	srvInfo *ServerInfo
)

type GeoIP map[string]interface{}

type Request struct {
	Headers interface{} `json:"headers"`
	User    string      `json:"user,omitempty"`
}

type ServerInfo struct {
	Address string `json:"address,omitempty"`
	GeoIP   *GeoIP `json:"geoIP,omitempty"`
}

type ClientInfo struct {
	Address string  `json:"address,omitempty"`
	GeoIP   *GeoIP  `json:"geoIP,omitempty"`
	Request Request `json:"request"`
}

type DistanceCliSrv struct {
	Kilometers    float64 `json:"kilometers"`
	Miles         float64 `json:"miles"`
	NauticalMiles float64 `json:"nauticalMiles"`
}

type Response struct {
	ServerInfo    *ServerInfo     `json:"serverInfo,omitempty"`
	ClientInfo    *ClientInfo     `json:"clientInfo,omitempty"`
	StatusMessage string          `json:"statusMessage,omitempty"`
	Distance      *DistanceCliSrv `json:"distance,omitempty"`
}

// Get IP's Geo information from API
func getPublicIP() (string, error) {

	resp, err := http.Get(pubip_api_url)
	if err != nil {
		log.Printf("Error getting caller IP info: %v\n", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		bodyBytes, err := io.ReadAll(resp.Body)
		if err != nil {
			log.Fatal(err)
		}

		return string(bodyBytes), nil
	}
	return fmt.Sprintf("Error#%d", resp.StatusCode), nil
}

// Get IP's Geo information from API
func getGeoIP(ip string) (*GeoIP, error) {

	resp, err := http.Get(fmt.Sprintf("%s/%s", geoip_api_url, ip))
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

func checkDistance(resp *Response) {

	gipCli := resp.ClientInfo.GeoIP
	gipSrv := resp.ServerInfo.GeoIP

	if (*gipCli)["status"].(string) != "success" {
		return
	}

	la1 := (*gipSrv)["lat"].(float64)
	lo1 := (*gipSrv)["lon"].(float64)
	la2 := (*gipCli)["lat"].(float64)
	lo2 := (*gipCli)["lon"].(float64)

	resp.Distance = &DistanceCliSrv{
		Kilometers:    calculateDistance(la1, lo1, la2, lo2, "K"),
		Miles:         calculateDistance(la1, lo1, la2, lo2, "M"),
		NauticalMiles: calculateDistance(la1, lo1, la2, lo2, "N"),
	}
}

func respHandlerGeo(w http.ResponseWriter, resp *Response, ip string) {
	var err error
	resp.ClientInfo.Address = ip
	resp.ClientInfo.GeoIP, err = getGeoIP(resp.ClientInfo.Address)
	if err != nil {
		msg := fmt.Sprintf("{\"error\":\"Unable to get results from GeoAPI API: %v\"}", err)
		fmt.Fprintf(w, "%s", msg)
		return
	}
	checkDistance(resp)

	re, err := json.Marshal(resp)
	if err != nil {
		msg := fmt.Sprintf("{\"error\":\"Unable to parse results from GeoAPI API: %v\"}", err)
		fmt.Fprintf(w, "%s", msg)
		return
	}

	log.Println(string(re))
	fmt.Fprintf(w, "%s", string(re))
}

// Handler to discover the GeoIP for QueryString (?ip=<ip>), or
// discover from request (initially headers, them remote address).
func HandlerGeo(w http.ResponseWriter, r *http.Request) {
	log.Println("Received /geo or /")
	var resp Response
	resp.ClientInfo = &ClientInfo{
		Request: Request{
			Headers: r.Header,
		},
	}
	resp.ServerInfo = srvInfo

	ipQS, ok := r.URL.Query()["ip"]
	if ok && len(ipQS[0]) > 0 {
		respHandlerGeo(w, &resp, ipQS[0])
		return
	}

	ip := r.Header.Get("X-Real-Ip")
	if ip != "" {
		respHandlerGeo(w, &resp, ip)
		return
	}
	ip = r.Header.Get("X-Forwarded-For")
	if ip != "" {
		respHandlerGeo(w, &resp, ip)
		return
	}
	ip = strings.Split(r.RemoteAddr, ":")[0]
	respHandlerGeo(w, &resp, ip)
}

// HandlerHealthCheck returns client request information
func HandlerEcho(w http.ResponseWriter, r *http.Request) {
	log.Println("Received /echo")
	var resp Response
	resp.ClientInfo = &ClientInfo{
		Request: Request{
			Headers: r.Header,
		},
	}
	resp.ClientInfo.Address = r.RemoteAddr

	re, err := json.Marshal(resp)
	if err != nil {
		msg := fmt.Sprintf("{\"error\":\"Unable to parse results from GeoAPI API: %v\"}", err)
		fmt.Fprintf(w, "%s", msg)
		return
	}

	fmt.Fprintf(w, "%s", string(re))
}

// HandlerHealthCheck returns simple server string to be used to probe healthy app
func HandlerHealthCheck(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "OK")
}

// Init server retrieving server address

func init() {
	log.Printf("Discovering PublicIP...\n")
	addr, err := getPublicIP()
	if err != nil {
		log.Printf("Error getting public ip address: %v", err)
	}

	log.Printf("Public IP Address discovered: %s\n", addr)

	log.Printf("Discovering GeoIP...\n")
	serverAddrGeoIP, err := getGeoIP(addr)
	if err != nil {
		log.Printf("Error getting GeoIP from Public address: %v", err)
	}
	log.Printf("GeoIP discovered: %v\n", serverAddrGeoIP)
	srvInfo = &ServerInfo{
		Address: addr,
		GeoIP:   serverAddrGeoIP,
	}
}

func main() {
	http.HandleFunc("/", HandlerGeo)
	http.HandleFunc("/geo", HandlerGeo)
	http.HandleFunc("/healthz", HandlerHealthCheck)
	http.HandleFunc("/echo", HandlerEcho)

	log.Printf("Listening to address %s\n", serverAddress)
	http.ListenAndServe(serverAddress, nil)
}
