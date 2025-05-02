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
	w.WriteHeader(http.StatusOK)
	//w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Type", "text/plain")
	w.Write([]byte("OK"))
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
    w.Header().Set("Content-Type", "text/event-stream")
    w.WriteHeader(http.StatusOK)
	
    // Optionally, you can write a comment to keep the connection open
    fmt.Fprintf(w, ": keep-alive\n\n")
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