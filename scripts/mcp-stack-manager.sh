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
