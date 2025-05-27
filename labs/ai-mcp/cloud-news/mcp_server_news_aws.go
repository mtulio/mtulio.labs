package main

import (
	"log"
	"net/http"

	serverlessAPI "github.com/mtulio/mtulio.labs-devel/api/news"
)

// This program starts an http server exposing the serverless API
// used in the Vercel serverless platform in mtulio.labs.
// This program is merely to be used in the local development,
// instead of remote serverless API.
func main() {
	http.HandleFunc("/news", serverlessAPI.Handler)
	log.Println("Starting server on port 8080...")
	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		log.Fatalf("Error starting server: %v", err)
	}
}
