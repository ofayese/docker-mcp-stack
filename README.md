# Docker MCP Stack

A comprehensive Docker stack for running multiple AI models locally with Model Context Protocol (MCP) integration.

<!-- Badges -->
<p align="center">
  <img src="https://img.shields.io/badge/docker-compose-blue.svg" alt="Docker Compose" />
  <img src="https://img.shields.io/badge/models-9%2B-green.svg" alt="9+ Models" />
  <img src="https://img.shields.io/badge/mcp-enabled-purple.svg" alt="MCP Enabled" />
  <img src="https://img.shields.io/badge/gordon-ready-orange.svg" alt="Gordon Ready" />
</p>

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

3. **Docker Hub Authentication (Optional)**

For private images or to avoid rate limits, add your Docker Hub credentials:

```bash
# In your .env file
DOCKER_HUB_USERNAME=your-dockerhub-username
DOCKER_HUB_TOKEN=your-dockerhub-token
```

You can authenticate manually with:

```bash
make docker-login
```

4. **Pull model images**

```bash
make pull-models
```

5. **Start the stack**

```bash
# Start with basic services
make start

# OR start everything
make start-all
```

6. **Verify installation**

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

- **Production Security**: Use Docker Secrets for sensitive data (tokens, passwords)
- **Network Security**: Default setup binds to localhost for development
- **Authentication**: No authentication enabled by default - configure for production
- **SSL/TLS**: Enable SSL and proper authentication for production deployments
- **Environment Variables**: Migrate sensitive data from .env files to Docker Secrets
- **Access Control**: Use principle of least privilege for service access

For enhanced security, see:

- [DOCKER_SECRETS_GUIDE.md](DOCKER_SECRETS_GUIDE.md) - Docker Secrets implementation
- [SECURITY_RECOMMENDATIONS.md](SECURITY_RECOMMENDATIONS.md) - Comprehensive security guide

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

## 🔐 Docker Secrets (Production Security)

For production deployments, use Docker Secrets to securely manage sensitive information like API tokens and passwords.

### Prerequisites

Docker Secrets requires Docker Swarm mode:

```bash
# Initialize Docker Swarm (if not already initialized)
docker swarm init

# Verify swarm mode is active
docker info | grep Swarm
```

### Setup Docker Secrets

1. **Create secrets from environment variables**:

```bash
# Method 1: Use the built-in secrets manager
./run.sh secrets init

# Method 2: Create secrets manually
echo "your-github-token" | docker secret create github_token -
echo "your-gitlab-token" | docker secret create gitlab_token -
echo "secure-postgres-password" | docker secret create postgres_password -
echo "secure-grafana-password" | docker secret create grafana_admin_password -
```

1. **Start services with Docker Secrets**:

```bash
# Enable secrets mode in environment
export USE_DOCKER_SECRETS=true

# Start services using secrets
./run.sh start --secrets

# OR start all services with secrets
./run.sh start --all --secrets
```

1. **Manage secrets**:

```bash
# List all secrets
./run.sh secrets list

# Check secrets status
./run.sh secrets status

# Update a specific secret
./run.sh secrets update github_token

# Rotate all secrets
./run.sh secrets rotate
```

### Benefits of Docker Secrets

- ✅ **Encrypted storage**: Secrets are encrypted at rest and in transit
- ✅ **Access control**: Only authorized services can access specific secrets
- ✅ **No environment exposure**: Secrets don't appear in `docker inspect` or process lists
- ✅ **Rotation support**: Update secrets without rebuilding containers
- ✅ **Centralized management**: All secrets managed through Docker Swarm

### Migration from Environment Variables

1. **Backup your current .env file**
2. **Initialize Docker Swarm** (if not already done)
3. **Create secrets** using `./run.sh secrets init`
4. **Update environment** to use secrets mode
5. **Test the deployment** with `./run.sh start --secrets`

For detailed information, see [DOCKER_SECRETS_GUIDE.md](DOCKER_SECRETS_GUIDE.md).
