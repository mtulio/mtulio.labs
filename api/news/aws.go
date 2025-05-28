package handler

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

type NewsItem struct {
	ID       string   `json:"id"`
	Date     string   `json:"date"`
	Headline string   `json:"headline"`
	Body     string   `json:"body"`
	Category string   `json:"category"`
	Products []string `json:"products"`
}

func fetchNews(category string) ([]NewsItem, error) {
	// Define the API endpoint
	url := "https://aws.amazon.com/api/dirs/items/search"

	// Define the query parameters
	params := map[string]string{
		"item.directoryId": "whats-new-v2",
		"sort_by":          "item.additionalFields.postDateTime",
		"sort_order":       "desc",
		"size":             "50",
		"item.locale":      "en_US",
	}

	// Optional: Add category filter
	if category != "" {
		params["tags.id"] = fmt.Sprintf("whats-new-v2#marketing-marchitecture#%s", category)
	}

	// Build query string
	query := []string{}
	for key, value := range params {
		query = append(query, fmt.Sprintf("%s=%s", key, value))
	}
	queryString := strings.Join(query, "&")

	// Define the headers
	headers := map[string]string{
		"accept":             "*/*",
		"accept-language":    "en-US,en;q=0.9",
		"user-agent":         "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
		"x-requested-with":   "XMLHttpRequest",
		"sec-ch-ua":          `"Google Chrome";v="135", "Not-A.Brand";v="8", "Chromium";v="135"`,
		"sec-ch-ua-mobile":   "?0",
		"sec-ch-ua-platform": `"Linux"`,
		"sec-fetch-dest":     "empty",
		"sec-fetch-mode":     "cors",
		"sec-fetch-site":     "same-origin",
		"priority":           "u=1, i",
		"referer":            "https://aws.amazon.com/new/?whats-new-content-all.sort-by=item.additionalFields.postDateTime&whats-new-content-all.sort-order=desc&awsf.whats-new-categories=marketing-marchitecture%23compute",
	}

	// Create HTTP request
	req, err := http.NewRequest("GET", fmt.Sprintf("%s?%s", url, queryString), nil)
	if err != nil {
		return nil, err
	}

	// Add headers to the request
	for key, value := range headers {
		req.Header.Add(key, value)
	}

	// Send the request
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	// fmt.Println(resp)
	// Check response status
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("failed to fetch data. Status code: %d", resp.StatusCode)
	}

	// Parse response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	// fmt.Println(body)
	var responseData map[string]interface{}
	err = json.Unmarshal(body, &responseData)
	if err != nil {
		fmt.Println("ERROR")
		return nil, err
	}
	// fmt.Println()
	// fmt.Println(responseData)
	// Extract and transform data
	items, ok := responseData["items"].([]interface{})
	if !ok {
		return nil, fmt.Errorf("invalid response format")
	}

	var newsItems []NewsItem
	for _, item := range items {
		itemMap := item.(map[string]interface{})
		header := itemMap["item"].(map[string]interface{})
		tags := itemMap["tags"].([]interface{})

		categoryData := "TBD"
		var products []string
		for _, tag := range tags {
			tagMap := tag.(map[string]interface{})
			if tagMap["tagNamespaceId"] == "whats-new-v2#marketing-marchitecture" {
				categoryData = tagMap["name"].(string)
			}
			if tagMap["tagNamespaceId"] == "whats-new-v2#general-products" {
				products = append(products, tagMap["name"].(string))
			}
		}

		additionalFields := header["additionalFields"].(map[string]interface{})
		headline := additionalFields["headline"].(string)
		postBody := additionalFields["postBody"].(string)

		// Ignore empty rows
		if headline == "" {
			continue
		}

		newsItems = append(newsItems, NewsItem{
			ID:       header["name"].(string),
			Date:     header["dateCreated"].(string),
			Headline: headline,
			Body:     postBody,
			Category: categoryData,
			Products: products,
		})

		// temp: collect only one item
		break
	}

	return newsItems, nil
}

// type AddArgs struct {
// 	A int `json:"a"`
// 	B int `json:"b"`
// }

// // var mcpHandler mcptransport.Handler
// var Server *mcp.Server

// // TimeArgs defines the arguments for the time tool
// type TimeArgs struct {
// 	Format string `json:"format" jsonschema:"description=The time format to use"`
// }

// func init() {
// 	transport := mcptransport.NewHTTPTransport("/mcp")
// 	transport.WithAddr(":8080")

// 	Server = mcp.NewServer(
// 		transport,
// 		mcp.WithName("mcp-golang-stateless-http-example"),
// 		mcp.WithInstructions("A simple example of a stateless HTTP server using mcp-golang"),
// 		mcp.WithVersion("0.0.1"),
// 	)

// 	// Register add tool
// 	err := Server.RegisterTool("add", "Add two numbers", func(args AddArgs) (*mcp.ToolResponse, error) {
// 		sum := args.A + args.B
// 		return mcp.NewToolResponse(mcp.NewTextContent(fmt.Sprintf("%d", sum))), nil
// 	})
// 	if err != nil {
// 		panic(err)
// 	}

// 	// Register time tool
// 	err = Server.RegisterTool("time", "Returns the current time in the specified format", func(args TimeArgs) (*mcp.ToolResponse, error) {
// 		format := args.Format
// 		return mcp.NewToolResponse(mcp.NewTextContent(time.Now().Format(format))), nil
// 	})
// 	if err != nil {
// 		panic(err)
// 	}
// }

// Vercel entry point
// func Handler(w http.ResponseWriter, r *http.Request) {
// 	mcpHandler.ServeHTTP(w, r)
// }

// type MCPMessage struct {
// 	Type string          `json:"type"`
// 	Data json.RawMessage `json:"data,omitempty"`
// }

// type Tool struct {
// 	Name        string `json:"name"`
// 	Description string `json:"description"`
// }

func Handler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	// Check if the query string ?json is added
	outputJson := false
	query := r.URL.Query()
	if _, ok := query["json"]; ok {
		outputJson = true
	}
	writeData := func(content []byte) {
		if outputJson {
			fmt.Fprintf(w, "%s", content)
		} else {
			fmt.Fprintf(w, "data: %s\n\n", content)
		}
	}

	// Allow browsers which does not support SSE to run through arg no-sse.
	// Vercel does not support Server-Sent Events (SSE)
	unsupportedSSE := false
	if _, ok := query["no-sse"]; ok {
		unsupportedSSE = true
	}
	flusher, ok := w.(http.Flusher)
	if !unsupportedSSE && !ok {
		http.Error(w, "SSE not supported", http.StatusInternalServerError)
		return
	}
	flusherFunc := func() {
		if !unsupportedSSE {
			flusher.Flush()
		}
	}

	// 1. Send the correct initialization message
	initResp := map[string]interface{}{
		"jsonrpc": "2.0",
		"id":      1,
		"result": map[string]interface{}{
			"capabilities": map[string]interface{}{
				"completion": true,
			},
			"tools": []map[string]interface{}{
				{
					"name":        "aws_news",
					"description": "Fetches latest AWS news and announcements",
					"parameters": map[string]interface{}{
						"type": "object",
						"properties": map[string]interface{}{
							"category": map[string]interface{}{
								"type":        "string",
								"description": "Optional category to filter news",
							},
						},
					},
				},
			},
		},
	}
	initJSON, _ := json.Marshal(initResp)
	writeData(initJSON)
	flusherFunc()

	category := ""
	var req struct {
		ID     int                    `json:"id"`
		Method string                 `json:"method"`
		Params map[string]interface{} `json:"params"`
	}
	if r.Method == http.MethodPost {
		body, _ := io.ReadAll(r.Body)
		json.Unmarshal(body, &req)
		if c, ok := req.Params["category"].(string); ok {
			category = c
		}
	} else {
		if _, ok := query["category"]; ok {
			category = query["category"][0]
		}
	}

	news, err := fetchNews(category)
	if err != nil {
		errResp := map[string]interface{}{
			"jsonrpc": "2.0",
			"id":      req.ID,
			"error": map[string]interface{}{
				"code":    -32000,
				"message": fmt.Sprintf("Failed to fetch news: %v", err),
			},
		}
		errJSON, _ := json.Marshal(errResp)
		writeData(errJSON)
		flusherFunc()
		return
	}
	for _, item := range news {
		newsResp := map[string]interface{}{
			"jsonrpc": "2.0",
			"id":      req.ID,
			"result": map[string]interface{}{
				"message": map[string]interface{}{
					"role": "assistant",
					"content": fmt.Sprintf("📢 AWS News Update (%s)\n\n**%s**\n\n%s\n\nCategory: %s\nProducts: %s",
						item.Date,
						item.Headline,
						item.Body,
						item.Category,
						strings.Join(item.Products, ", ")),
				},
			},
		}
		newsJSON, _ := json.Marshal(newsResp)
		writeData(newsJSON)
		flusherFunc()
	}
}
