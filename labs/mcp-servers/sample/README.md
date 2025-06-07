## Testing the MCP Server

Run the server:

```sh
go run main.go
```

You can test the MCP server using the following curl commands:

### 1. Initialize the Server
```bash
curl -v -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"initialize"}' http://localhost:8082/mcp
```

### 2. List Available Tools
```bash
curl -v -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' http://localhost:8082/mcp
```

### 3. Call the Time Tool
```bash
curl -v -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"time","arguments":{"format":"2006-01-02 15:04:05"}}}' http://localhost:8082/mcp
``` 