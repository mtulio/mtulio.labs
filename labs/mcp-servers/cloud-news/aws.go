package main

import (
	"log"
	"net/http"
	"os"
	"time"

	serverlessAPI "github.com/mtulio/mtulio.labs-devel/api/news"
)

func loggingMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Printf("[DEBUG] Incoming request: Method=%s, URL=%s, Headers=%v\n", r.Method, r.URL, r.Header)
		next.ServeHTTP(w, r)
	}
}

// This program starts an http server exposing the serverless API
// used in the Vercel serverless platform in mtulio.labs.
// This program is merely to be used in the local development,
// instead of remote serverless API.
func main() {
	// Enable detailed logging
	log.SetOutput(os.Stdout)
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds | log.Lshortfile)

	// Create custom server with longer timeouts
	server := &http.Server{
		Addr:              ":8080",
		ReadTimeout:       30 * time.Second,
		ReadHeaderTimeout: 30 * time.Second,
		WriteTimeout:      30 * time.Minute, // Long timeout for SSE
		IdleTimeout:       60 * time.Second,
	}

	// Wrap handler with logging middleware
	http.HandleFunc("/api/news/aws", loggingMiddleware(serverlessAPI.Handler))

	log.Printf("[INFO] Starting server on port 8080...\n")
	err := server.ListenAndServe()
	if err != nil {
		log.Fatalf("[ERROR] Error starting server: %v", err)
	}

	// Start the server
	// if err := serverlessAPI.Server.Serve(); err != nil {
	// 	log.Fatal(err)
	// }
}
