# Docker MCP Stack

A comprehensive Docker stack for running multiple AI models locally with Model Context Protocol (MCP) integration.

<div align="center">
  <img src="https://img.shields.io/badge/docker-compose-blue.svg" alt="Docker Compose">
  <img src="https://img.shields.io/badge/models-9%2B-green.svg" alt="9+ Models">
  <img src="https://img.shields.io/badge/mcp-enabled-purple.svg" alt="MCP Enabled">
  <img src="https://img.shields.io/badge/gordon-ready-orange.svg" alt="Gordon Ready">
</div>

## 🌟 Features

- 🤖 Run **9+ open source AI models** locally:
  - SmolLM2, Llama3, Phi-4, Qwen3, Qwen2.5, Mistral, Gemma3
  - Granite 7B Lab, Granite 3 8B Instruct
  - _All models run in isolated containers with shared model cache_

- 📦 **Full MCP integration** with Gordon AI assistant:
  - Time, Fetch, Filesystem, Postgres, Git, SQLite
  - GitHub, GitLab, Sentry, and Everything servers

- 🛠️ **Advanced tooling**:
  - Nginx reverse proxy for unified API access
  - Prometheus + Grafana monitoring
  - Automated backup and restore
  - Easy CLI management scripts
  - Systemd service integration

- 🔌 **Developer-friendly**:
  - OpenAI-compatible API endpoints
  - Consistent port mapping
  - Simple profile-based deployment
  - YAML configuration

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose
- 8GB+ RAM (more for multiple models)
- GPU with CUDA support (optional but recommended)

### Installation

1. **Clone the repository**

```bash
git clone https://github.com/yourusername/docker-mcp-stack.git
cd docker-mcp-stack
```

2. **Configure environment variables**

```bash
cp .env.example .env
# Edit .env with your preferred settings
```

3. **Pull model images**

```bash
make pull-models
```

4. **Start the stack**

```bash
# Start with basic services
make start

# OR start everything
make start-all
```

5. **Verify installation**

```bash
make status
make check
```

## 💻 Usage

### Running Specific Models

Start a specific model:

```bash
# Start SmolLM2 model
./run.sh model smollm2

# OR using make
make models MODEL=smollm2
```

Available models: `smollm2`, `llama3`, `phi4`, `qwen3`, `qwen2`, `mistral`, `gemma3`, `granite7`, `granite3`

### Using Gordon with MCP

The `gordon-mcp.yml` file is automatically detected by Gordon when running commands in this directory:

```bash
# Ask Gordon a question that uses MCP capabilities
docker ai "What time is it in Tokyo?"

# File operations
docker ai "Create a summary of the files in this directory"

# Database operations
docker ai "Create a new SQLite database and add a users table"
```

### API Endpoints

All models expose OpenAI-compatible API endpoints:

```bash
# Chat completions with SmolLM2
curl http://localhost:12434/engines/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ai/smollm2",
    "messages": [{"role": "user", "content": "Hello world!"}]
  }'

# Through Nginx unified API
curl http://localhost:80/models/smollm2/engines/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ai/smollm2",
    "messages": [{"role": "user", "content": "Hello world!"}]
  }'
```

### Common Operations

```bash
# View all available commands
make help

# Start services
make start

# Check status
make status

# View logs
make logs
make logs SERVICE=smollm2-runner

# Stop all services
make stop

# Create backup
make backup

# Restore from backup
make restore FILE=backups/mcp_backup_20250608_123456.tar.gz

# Install as systemd service
make install-service
```

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   Gordon AI     │────│  Model Runners  │
│                 │    │  (9+ Models)    │
└─────────────────┘    └─────────────────┘
         │                      │
         │                      │
         ▼                      ▼
┌────────────────────────────────────────┐
│            MCP Servers                 │
│ ┌─────────┐ ┌────────┐ ┌────────────┐ │
│ │  Time   │ │ Fetch  │ │ Filesystem │ │
│ └─────────┘ └────────┘ └────────────┘ │
│ ┌─────────┐ ┌────────┐ ┌────────────┐ │
│ │Postgres │ │  Git   │ │  SQLite    │ │
│ └─────────┘ └────────┘ └────────────┘ │
│ ┌─────────┐ ┌────────┐ ┌────────────┐ │
│ │ GitHub  │ │GitLab  │ │   Sentry   │ │
│ └─────────┘ └────────┘ └────────────┘ │
└────────────────────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────┐
│          Infrastructure                │
│ ┌─────────┐ ┌────────┐ ┌────────────┐ │
│ │  Nginx  │ │Postgres│ │Prometheus/ │ │
│ │         │ │Database│ │  Grafana   │ │
│ └─────────┘ └────────┘ └────────────┘ │
└────────────────────────────────────────┘
```

## 📊 Monitoring

Access Grafana dashboards at <http://localhost:3000> (default credentials: admin/admin)

## 🔒 Security Considerations

- Default setup binds to localhost
- No authentication is enabled by default
- For production, enable SSL and authentication
- API keys and tokens should be properly secured in .env file

## 🔧 Customization

### Adding New Models

1. Add a new service to `compose.yaml` following the existing model runner pattern
2. Add a new location block to `nginx/nginx.conf`
3. Update model-related scripts in `run.sh`

### Docker Compose Profiles

Services are organized into profiles for flexible deployment:

- `basic` - Essential services
- `models` - All model runners
- `monitoring` - Prometheus and Grafana
- `web` - Nginx and web services
- `all` - Everything

## 📝 License

MIT

## 🙏 Acknowledgements

- [Docker Model Runner](https://docs.docker.com/desktop/model-runner/)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Gordon AI Assistant](https://www.docker.com/blog/introducing-gordon-ai-assistant/)
