# MCP Servers


## Registering MCP on IDE

### Cursor IDE

 - mcp.json
```json
{
  "mcpServers": {
    "filereader": {
      "path": "labs/mcp-servers/filereader",
      "description": "A simple HTTP server that serves files from a directory",
      "url": "http://localhost:8080"
    },
    "cep": {
      "path": "labs/mcp-servers/cep",
      "description": "A simple HTTP server that serves CEP from a directory",
      "command": "/home/mtulio/go/src/github.com/mtulio/mtulio.labs-devel/labs/mcp-servers/cep/cep"
    }
  }
}
```