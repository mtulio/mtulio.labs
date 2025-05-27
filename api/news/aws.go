package main

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
		"size":             "15",
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
	}

	return newsItems, nil
}

func Handler(w http.ResponseWriter, r *http.Request) {
	// Extract 'category' query parameter
	category := r.URL.Query().Get("category")

	// Fetch news based on the category
	news, err := fetchNews(category)
	if err != nil {
		http.Error(w, fmt.Sprintf("Error fetching news: %v", err), http.StatusInternalServerError)
		return
	}

	// Convert news items to JSON
	jsonData, err := json.MarshalIndent(news, "", "  ")
	if err != nil {
		http.Error(w, fmt.Sprintf("Error converting news to JSON: %v", err), http.StatusInternalServerError)
		return
	}

	// Set response headers and write JSON data
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(jsonData)
}
