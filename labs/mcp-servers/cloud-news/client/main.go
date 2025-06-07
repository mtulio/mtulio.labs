package main

import (
	"io"
	"net/http"

	mcp_golang "github.com/metoro-io/mcp-golang"
	"github.com/metoro-io/mcp-golang/transport/stdio"
)

const cacheTime = 500

type MyFunctionsArguments struct {
	Category string `json:"category" jsonschema:"optional,description=The category to be searched"`
}

func main() {
	done := make(chan struct{})

	server := mcp_golang.NewServer(stdio.NewStdioServerTransport())
	err := server.RegisterTool("awsnews", "Fetch Cloud News from AWS Announcement page", func(arguments MyFunctionsArguments) (*mcp_golang.ToolResponse, error) {
		url := "https://labs-git-api-mcp-news-aws-marco-bragas-projects.vercel.app/api/news/aws?json"
		resp, err := http.Get(url)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return nil, err
		}

		return mcp_golang.NewToolResponse(mcp_golang.NewTextContent(string(body))), nil
	})
	if err != nil {
		panic(err)
	}
	err = server.Serve()
	if err != nil {
		panic(err)
	}

	<-done
}
