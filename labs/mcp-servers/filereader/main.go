package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type FileInfo struct {
	Name     string `json:"name"`
	Path     string `json:"path"`
	Size     int64  `json:"size"`
	Contents string `json:"contents,omitempty"`
}

type Summary struct {
	WordCount int    `json:"word_count"`
	Lines     int    `json:"lines"`
	Preview   string `json:"preview"`
}

const defaultBaseDir = "../../../docs/guides"

func main() {
	// Define the base directory for file operations
	//baseDir := "../../../docs"
	if err := os.MkdirAll(defaultBaseDir, 0755); err != nil {
		log.Fatalf("Failed to create base directory: %v", err)
	}

	// Define HTTP routes
	http.HandleFunc("/", DummyRootHandler)
	http.HandleFunc("/files", listFilesHandler)
	http.HandleFunc("/files/", fileHandler)
	http.HandleFunc("/summary/", summaryHandler)
	http.HandleFunc("/events", eventsHandler)
	http.HandleFunc("/events/", eventsHandler)

	// Start the server
	port := ":8080"
	fmt.Printf("Server starting on port %s\n", port)
	if err := http.ListenAndServe(port, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

func setHeaders(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
}

func DummyRootHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Printf("Received request root: %s %s\n", r.Method, r.URL.Path)
	setHeaders(w, r)

	// If Accept header contains text/event-stream, handle as SSE
	if strings.Contains(r.Header.Get("Accept"), "text/event-stream") {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		w.WriteHeader(http.StatusOK)

		// Get the flush interface if available
		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "Streaming unsupported!", http.StatusInternalServerError)
			return
		}

		// Send initial connection established message
		fmt.Fprintf(w, "event: connected\ndata: {\"status\":\"connected\"}\n\n")
		flusher.Flush()

		// Create a channel to detect client disconnect
		notify := w.(http.CloseNotifier).CloseNotify()

		// Keep the connection alive with heartbeat
		ticker := time.NewTicker(15 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-notify:
				fmt.Println("Client disconnected")
				return
			case <-ticker.C:
				fmt.Fprintf(w, "event: heartbeat\ndata: {\"time\":\"%s\"}\n\n", time.Now().Format(time.RFC3339))
				flusher.Flush()
			}
		}
	} else {
		// Regular HTTP request
		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	}
}

func listFilesHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Printf("Received request: %s %s\n", r.Method, r.URL.Path)

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	files, err := ioutil.ReadDir(defaultBaseDir)
	if err != nil {
		http.Error(w, "Failed to read directory", http.StatusInternalServerError)
		return
	}

	var fileInfos []FileInfo
	for _, file := range files {
		if !file.IsDir() {
			fileInfos = append(fileInfos, FileInfo{
				Name: file.Name(),
				Path: filepath.Join(defaultBaseDir, file.Name()),
				Size: file.Size(),
			})
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(fileInfos)
}

func eventsHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Printf("Received request: %s %s\n", r.Method, r.URL.Path)
	setHeaders(w, r)

	// Set headers for SSE
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)

	// Get the flush interface if available
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming unsupported!", http.StatusInternalServerError)
		return
	}

	// Send initial connection established message
	fmt.Fprintf(w, "event: connected\ndata: {\"status\":\"connected\"}\n\n")
	flusher.Flush()

	// Create a channel to detect client disconnect
	notify := w.(http.CloseNotifier).CloseNotify()

	// Keep the connection alive with heartbeat
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-notify:
			fmt.Println("Client disconnected")
			return
		case <-ticker.C:
			fmt.Fprintf(w, "event: heartbeat\ndata: {\"time\":\"%s\"}\n\n", time.Now().Format(time.RFC3339))
			flusher.Flush()
		}
	}
}

func fileHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Printf("Received request: %s %s\n", r.Method, r.URL.Path)

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Extract filename from URL
	filename := strings.TrimPrefix(r.URL.Path, "/files/")
	if filename == "" {
		http.Error(w, "Filename required", http.StatusBadRequest)
		return
	}

	// Read file contents
	content, err := ioutil.ReadFile(filepath.Join(defaultBaseDir, filename))
	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}

	fileInfo := FileInfo{
		Name:     filename,
		Path:     filepath.Join(defaultBaseDir, filename),
		Size:     int64(len(content)),
		Contents: string(content),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(fileInfo)
}

func summaryHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Printf("Received request: %s %s\n", r.Method, r.URL.Path)

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Extract filename from URL
	filename := strings.TrimPrefix(r.URL.Path, "/summary/")
	if filename == "" {
		http.Error(w, "Filename required", http.StatusBadRequest)
		return
	}

	// Read file contents
	content, err := ioutil.ReadFile(filepath.Join(defaultBaseDir, filename))
	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}

	// Create summary
	text := string(content)
	words := strings.Fields(text)
	lines := strings.Split(text, "\n")

	// Get first 100 characters as preview
	preview := text
	if len(preview) > 100 {
		preview = preview[:100] + "..."
	}

	summary := Summary{
		WordCount: len(words),
		Lines:     len(lines),
		Preview:   preview,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(summary)
}
