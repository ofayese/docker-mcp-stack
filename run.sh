#!/bin/bash
# Docker MCP Stack - Management Script
# This script provides a CLI for managing the Docker MCP Stack

# Enable strict mode for better error handling
set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}Script failed with exit code $exit_code${NC}" >&2
    fi
    exit $exit_code
}

# Set up trap for cleanup
trap cleanup EXIT

# Validate script environment
validate_environment() {
    # Check if we're in the right directory
    if [[ ! -f "compose.yaml" ]]; then
        echo -e "${RED}Error: compose.yaml not found. Please run this script from the project root directory.${NC}" >&2
        exit 1
    fi
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not installed or not in PATH.${NC}" >&2
        exit 1
    fi
    
    # Check if docker compose is available
    if ! docker compose version >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker Compose is not available.${NC}" >&2
        exit 1
    fi
}

# Load environment variables safely
load_environment() {
    if [[ -f .env ]]; then
        # shellcheck source=/dev/null
        set -a
        source .env
        set +a
        echo -e "${BLUE}Environment variables loaded from .env${NC}"
    else
        echo -e "${YELLOW}Warning: .env file not found. Using default values.${NC}"
    fi
}

# Docker Compose file selection with validation
COMPOSE_FILE="compose.yaml"
SECRETS_MODE="${USE_DOCKER_SECRETS:-false}"

# Validate secrets mode configuration
validate_secrets_mode() {
    if [[ "$SECRETS_MODE" == "true" ]]; then
        if [[ -f "compose.secrets.yaml" ]]; then
            COMPOSE_FILE="compose.secrets.yaml"
            echo -e "${BLUE}Using Docker Secrets mode${NC}"
        else
            echo -e "${RED}Error: USE_DOCKER_SECRETS is true but compose.secrets.yaml not found${NC}" >&2
            exit 1
        fi
    fi
}

# Docker compose command with appropriate file and error handling
compose_cmd() {
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}Error: No arguments provided to compose_cmd${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Running: docker compose -f $COMPOSE_FILE $*${NC}"
    docker compose -f "$COMPOSE_FILE" "$@"
}

# Usage information
usage() {
    echo -e "${BLUE}Docker MCP Stack - Management Script${NC}"
    echo ""
    echo "Usage: $0 COMMAND [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  start [--all|--secrets]   Start basic services (use --all for all services, --secrets for secrets mode)"
    echo "  stop                      Stop all services"
    echo "  restart                   Restart all services"
    echo "  status                    Display status of all services"
    echo "  logs [SERVICE]            View logs (optionally for a specific service)"
    echo "  update                    Update all Docker images"
    echo "  clean                     Clean up containers and volumes"
    echo "  check                     Test model endpoints"
    echo "  pull-models               Pull all model images"
    echo "  model MODEL               Start a specific model (e.g., smollm2, llama3)"
    echo "  secrets                   Manage Docker secrets (requires swarm mode)"
    echo ""
    echo "Examples:"
    echo "  $0 start                  Start basic services"
    echo "  $0 start --all            Start all services including models and monitoring"
    echo "  $0 start --secrets        Start services using Docker Secrets"
    echo "  $0 model smollm2          Start SmolLM2 model"
    echo "  $0 logs mcp-time          View logs for the MCP Time server"
    echo "  $0 secrets init           Initialize Docker secrets from environment"
    exit 1
}

# Check if Docker is running with enhanced validation
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not running. Please start Docker and try again.${NC}" >&2
        exit 1
    fi
    
    # Check Docker version compatibility
    local docker_version
    docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    echo -e "${BLUE}Docker version: $docker_version${NC}"
    
    # Check if swarm is required for secrets mode
    if [[ "$SECRETS_MODE" == "true" ]]; then
        if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
            echo -e "${YELLOW}Warning: Docker Swarm is not active but secrets mode is enabled${NC}"
        fi
    fi
}

# Input validation function
validate_service_name() {
    local service_name="$1"
    if [[ -z "$service_name" ]]; then
        echo -e "${RED}Error: Service name cannot be empty${NC}" >&2
        return 1
    fi
    
    # Validate service name format (alphanumeric, hyphens, underscores)
    if [[ ! "$service_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Error: Invalid service name format: $service_name${NC}" >&2
        return 1
    fi
    
    return 0
}

# Start services
start_services() {
    check_docker
    
    local use_secrets=false
    local start_all=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                start_all=true
                shift
                ;;
            --secrets)
                use_secrets=true
                COMPOSE_FILE="compose.secrets.yaml"
                shift
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                ;;
        esac
    done
    
    # Check if secrets file exists when secrets mode is requested
    if [[ "$use_secrets" == "true" ]] && [[ ! -f "compose.secrets.yaml" ]]; then
        echo -e "${RED}Error: compose.secrets.yaml not found. Please create it first.${NC}"
        exit 1
    fi
    
    # Initialize secrets if needed
    if [[ "$use_secrets" == "true" ]]; then
        echo -e "${BLUE}Checking Docker secrets...${NC}"
        if [[ -f "scripts/mcp-stack-manager.sh" ]]; then
            bash scripts/mcp-stack-manager.sh secrets status || {
                echo -e "${YELLOW}Initializing Docker secrets...${NC}"
                bash scripts/mcp-stack-manager.sh secrets init
            }
        fi
    fi
    
    if [[ "$start_all" == "true" ]]; then
        echo -e "${BLUE}Starting all services...${NC}"
        compose_cmd --profile basic --profile models --profile web --profile monitoring up -d
    else
        echo -e "${BLUE}Starting basic services...${NC}"
        compose_cmd --profile basic up -d
    fi
    
    echo -e "${GREEN}Services started.${NC}"
    
    # Check the status after starting
    show_status
}

# Stop services
stop_services() {
    check_docker
    
    echo -e "${BLUE}Stopping all services...${NC}"
    compose_cmd down
    
    echo -e "${GREEN}Services stopped.${NC}"
}

# Restart services
restart_services() {
    check_docker
    
    echo -e "${BLUE}Restarting all services...${NC}"
    compose_cmd restart
    
    echo -e "${GREEN}Services restarted.${NC}"
    
    # Check the status after restarting
    show_status
}

# Show status of services
show_status() {
    check_docker
    
    echo -e "${BLUE}=== Docker MCP Stack Status ===${NC}"
    
    # Get running containers
    RUNNING_CONTAINERS=$(docker ps --format "{{.Names}}")
    
    # Check model runners
    echo -e "${BLUE}Model Runners:${NC}"
    check_service "smollm2-runner" "SmolLM2"
    check_service "llama3-runner" "Llama3"
    check_service "phi4-runner" "Phi-4"
    check_service "qwen3-runner" "Qwen3"
    check_service "qwen2-runner" "Qwen2.5"
    check_service "mistral-runner" "Mistral"
    check_service "gemma3-runner" "Gemma3"
    check_service "granite7-runner" "Granite 7B"
    check_service "granite3-runner" "Granite 3 8B"
    
    # Check MCP servers
    echo -e "\n${BLUE}MCP Servers:${NC}"
    check_service "mcp-time" "Time Server"
    check_service "mcp-fetch" "Fetch Server"
    check_service "mcp-filesystem" "Filesystem Server"
    check_service "mcp-postgres-server" "Postgres Server"
    check_service "mcp-git" "Git Server"
    check_service "mcp-sqlite" "SQLite Server"
    check_service "mcp-github" "GitHub Server"
    check_service "mcp-gitlab" "GitLab Server"
    check_service "mcp-sentry" "Sentry Server"
    check_service "mcp-everything" "Everything Server"
    
    # Check infrastructure
    echo -e "\n${BLUE}Infrastructure:${NC}"
    check_service "mcp-postgres" "PostgreSQL Database"
    check_service "mcp-nginx" "Nginx"
    
    # Check monitoring
    echo -e "\n${BLUE}Monitoring:${NC}"
    check_service "mcp-prometheus" "Prometheus"
    check_service "mcp-grafana" "Grafana"
    check_service "mcp-node-exporter" "Node Exporter"
    
    echo ""
}

# Helper function to check if a service is running
check_service() {
    local container_name=$1
    local display_name=$2
    
    if echo "$RUNNING_CONTAINERS" | grep -q "$container_name"; then
        echo -e "  [${GREEN}✓${NC}] $display_name is running"
    else
        echo -e "  [${RED}✗${NC}] $display_name is not running"
    fi
}

# View logs
view_logs() {
    check_docker
    
    if [ -z "$1" ]; then
        echo -e "${BLUE}Viewing logs for all services...${NC}"
        compose_cmd logs --tail=100 -f
    else
        echo -e "${BLUE}Viewing logs for $1...${NC}"
        compose_cmd logs --tail=100 -f "$1"
    fi
}

# Update Docker images
update_images() {
    check_docker
    
    echo -e "${BLUE}Updating Docker images...${NC}"
    compose_cmd pull
    
    echo -e "${GREEN}Docker images updated.${NC}"
}

# Clean up containers and volumes
clean_up() {
    check_docker
    
    echo -e "${YELLOW}Warning: This will remove all containers and volumes for the MCP stack.${NC}"
    read -p "Are you sure you want to continue? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Stopping and removing containers...${NC}"
        compose_cmd down
        
        echo -e "${BLUE}Removing volumes...${NC}"
        docker volume rm mcp_model_cache mcp_fs_data mcp_git_data mcp_sqlite_data mcp_postgres_data mcp_prometheus_data mcp_grafana_data 2>/dev/null || true
        
        echo -e "${GREEN}Cleanup completed.${NC}"
    else
        echo -e "${BLUE}Cleanup cancelled.${NC}"
    fi
}

# Check model endpoints
check_endpoints() {
    check_docker
    
    echo -e "${BLUE}Checking model endpoints...${NC}"
    
    # SmolLM2
    check_endpoint "${SMOLLM2_PORT:-12434}" "SmolLM2"
    
    # Llama3
    check_endpoint "${LLAMA3_PORT:-12435}" "Llama3"
    
    # Phi-4
    check_endpoint "${PHI4_PORT:-12436}" "Phi-4"
    
    # Qwen3
    check_endpoint "${QWEN3_PORT:-12437}" "Qwen3"
    
    # Qwen2.5
    check_endpoint "${QWEN2_PORT:-12438}" "Qwen2.5"
    
    # Mistral
    check_endpoint "${MISTRAL_PORT:-12439}" "Mistral"
    
    # Gemma3
    check_endpoint "${GEMMA3_PORT:-12440}" "Gemma3"
    
    # Granite 7B
    check_endpoint "${GRANITE7_PORT:-12441}" "Granite 7B"
    
    # Granite 3 8B
    check_endpoint "${GRANITE3_PORT:-12442}" "Granite 3 8B"
    
    echo ""
}

# Helper function to check if a model endpoint is accessible
check_endpoint() {
    local port=$1
    local model_name=$2
    
    if curl -s "http://localhost:$port/engines/v1/models" > /dev/null 2>&1; then
        echo -e "  [${GREEN}✓${NC}] $model_name endpoint is accessible on port $port"
    else
        echo -e "  [${RED}✗${NC}] $model_name endpoint is not accessible on port $port"
    fi
}

# Pull model images
pull_models() {
    check_docker
    
    echo -e "${BLUE}Pulling model images...${NC}"
    
    # Pull all models
    docker pull ai/smollm2
    docker pull ai/llama3
    docker pull ai/phi4
    docker pull ai/qwen3
    docker pull ai/qwen2.5
    docker pull ai/mistral
    docker pull ai/gemma3
    docker pull redhat/granite-7b-lab-gguf
    docker pull ai/granite-3-8b-instruct
    
    echo -e "${GREEN}Model images pulled successfully.${NC}"
}

# Start a specific model
start_model() {
    check_docker
    
    local model=$1
    
    if [ -z "$model" ]; then
        echo -e "${RED}Error: No model specified.${NC}"
        echo "Usage: $0 model MODEL_NAME"
        echo "Available models: smollm2, llama3, phi4, qwen3, qwen2, mistral, gemma3, granite7, granite3"
        exit 1
    fi
    
    case "$model" in
        smollm2)
            echo -e "${BLUE}Starting SmolLM2 model...${NC}"
            compose_cmd up -d smollm2-runner
            ;;
        llama3)
            echo -e "${BLUE}Starting Llama3 model...${NC}"
            compose_cmd up -d llama3-runner
            ;;
        phi4)
            echo -e "${BLUE}Starting Phi-4 model...${NC}"
            compose_cmd up -d phi4-runner
            ;;
        qwen3)
            echo -e "${BLUE}Starting Qwen3 model...${NC}"
            compose_cmd up -d qwen3-runner
            ;;
        qwen2)
            echo -e "${BLUE}Starting Qwen2.5 model...${NC}"
            compose_cmd up -d qwen2-runner
            ;;
        mistral)
            echo -e "${BLUE}Starting Mistral model...${NC}"
            compose_cmd up -d mistral-runner
            ;;
        gemma3)
            echo -e "${BLUE}Starting Gemma3 model...${NC}"
            compose_cmd up -d gemma3-runner
            ;;
        granite7)
            echo -e "${BLUE}Starting Granite 7B model...${NC}"
            compose_cmd up -d granite7-runner
            ;;
        granite3)
            echo -e "${BLUE}Starting Granite 3 8B model...${NC}"
            compose_cmd up -d granite3-runner
            ;;
        *)
            echo -e "${RED}Error: Unknown model '$model'.${NC}"
            echo "Available models: smollm2, llama3, phi4, qwen3, qwen2, mistral, gemma3, granite7, granite3"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}Model started.${NC}"
    
    # Show the status of models
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "runner"
}

# Process command
if [ $# -lt 1 ]; then
    usage
fi

command=$1
shift

case "$command" in
    start)
# Main execution function with enhanced error handling
main() {
    # Validate environment first
    validate_environment
    load_environment
    validate_secrets_mode
    
    # Check for arguments
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}Error: No command specified.${NC}" >&2
        usage
    fi
    
    local command="$1"
    shift
    
    # Validate command input
    if [[ -z "$command" ]]; then
        echo -e "${RED}Error: Command cannot be empty.${NC}" >&2
        usage
    fi
    
    # Execute command with error handling
    case "$command" in
        start)
            start_services "$@"
            ;;
        stop)
            stop_services
            ;;
        restart)
            restart_services
            ;;
        status)
            show_status
            ;;
        logs)
            view_logs "$@"
            ;;
        update)
            update_images
            ;;
        clean)
            clean_up
            ;;
        check)
            check_endpoints
            ;;
        pull-models)
            pull_models
            ;;
        model)
            if [[ $# -eq 0 ]]; then
                echo -e "${RED}Error: No model specified.${NC}" >&2
                usage
            fi
            start_model "$@"
            ;;
        secrets)
            if [[ -f "scripts/mcp-stack-manager.sh" ]]; then
                bash scripts/mcp-stack-manager.sh secrets "$@"
            else
                echo -e "${RED}Error: mcp-stack-manager.sh not found.${NC}" >&2
                exit 1
            fi
            ;;
        help|--help|-h)
            usage
            ;;
        version|--version|-v)
            echo "Docker MCP Stack Management Script v1.0.0"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$command'.${NC}" >&2
            usage
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
