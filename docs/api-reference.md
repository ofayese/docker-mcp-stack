# Docker MCP Stack - API Reference

This document provides comprehensive API documentation for the Docker MCP Stack.

## Table of Contents

- [Authentication](#authentication)
- [Model Endpoints](#model-endpoints)
- [MCP Server APIs](#mcp-server-apis)
- [Health Check Endpoints](#health-check-endpoints)
- [Error Handling](#error-handling)
- [Rate Limiting](#rate-limiting)
- [Examples](#examples)

## Authentication

Currently, the Docker MCP Stack operates without authentication for local development. For production deployments, consider implementing:

- API key authentication
- OAuth 2.0
- JWT tokens
- IP allowlisting

## Model Endpoints

All models expose OpenAI-compatible API endpoints on different ports:

### Available Models

| Model | Port | Container | Image |
|-------|------|-----------|-------|
| SmolLM2 | 12434 | smollm2-runner | ai/smollm2 |
| Llama3 | 12435 | llama3-runner | ai/llama3 |
| Phi-4 | 12436 | phi4-runner | ai/phi4 |
| Qwen3 | 12437 | qwen3-runner | ai/qwen3 |
| Qwen2.5 | 12438 | qwen2-runner | ai/qwen2.5 |
| Mistral | 12439 | mistral-runner | ai/mistral |
| Gemma3 | 12440 | gemma3-runner | ai/gemma3 |
| Granite 7B | 12441 | granite7-runner | redhat/granite-7b-lab-gguf |
| Granite 3 8B | 12442 | granite3-runner | ai/granite-3-8b-instruct |

### Direct Model Access

#### Chat Completions

```http
POST http://localhost:{PORT}/engines/v1/chat/completions
Content-Type: application/json

{
  "model": "ai/smollm2",
  "messages": [
    {
      "role": "user",
      "content": "Hello, how are you?"
    }
  ],
  "max_tokens": 150,
  "temperature": 0.7
}
```

#### List Models

```http
GET http://localhost:{PORT}/engines/v1/models
```

#### Model Information

```http
GET http://localhost:{PORT}/engines/v1/models/{model_name}
```

### Unified Access via Nginx

All models are also accessible through the Nginx reverse proxy:

#### Chat Completions

```http
POST http://localhost/models/{model_name}/engines/v1/chat/completions
Content-Type: application/json

{
  "model": "ai/smollm2",
  "messages": [
    {
      "role": "user",
      "content": "Hello, how are you?"
    }
  ]
}
```

#### Available Routes

- `/models/smollm2/` → SmolLM2 (port 12434)
- `/models/llama3/` → Llama3 (port 12435)
- `/models/phi4/` → Phi-4 (port 12436)
- `/models/qwen3/` → Qwen3 (port 12437)
- `/models/qwen2/` → Qwen2.5 (port 12438)
- `/models/mistral/` → Mistral (port 12439)
- `/models/gemma3/` → Gemma3 (port 12440)
- `/models/granite7/` → Granite 7B (port 12441)
- `/models/granite3/` → Granite 3 8B (port 12442)
- `/api/` → Default model (SmolLM2)

## MCP Server APIs

MCP (Model Context Protocol) servers provide additional capabilities:

### Available MCP Servers

| Server | Container | Purpose |
|--------|-----------|---------|
| Time | mcp-time | Date/time operations |
| Fetch | mcp-fetch | Web data fetching |
| Filesystem | mcp-filesystem | File operations |
| PostgreSQL | mcp-postgres-server | Database operations |
| Git | mcp-git | Version control operations |
| SQLite | mcp-sqlite | SQLite database operations |
| GitHub | mcp-github | GitHub API integration |
| GitLab | mcp-gitlab | GitLab API integration |
| Sentry | mcp-sentry | Error tracking integration |
| Everything | mcp-everything | Combined capabilities |

### Gordon AI Integration

The MCP servers are automatically detected by Gordon AI when using:

```bash
docker ai "Your question here"
```

## Health Check Endpoints

### Individual Service Health

```http
GET http://localhost:{PORT}/health
```

### Model Health

```http
GET http://localhost:{PORT}/engines/v1/models
```

Returns 200 if the model is ready to serve requests.

### Database Health

```http
GET http://localhost:5432/  # PostgreSQL (requires pg_isready)
```

### Monitoring Endpoints

- **Prometheus**: `http://localhost:9090/-/healthy`
- **Grafana**: `http://localhost:3000/api/health`

## Error Handling

### Standard HTTP Status Codes

- `200` - Success
- `400` - Bad Request (invalid parameters)
- `401` - Unauthorized (if authentication is enabled)
- `404` - Not Found (model or endpoint not available)
- `429` - Too Many Requests (rate limited)
- `500` - Internal Server Error
- `503` - Service Unavailable (model loading or maintenance)

### Error Response Format

```json
{
  "error": {
    "type": "invalid_request_error",
    "message": "The model parameter is required",
    "code": "missing_parameter"
  }
}
```

## Rate Limiting

Rate limiting is configured in Nginx:

- **API endpoints**: 10 requests/second per IP
- **Model endpoints**: 5 requests/second per IP

Rate limit headers are included in responses:

```http
X-RateLimit-Limit: 10
X-RateLimit-Remaining: 9
X-RateLimit-Reset: 1234567890
```

## Examples

### cURL Examples

#### Chat with SmolLM2

```bash
curl -X POST http://localhost:12434/engines/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ai/smollm2",
    "messages": [
      {
        "role": "user",
        "content": "Explain quantum computing in simple terms"
      }
    ],
    "max_tokens": 200,
    "temperature": 0.7
  }'
```

#### List Available Models

```bash
curl http://localhost:12434/engines/v1/models
```

#### Via Nginx Proxy

```bash
curl -X POST http://localhost/models/smollm2/engines/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ai/smollm2",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Python Examples

#### Using OpenAI Python Client

```python
import openai

# Configure for local SmolLM2
client = openai.OpenAI(
    api_key="not-needed",
    base_url="http://localhost:12434/engines/v1"
)

# Chat completion
response = client.chat.completions.create(
    model="ai/smollm2",
    messages=[
        {"role": "user", "content": "What is the meaning of life?"}
    ],
    max_tokens=150,
    temperature=0.7
)

print(response.choices[0].message.content)
```

#### Using Requests

```python
import requests

url = "http://localhost:12434/engines/v1/chat/completions"
payload = {
    "model": "ai/smollm2",
    "messages": [
        {"role": "user", "content": "Tell me a joke"}
    ],
    "max_tokens": 100
}

response = requests.post(url, json=payload)
result = response.json()
print(result["choices"][0]["message"]["content"])
```

### Node.js Examples

#### Using Fetch API

```javascript
const response = await fetch('http://localhost:12434/engines/v1/chat/completions', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    model: 'ai/smollm2',
    messages: [
      { role: 'user', content: 'Write a haiku about programming' }
    ],
    max_tokens: 150
  })
});

const data = await response.json();
console.log(data.choices[0].message.content);
```

### Gordon AI Examples

#### Basic Usage

```bash
# Ask about time
docker ai "What time is it in Tokyo?"

# File operations
docker ai "List the files in the current directory"

# Database queries
docker ai "Show me the PostgreSQL database schema"

# Web data
docker ai "Fetch the latest news about AI"

# Git operations
docker ai "Show me the git status of this repository"
```

## WebSocket Support

Currently, the stack does not support WebSocket connections for streaming responses. This is a planned feature for future releases.

## Monitoring and Metrics

### Prometheus Metrics

Model runners expose metrics at:

- `http://localhost:{PORT}/metrics`

Key metrics include:

- Request count
- Response time
- Error rate
- Memory usage
- GPU utilization

### Grafana Dashboards

Access Grafana at `http://localhost:3000` (admin/admin) for:

- Model performance dashboards
- System resource monitoring
- Request analytics
- Error tracking

## Troubleshooting

### Common Issues

#### Model Not Responding

1. Check if the container is running:

   ```bash
   docker ps | grep model-runner
   ```

2. Check container logs:

   ```bash
   docker logs smollm2-runner
   ```

3. Verify health check:

   ```bash
   curl http://localhost:12434/engines/v1/models
   ```

#### High Memory Usage

Models require significant memory. Monitor with:

```bash
docker stats
```

Consider adjusting `MODEL_MEMORY_LIMIT` in `.env`.

#### SSL/TLS Issues

For HTTPS support, configure SSL certificates in `nginx/ssl/` and set `SSL_ENABLED=true` in `.env`.

## Development

### Adding New Models

1. Add service to `compose.yaml`
2. Update `nginx/nginx.conf` with new route
3. Add port configuration to `.env.example`
4. Update documentation

### Custom MCP Servers

Create custom MCP servers following the [MCP specification](https://modelcontextprotocol.io/) and add them to `gordon-mcp.yml`.

## Support

For issues and questions:

- Check the [troubleshooting guide](troubleshooting.md)
- Review container logs
- Open an issue on GitHub

## Version

API Version: 1.0
Last Updated: 2024-12-19
