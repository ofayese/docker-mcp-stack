# Docker MCP Stack Makefile

.PHONY: up down logs check health status stack-up models-light models-medium models-large models-enterprise models-all
.PHONY: mcp-dev mcp-monitoring mcp-search mcp-all reset-db backup-db restore-db clean clean-models
.PHONY: pull-models test-models gordon-test-basic gordon-test-time gordon-test-fs gordon-test-db gordon-test-all
.PHONY: monitor help ssl-setup ssl-renew validate benchmark lint-docs lint-docs-fix lint-docs-install
.PHONY: secrets-init secrets-list secrets-status secrets-rotate start-secrets start-all-secrets

# Script paths
STACK_MANAGER := scripts/mcp-stack-manager.sh

# === Basic Operations ===
up:
	@echo "🚀 Starting MCP Stack..."
	@if [ -n "$$DOCKER_HUB_USERNAME" ] && [ -n "$$DOCKER_HUB_TOKEN" ]; then \
		echo "🔑 Authenticating with Docker Hub..."; \
		echo "$$DOCKER_HUB_TOKEN" | docker login -u "$$DOCKER_HUB_USERNAME" --password-stdin; \
	fi
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service start

down:
	@echo "🛑 Stopping MCP Stack..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service stop

logs:
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service logs

check:
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) health check

health:
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) health check

status:
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service status

# === Model Management ===
models-light:
	@echo "🚀 Starting lightweight models..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service model smollm2

models-medium:
	@echo "🚀 Starting medium models..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service model phi4
	@$(STACK_MANAGER) service model mistral
	@$(STACK_MANAGER) service model gemma3

models-large:
	@echo "🚀 Starting large models..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service model llama3
	@$(STACK_MANAGER) service model qwen3
	@$(STACK_MANAGER) service model qwen2

models-enterprise:
	@echo "🚀 Starting enterprise models..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service model granite7
	@$(STACK_MANAGER) service model granite3

models-all:
	@echo "🚀 Starting all models..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service models

# === MCP Server Profiles ===
mcp-dev:
	@echo "🚀 Starting development MCP servers..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service profile github
	@$(STACK_MANAGER) service profile gitlab

mcp-monitoring:
	@echo "🚀 Starting monitoring MCP servers..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service profile sentry
	@$(STACK_MANAGER) service profile monitoring

mcp-search:
	@echo "🚀 Starting search MCP servers..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service profile everything

mcp-all:
	@echo "🚀 Starting all MCP servers..."
	@make mcp-dev
	@make mcp-monitoring
	@make mcp-search

# === Database Operations ===
reset-db:
	@echo "🔄 Resetting database..."
	@docker exec mcp-postgres psql -U $${POSTGRES_USER:-mcp} -d $${POSTGRES_DB:-mcp} -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
	@echo "✅ Database reset complete"

backup-db:
	@echo "💾 Backing up database..."
	@./backup.sh
	@echo "✅ Database backup complete"

restore-db:
	@echo "📁 Restoring database..."
	@if [ -z "$$BACKUP_DIR" ]; then echo "❗ Please set BACKUP_DIR environment variable"; exit 1; fi
	@./restore.sh $$BACKUP_DIR
	@echo "✅ Database restore complete"

# === Docker Secrets Management ===
secrets-init:
	@echo "🔐 Initializing Docker secrets..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) secrets init
	@echo "✅ Docker secrets initialized"

secrets-list:
	@echo "📋 Listing Docker secrets..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) secrets list

secrets-status:
	@echo "🔍 Checking secrets status..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) secrets status

secrets-rotate:
	@echo "🔄 Rotating all secrets..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) secrets rotate
	@echo "✅ Secrets rotation complete"

start-secrets:
	@echo "🚀 Starting stack with Docker Secrets..."
	@export USE_DOCKER_SECRETS=true && ./run.sh start --secrets

start-all-secrets:
	@echo "🚀 Starting all services with Docker Secrets..."
	@export USE_DOCKER_SECRETS=true && ./run.sh start --all --secrets

# === Testing & Validation ===
validate:
	@echo "🔍 Validating configuration..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) validate all

benchmark:
	@echo "🧪 Running benchmark tests..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) benchmark --comparative --prompts simple

# === Documentation Linting ===
lint-docs-install:
	@echo "📦 Installing markdown linting dependencies..."
	@npm install

lint-docs:
	@echo "📝 Checking markdown documentation..."
	@powershell -ExecutionPolicy Bypass -File scripts/lint-docs.ps1 -Action check

lint-docs-fix:
	@echo "🔧 Fixing markdown documentation..."
	@powershell -ExecutionPolicy Bypass -File scripts/lint-docs.ps1 -Action fix

lint-docs-report:
	@echo "📊 Generating markdown linting report..."
	@powershell -ExecutionPolicy Bypass -File scripts/lint-docs.ps1 -Action report

test-models:
	@echo "🧪 Testing model endpoints..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) test models

gordon-test-basic:
	@echo "🧪 Testing basic Gordon functionality..."
	docker ai "Hello, can you tell me what MCP servers are available?"

gordon-test-time:
	@echo "🧪 Testing time MCP server..."
	docker ai "What time is it in Tokyo, New York, and London?"

gordon-test-fs:
	@echo "🧪 Testing filesystem MCP server..."
	docker ai "List the files in the current directory and create a summary"

gordon-test-db:
	@echo "🧪 Testing database MCP server..."
	docker ai "Show me the PostgreSQL database schema and create a test table"

gordon-test-all: gordon-test-basic gordon-test-time gordon-test-fs gordon-test-db

# === System Monitoring ===
monitor:
	@echo "📊 Monitoring system health..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) health monitor 30

# === Docker Hub Authentication ===
docker-login:
	@echo "🔑 Authenticating with Docker Hub..."
	@if [ -z "$$DOCKER_HUB_USERNAME" ] || [ -z "$$DOCKER_HUB_TOKEN" ]; then \
		echo "❗ Please set DOCKER_HUB_USERNAME and DOCKER_HUB_TOKEN environment variables"; \
		exit 1; \
	fi
	@echo "$$DOCKER_HUB_TOKEN" | docker login -u "$$DOCKER_HUB_USERNAME" --password-stdin
	@echo "✅ Docker Hub authentication successful"

# === Image Management ===
pull-models: docker-login
	@echo "📥 Pulling all model images..."
	docker pull ai/smollm2
	docker pull ai/llama3.3
	docker pull ai/phi4
	docker pull ai/qwen3
	docker pull ai/qwen2.5
	docker pull ai/mistral
	docker pull ai/gemma3
	docker pull redhat/granite-7b-lab-gguf
	docker pull ai/granite-3-8b-instruct
	@echo "✅ All models pulled successfully"

# === Cleanup Operations ===
clean:
	@echo "🧹 Cleaning up..."
	@chmod +x $(STACK_MANAGER)
	@$(STACK_MANAGER) service clean
	@echo "✅ Cleanup complete"

clean-models:
	@echo "🧹 Cleaning model caches..."
	docker volume rm mcp_model_cache_smollm2 mcp_model_cache_llama3_3 mcp_model_cache_phi4 mcp_model_cache_qwen3 mcp_model_cache_qwen2_5 mcp_model_cache_mistral mcp_model_cache_gemma3 mcp_model_cache_granite_7b mcp_model_cache_granite_3_8b || true
	@echo "✅ Model caches cleaned"

# === SSL Setup ===
ssl-setup:
	@echo "🔒 Setting up SSL certificates..."
	./run.sh
	@echo "✅ SSL setup complete"

ssl-renew:
	@echo "🔄 Renewing SSL certificates..."
	./cron/renew-cert.sh
	@echo "✅ SSL certificates renewed"

# === Help ===
help:
	@echo "📚 MCP Stack Management Commands"
	@echo ""
	@echo "Basic Operations:"
	@echo "  make up              - Start the MCP stack"
	@echo "  make down            - Stop the MCP stack"
	@echo "  make logs            - Follow logs"
	@echo "  make status          - Show service status"
	@echo "  make health          - Check service health"
	@echo "  make docker-login    - Authenticate with Docker Hub"
	@echo ""
	@echo "Model Management:"
	@echo "  make pull-models     - Pull all model images"
	@echo "  make models-light    - Start lightweight models only"
	@echo "  make models-medium   - Start medium models"
	@echo "  make models-large    - Start large models"
	@echo "  make models-enterprise - Start enterprise models"
	@echo "  make models-all      - Start all models"
	@echo ""
	@echo "MCP Server Management:"
	@echo "  make mcp-dev         - Start development MCP servers"
	@echo "  make mcp-monitoring  - Start monitoring MCP servers"
	@echo "  make mcp-search      - Start search MCP servers"
	@echo "  make mcp-all         - Start all MCP servers"
	@echo ""
	@echo "Testing & Validation:"
	@echo "  make validate        - Validate configuration"
	@echo "  make benchmark       - Run benchmark tests"
	@echo "  make test-models     - Test model endpoints"
	@echo "  make gordon-test-all - Test all Gordon functionality"
	@echo ""
	@echo "Documentation:"
	@echo "  make lint-docs-install - Install markdown linting dependencies"
	@echo "  make lint-docs       - Check markdown documentation for issues"
	@echo "  make lint-docs-fix   - Auto-fix markdown documentation issues"
	@echo "  make lint-docs-report - Generate markdown linting report"
	@echo ""
	@echo "Database Operations:"
	@echo "  make reset-db        - Reset database"
	@echo "  make backup-db       - Backup database"
	@echo "  make restore-db      - Restore database"
	@echo ""
	@echo "Docker Secrets (Production Security):"
	@echo "  make secrets-init    - Initialize Docker secrets from environment"
	@echo "  make secrets-list    - List all managed secrets"
	@echo "  make secrets-status  - Check secrets status"
	@echo "  make secrets-rotate  - Rotate all secrets"
	@echo "  make start-secrets   - Start services with Docker Secrets"
	@echo "  make start-all-secrets - Start all services with Docker Secrets"
	@echo ""
	@echo "Monitoring:"
	@echo "  make monitor         - Monitor system health"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean           - Clean up everything"
	@echo "  make clean-models    - Clean model caches only"
	@echo ""
	@echo "SSL Management:"
	@echo "  make ssl-setup       - Setup SSL certificates"
	@echo "  make ssl-renew       - Renew SSL certificates"
