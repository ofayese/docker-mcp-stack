#!/bin/bash
# MCP Stack Manager - Main entry point for Docker MCP Stack management
# This script provides a unified interface to manage all aspects of the MCP stack

# Enable strict mode
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UTILS_DIR="$ROOT_DIR/scripts/utils"
SERVICES_DIR="$ROOT_DIR/scripts/services"
TEST_DIR="$ROOT_DIR/scripts/test"
SECRETS_DIR="$ROOT_DIR/secrets"

# Docker Secrets configuration
SECRETS_CONFIG=(
    "github_token:GITHUB_TOKEN"
    "gitlab_token:GITLAB_TOKEN"
    "postgres_password:POSTGRES_PASSWORD"
    "grafana_admin_password:GRAFANA_ADMIN_PASSWORD"
    "backup_encryption_key:BACKUP_ENCRYPTION_KEY"
)

# Import utility scripts
# shellcheck disable=SC1091
source "$UTILS_DIR/validation.sh"

# Define version
VERSION="1.0.0"

# Help message
print_help() {
    cat << EOF
MCP Stack Manager v$VERSION
A comprehensive management tool for Docker MCP Stack

Usage: $0 [command] [options]

Commands:
  setup              Setup the MCP stack (validate, initialize, etc.)
  start              Start the MCP stack
  stop               Stop the MCP stack
  restart            Restart the MCP stack
  status             Show the status of the MCP stack
  logs [service]     Show logs for a service or all services
  health             Run health checks on the MCP stack
  model [options]    Manage models (see 'model' subcommand help)
  service [options]  Manage services (see 'service' subcommand help)
  benchmark [options] Run benchmarks (see 'benchmark' subcommand help)
  update             Update the MCP stack to the latest version
  clean              Clean up resources used by the MCP stack
  validate           Validate the MCP stack configuration
  secrets [options]  Manage Docker secrets (see 'secrets' subcommand help)
  help               Show this help message
  version            Show version information

Model Commands:
  model list                  List available models
  model start <model>         Start a specific model
  model stop <model>          Stop a specific model
  model restart <model>       Restart a specific model
  model logs <model>          Show logs for a specific model
  model pull <model>          Pull a model image
  model benchmark <model>     Benchmark a specific model

Service Commands:
  service list                List available services
  service start <service>     Start a specific service
  service stop <service>      Stop a specific service
  service restart <service>   Restart a specific service
  service logs <service>      Show logs for a specific service
  service profile <profile>   Activate a specific profile
  service exec <service> <cmd> Execute a command in a service

Benchmark Commands:
  benchmark model <model>     Benchmark a specific model
  benchmark comparative       Run comparative benchmarks for all models
  benchmark throughput        Generate token throughput report

Health Commands:
  health check                Run all health checks
  health service <service>    Check health of a specific service
  health model <model>        Check health of a specific model
  health report               Generate a health report

Secrets Commands:
  secrets init                Initialize Docker secrets from environment
  secrets create <name>       Create a specific secret
  secrets list                List all managed secrets
  secrets update <name>       Update a specific secret
  secrets remove <name>       Remove a specific secret
  secrets rotate              Rotate all secrets
  secrets status              Show secrets status

Examples:
  $0 setup
  $0 start
  $0 model start llama3
  $0 service profile github
  $0 benchmark comparative
  $0 health check

For more information, see the documentation.
EOF
}

# Function to parse and execute commands
execute_command() {
    local command="$1"
    shift
    
    case "$command" in
        setup)
            setup_stack "$@"
            ;;
        start)
            start_stack "$@"
            ;;
        stop)
            stop_stack "$@"
            ;;
        restart)
            restart_stack "$@"
            ;;
        status)
            show_status "$@"
            ;;
        logs)
            show_logs "$@"
            ;;
        health)
            if [[ $# -eq 0 ]]; then
                # Default to health check if no subcommand provided
                "$UTILS_DIR/health-monitor.sh" check
            else
                local health_command="$1"
                shift
                
                case "$health_command" in
                    check)
                        "$UTILS_DIR/health-monitor.sh" check
                        ;;
                    service)
                        if [[ $# -eq 0 ]]; then
                            log_error "Missing service name"
                            print_help
                            return 1
                        fi
                        "$UTILS_DIR/health-monitor.sh" service "$1"
                        ;;
                    model)
                        if [[ $# -eq 0 ]]; then
                            log_error "Missing model name"
                            print_help
                            return 1
                        fi
                        # Determine port from model name
                        local var_name="MODEL_PORT_${1^^}"
                        var_name="${var_name//-/_}"
                        var_name="${var_name//./_}"
                        
                        if [[ -n "${!var_name+x}" ]]; then
                            "$UTILS_DIR/health-monitor.sh" model "$1" "${!var_name}"
                        else
                            log_error "Port for model $1 not found"
                            return 1
                        fi
                        ;;
                    report)
                        "$UTILS_DIR/health-monitor.sh" report
                        ;;
                    *)
                        log_error "Unknown health command: $health_command"
                        print_help
                        return 1
                        ;;
                esac
            fi
            ;;
        model)
            if [[ $# -eq 0 ]]; then
                log_error "Missing model subcommand"
                print_help
                return 1
            fi
            
            local model_command="$1"
            shift
            
            case "$model_command" in
                list)
                    log_info "Available models:"
                    if [[ -f "$ROOT_DIR/.env" ]]; then
                        set -a
                        source "$ROOT_DIR/.env"
                        set +a
                    fi
                    
                    # Get model ports from environment variables
                    env | grep -E "^MODEL_PORT_" | sort | while read -r line; do
                        model_name=$(echo "$line" | sed -E 's/MODEL_PORT_([^=]+)=.*/\1/' | tr '[:upper:]' '[:lower:]' | tr '_' '-')
                        port=$(echo "$line" | sed -E 's/.*=([0-9]+)/\1/')
                        
                        # Check if model is running
                        if docker ps --format '{{.Names}}' | grep -q "model-runner-$model_name"; then
                            status="running"
                        else
                            status="stopped"
                        fi
                        
                        echo "  $model_name (Port: $port, Status: $status)"
                    done
                    ;;
                start)
                    if [[ $# -eq 0 ]]; then
                        log_error "Missing model name"
                        print_help
                        return 1
                    fi
                    "$SERVICES_DIR/service-manager.sh" model "$1"
                    ;;
                stop)
                    if [[ $# -eq 0 ]]; then
                        log_error "Missing model name"
                        print_help
                        return 1
                    fi
                    "$SERVICES_DIR/service-manager.sh" stop "model-runner-${1//./-}"
                    ;;
                restart)
                    if [[ $# -eq 0 ]]; then
                        log_error "Missing model name"
                        print_help
                        return 1
                    fi
                    "$SERVICES_DIR/service-manager.sh" restart "model-runner-${1//./-}"
                    ;;
                logs)
                    if [[ $# -eq 0 ]]; then
                        log_error "Missing model name"
                        print_help
                        return 1
                    fi
                    "$SERVICES_DIR/service-manager.sh" logs "model-runner-${1//./-}"
                    ;;
                pull)
                    if [[ $# -eq 0 ]]; then
                        log_error "Missing model name"
                        print_help
                        return 1
                    fi
                    log_info "Pulling model: $1"
                    docker pull "ai/$1"
                    ;;
                benchmark)
                    if [[ $# -eq 0 ]]; then
                        log_error "Missing model name"
                        print_help
                        return 1
                    fi
                    "$TEST_DIR/benchmark.sh" --model "$1"
                    ;;
                *)
                    log_error "Unknown model command: $model_command"
                    print_help
                    return 1
                    ;;
            esac
            ;;
        service)
            if [[ $# -eq 0 ]]; then
                log_error "Missing service subcommand"
                print_help
                return 1
            fi
            
            local service_command="$1"
            shift
            
            case "$service_command" in
                list)
                    log_info "Available services:"
                    docker compose -f "$ROOT_DIR/compose.yaml" config --services | grep -v "model-runner" | sort | while read -r service; do
                        # Check if service is running
                        if docker ps --format '{{.Names}}' | grep -q "$service"; then
                            status="running"
                        else
                            status="stopped"
                        fi
                        
                        echo "  $service (Status: $status)"
                    done
                    ;;
                start|stop|restart|logs)
                    if [[ $# -eq 0 ]]; then
                        log_error "Missing service name"
                        print_help
                        return 1
                    fi
                    "$SERVICES_DIR/service-manager.sh" "$service_command" "$1"
                    ;;
                profile)
                    if [[ $# -eq 0 ]]; then
                        log_error "Missing profile name"
                        print_help
                        return 1
                    fi
                    "$SERVICES_DIR/service-manager.sh" profile "$1"
                    ;;
                exec)
                    if [[ $# -lt 2 ]]; then
                        log_error "Missing service name or command"
                        print_help
                        return 1
                    fi
                    local service="$1"
                    shift
                    "$SERVICES_DIR/service-manager.sh" exec "$service" "$@"
                    ;;
                *)
                    log_error "Unknown service command: $service_command"
                    print_help
                    return 1
                    ;;
            esac
            ;;
        benchmark)
            if [[ $# -eq 0 ]]; then
                log_error "Missing benchmark subcommand"
                print_help
                return 1
            fi
            
            local benchmark_command="$1"
            shift
            
            case "$benchmark_command" in
                model)
                    if [[ $# -eq 0 ]]; then
                        log_error "Missing model name"
                        print_help
                        return 1
                    fi
                    "$TEST_DIR/benchmark.sh" --model "$1"
                    ;;
                comparative)
                    local prompt_set="simple"
                    if [[ $# -gt 0 ]]; then
                        prompt_set="$1"
                    fi
                    "$TEST_DIR/benchmark.sh" --comparative --prompts "$prompt_set"
                    ;;
                throughput)
                    "$TEST_DIR/benchmark.sh" --throughput
                    ;;
                *)
                    log_error "Unknown benchmark command: $benchmark_command"
                    print_help
                    return 1
                    ;;
            esac
            ;;
        update)
            update_stack "$@"
            ;;
        clean)
            clean_stack "$@"
            ;;
        validate)
            validate_stack "$@"
            ;;
        secrets)
            handle_secrets_command "$@"
            ;;
        help)
            print_help
            ;;
        version)
            echo "MCP Stack Manager v$VERSION"
            ;;
        *)
            log_error "Unknown command: $command"
            print_help
            return 1
            ;;
    esac
}

# Setup the MCP stack
setup_stack() {
    log_info "Setting up MCP stack..."
    
    # Run comprehensive validation
    log_info "Validating system requirements..."
    run_comprehensive_validation || return 1
    
    # Check if .env file exists
    if [[ ! -f "$ROOT_DIR/.env" ]]; then
        log_info "Creating .env file from template..."
        cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
        log_info "Please update the .env file with your configuration"
    fi
    
    # Create required directories
    log_info "Creating required directories..."
    mkdir -p "$ROOT_DIR/backups"
    mkdir -p "$ROOT_DIR/benchmarks"
    mkdir -p "$ROOT_DIR/monitoring"
    mkdir -p "$ROOT_DIR/nginx/certs"
    mkdir -p "$ROOT_DIR/nginx/html"
    mkdir -p "$ROOT_DIR/sql/init"
    mkdir -p "$ROOT_DIR/workspace"
    
    # Set file permissions
    log_info "Setting file permissions..."
    chmod +x "$ROOT_DIR/run.sh" 2>/dev/null || true
    chmod +x "$ROOT_DIR/backup.sh" 2>/dev/null || true
    chmod +x "$ROOT_DIR/restore.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
    chmod +x "$UTILS_DIR"/*.sh 2>/dev/null || true
    chmod +x "$SERVICES_DIR"/*.sh 2>/dev/null || true
    chmod +x "$TEST_DIR"/*.sh 2>/dev/null || true
    
    log_info "✅ MCP stack setup completed successfully"
    log_info "You can now start the stack with: $0 start"
}

# Docker Secrets Management Functions

# Handle secrets command
handle_secrets_command() {
    local subcommand="${1:-}"
    shift || true
    
    case "$subcommand" in
        init)
            init_secrets "$@"
            ;;
        create)
            create_secret "$@"
            ;;
        list)
            list_secrets "$@"
            ;;
        update)
            update_secret "$@"
            ;;
        remove)
            remove_secret "$@"
            ;;
        rotate)
            rotate_secrets "$@"
            ;;
        status)
            secrets_status "$@"
            ;;
        "")
            log_error "Missing secrets subcommand"
            log_info "Available commands: init, create, list, update, remove, rotate, status"
            return 1
            ;;
        *)
            log_error "Unknown secrets subcommand: $subcommand"
            log_info "Available commands: init, create, list, update, remove, rotate, status"
            return 1
            ;;
    esac
}

# Initialize Docker secrets from environment
init_secrets() {
    log_info "Initializing Docker secrets from environment..."
    
    # Check if Docker swarm is initialized
    if ! docker node ls >/dev/null 2>&1; then
        log_info "Initializing Docker swarm mode for secrets support..."
        docker swarm init --advertise-addr 127.0.0.1 >/dev/null 2>&1 || {
            log_error "Failed to initialize Docker swarm mode"
            return 1
        }
    fi
    
    # Create secrets directory if it doesn't exist
    mkdir -p "$SECRETS_DIR"
    
    # Source environment variables
    if [[ -f "$ROOT_DIR/.env" ]]; then
        # shellcheck disable=SC1091
        source "$ROOT_DIR/.env"
    fi
    
    local created_count=0
    local failed_count=0
    
    # Create secrets from configuration
    for secret_config in "${SECRETS_CONFIG[@]}"; do
        local secret_name="${secret_config%%:*}"
        local env_var="${secret_config##*:}"
        
        # Get value from environment variable
        local secret_value="${!env_var:-}"
        
        if [[ -z "$secret_value" ]]; then
            log_warning "Environment variable $env_var is not set, skipping $secret_name"
            continue
        fi
        
        # Skip if already exists
        if docker secret inspect "$secret_name" >/dev/null 2>&1; then
            log_info "Secret $secret_name already exists, skipping"
            continue
        fi
        
        # Create secret
        if echo "$secret_value" | docker secret create "$secret_name" - >/dev/null 2>&1; then
            log_info "✅ Created secret: $secret_name"
            ((created_count++))
        else
            log_error "❌ Failed to create secret: $secret_name"
            ((failed_count++))
        fi
    done
    
    log_info "Secrets initialization completed: $created_count created, $failed_count failed"
}

# Create a specific secret
create_secret() {
    local secret_name="${1:-}"
    
    if [[ -z "$secret_name" ]]; then
        log_error "Missing secret name"
        log_info "Usage: $0 secrets create <secret_name>"
        return 1
    fi
    
    # Check if secret already exists
    if docker secret inspect "$secret_name" >/dev/null 2>&1; then
        log_error "Secret $secret_name already exists"
        log_info "Use 'update' command to update existing secrets"
        return 1
    fi
    
    # Find the environment variable for this secret
    local env_var=""
    for secret_config in "${SECRETS_CONFIG[@]}"; do
        local config_name="${secret_config%%:*}"
        if [[ "$config_name" == "$secret_name" ]]; then
            env_var="${secret_config##*:}"
            break
        fi
    done
    
    if [[ -z "$env_var" ]]; then
        log_error "Unknown secret: $secret_name"
        log_info "Available secrets: $(printf '%s ' "${SECRETS_CONFIG[@]}" | sed 's/:[^ ]*//g')"
        return 1
    fi
    
    # Source environment variables
    if [[ -f "$ROOT_DIR/.env" ]]; then
        # shellcheck disable=SC1091
        source "$ROOT_DIR/.env"
    fi
    
    local secret_value="${!env_var:-}"
    
    if [[ -z "$secret_value" ]]; then
        log_error "Environment variable $env_var is not set"
        log_info "Please set $env_var in your .env file"
        return 1
    fi
    
    # Create secret
    if echo "$secret_value" | docker secret create "$secret_name" - >/dev/null 2>&1; then
        log_info "✅ Created secret: $secret_name"
    else
        log_error "❌ Failed to create secret: $secret_name"
        return 1
    fi
}

# List all managed secrets
list_secrets() {
    log_info "Listing managed Docker secrets..."
    
    for secret_config in "${SECRETS_CONFIG[@]}"; do
        local secret_name="${secret_config%%:*}"
        local env_var="${secret_config##*:}"
        
        if docker secret inspect "$secret_name" >/dev/null 2>&1; then
            local created_at
            created_at=$(docker secret inspect "$secret_name" --format '{{.CreatedAt}}' 2>/dev/null | cut -d'.' -f1)
            echo "✅ $secret_name (env: $env_var) - Created: $created_at"
        else
            echo "❌ $secret_name (env: $env_var) - Not found"
        fi
    done
}

# Update a specific secret
update_secret() {
    local secret_name="${1:-}"
    
    if [[ -z "$secret_name" ]]; then
        log_error "Missing secret name"
        log_info "Usage: $0 secrets update <secret_name>"
        return 1
    fi
    
    # Remove existing secret
    if docker secret inspect "$secret_name" >/dev/null 2>&1; then
        log_info "Removing existing secret: $secret_name"
        if ! docker secret rm "$secret_name" >/dev/null 2>&1; then
            log_error "Failed to remove existing secret: $secret_name"
            log_info "Secret may be in use by running services. Stop services first."
            return 1
        fi
    fi
    
    # Create new secret
    create_secret "$secret_name"
}

# Remove a specific secret
remove_secret() {
    local secret_name="${1:-}"
    
    if [[ -z "$secret_name" ]]; then
        log_error "Missing secret name"
        log_info "Usage: $0 secrets remove <secret_name>"
        return 1
    fi
    
    if docker secret inspect "$secret_name" >/dev/null 2>&1; then
        if docker secret rm "$secret_name" >/dev/null 2>&1; then
            log_info "✅ Removed secret: $secret_name"
        else
            log_error "❌ Failed to remove secret: $secret_name"
            log_info "Secret may be in use by running services"
            return 1
        fi
    else
        log_warning "Secret $secret_name does not exist"
    fi
}

# Rotate all secrets
rotate_secrets() {
    log_info "Rotating all managed secrets..."
    log_warning "This will require restarting services using secrets"
    
    # Confirm action
    read -p "Are you sure you want to rotate all secrets? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Secret rotation cancelled"
        return 0
    fi
    
    local rotated_count=0
    local failed_count=0
    
    for secret_config in "${SECRETS_CONFIG[@]}"; do
        local secret_name="${secret_config%%:*}"
        
        if docker secret inspect "$secret_name" >/dev/null 2>&1; then
            log_info "Rotating secret: $secret_name"
            if update_secret "$secret_name"; then
                ((rotated_count++))
            else
                ((failed_count++))
            fi
        fi
    done
    
    log_info "Secret rotation completed: $rotated_count rotated, $failed_count failed"
    
    if [[ $rotated_count -gt 0 ]]; then
        log_warning "Please restart services to use the new secrets"
        log_info "Run: $0 restart"
    fi
}

# Show secrets status
secrets_status() {
    log_info "Docker Secrets Status Report"
    echo "================================"
    
    # Check Docker swarm status
    if docker node ls >/dev/null 2>&1; then
        echo "✅ Docker swarm mode: Enabled"
    else
        echo "❌ Docker swarm mode: Disabled (required for secrets)"
        return 1
    fi
    
    # Check secrets
    local total_secrets=${#SECRETS_CONFIG[@]}
    local existing_secrets=0
    local missing_secrets=0
    
    for secret_config in "${SECRETS_CONFIG[@]}"; do
        local secret_name="${secret_config%%:*}"
        
        if docker secret inspect "$secret_name" >/dev/null 2>&1; then
            ((existing_secrets++))
        else
            ((missing_secrets++))
        fi
    done
    
    echo "📊 Secrets Summary:"
    echo "   Total managed secrets: $total_secrets"
    echo "   Existing secrets: $existing_secrets"
    echo "   Missing secrets: $missing_secrets"
    
    if [[ $missing_secrets -gt 0 ]]; then
        echo ""
        echo "⚠️  Missing secrets detected. Run 'secrets init' to create them."
    fi
    
    echo ""
    list_secrets
}

# Start the MCP stack
start_stack() {
    log_info "Starting MCP stack..."
    
    # Start the stack
    "$SERVICES_DIR/service-manager.sh" start
    
    log_info "✅ MCP stack started successfully"
    log_info "To check the status, run: $0 status"
}

# Stop the MCP stack
stop_stack() {
    log_info "Stopping MCP stack..."
    
    # Stop the stack
    "$SERVICES_DIR/service-manager.sh" stop
    
    log_info "✅ MCP stack stopped successfully"
}

# Restart the MCP stack
restart_stack() {
    log_info "Restarting MCP stack..."
    
    # Stop and start the stack
    stop_stack
    start_stack
    
    log_info "✅ MCP stack restarted successfully"
}

# Show the status of the MCP stack
show_status() {
    log_info "MCP stack status:"
    
    # Show the status
    "$SERVICES_DIR/service-manager.sh" status
    
    # Also run health check
    log_info "Running health check..."
    "$UTILS_DIR/health-monitor.sh" check
}

# Show logs for a service or all services
show_logs() {
    if [[ $# -eq 0 ]]; then
        log_info "Showing logs for all services..."
        "$SERVICES_DIR/service-manager.sh" logs
    else
        log_info "Showing logs for service: $1"
        "$SERVICES_DIR/service-manager.sh" logs "$1"
    fi
}

# Update the MCP stack
update_stack() {
    log_info "Updating MCP stack..."
    
    # Check for updates in repositories
    if [[ -d "$ROOT_DIR/.git" ]]; then
        log_info "Checking for updates in Git repository..."
        git -C "$ROOT_DIR" pull
    fi
    
    # Update Docker images
    log_info "Updating Docker images..."
    docker compose -f "$ROOT_DIR/compose.yaml" pull
    
    # Update model images
    log_info "Updating model images..."
    if [[ -f "$ROOT_DIR/.env" ]]; then
        set -a
        source "$ROOT_DIR/.env"
        set +a
    fi
    
    # Get model names from environment variables
    env | grep -E "^MODEL_PORT_" | sort | while read -r line; do
        model_name=$(echo "$line" | sed -E 's/MODEL_PORT_([^=]+)=.*/\1/' | tr '[:upper:]' '[:lower:]' | tr '_' '-')
        log_info "Updating model: $model_name"
        docker pull "ai/$model_name" || log_warn "Failed to pull model: $model_name"
    done
    
    log_info "✅ MCP stack updated successfully"
    log_info "You may need to restart the stack for changes to take effect: $0 restart"
}

# Clean up resources used by the MCP stack
clean_stack() {
    log_info "Cleaning up MCP stack resources..."
    
    # Confirm with user
    read -p "Are you sure you want to clean up all resources? This will remove all containers, volumes, and images. [y/N] " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled"
        return 0
    fi
    
    # Clean up resources
    "$SERVICES_DIR/service-manager.sh" clean
    
    log_info "✅ MCP stack cleaned up successfully"
}

# Validate the MCP stack configuration
validate_stack() {
    log_info "Validating MCP stack configuration..."
    
    # Run comprehensive validation
    run_comprehensive_validation
    
    log_info "✅ MCP stack validation completed successfully"
}

# Main function
main() {
    # No arguments, show help
    if [[ $# -eq 0 ]]; then
        print_help
        return 0
    fi
    
    # Parse command
    local command="$1"
    shift
    
    # Execute command
    execute_command "$command" "$@"
}

# Execute main function if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
