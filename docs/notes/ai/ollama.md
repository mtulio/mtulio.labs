## Ollama


### Install and play

- Install

```sh
wget https://github.com/ollama/ollama/releases/download/v0.2.6/ollama-linux-amd64 -o ~/bin/ollama && chmod u+x ollama
ollama serve &
ollama pull llama3:8b

curl -X POST http://localhost:11434/api/generate -d '{
  "model": "llama3:8b",
  "prompt":"What is the capital of France?"
 }'
 curl -X POST http://localhost:11434/api/generate -d '{
  "model": "llama3:8b",
  "prompt":"What is the capital of France?"
 }'
```


### Using code suggestions with Continue

References:
- https://github.com/ollama/ollama
- https://github.com/ollama/ollama/blob/main/docs/faq.md
- https://github.com/ollama/ollama?tab=readme-ov-file#extensions--plugins
- https://marketplace.visualstudio.com/items?itemName=Continue.continue
- https://docs.continue.dev/setup/configuration#local-and-offline-configuration

Steps:

```sh
ollama pull llama3:8b

ollama pull starcoder2:3b
ollama pull nomic-embed-text

mkdir ~/.continue
cat << EOF > ~/.continue/config.json
{
  "models": [
    {
      "title": "Ollama",
      "provider": "ollama",
      "model": "AUTODETECT"
    }
  ],
  "allowAnonymousTelemetry": false,
  "tabAutocompleteModel": {
    "title": "Starcoder 2 3b",
    "provider": "ollama",
    "model": "starcoder2:3b"
  },
  "embeddingsProvider": {
    "provider": "ollama",
    "model": "nomic-embed-text"
  }
}
```
