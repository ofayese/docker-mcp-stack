#!/bin/bash
# Service Manager for Docker MCP Stack
# This script provides functions to manage individual services

# Enable strict mode
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
UTILS_DIR="$ROOT_DIR/scripts/utils"

# Import utility scripts
# shellcheck disable=SC1091
source "$UTILS_DIR/validation.sh"

# Function to start a specific service
start_service() {
    local service="$1"
    local compose_file="${2:-$ROOT_DIR/compose.yaml}"
    
    log_info "Starting service: $service"
    
    # Check if service exists in compose file
    if ! docker compose -f "$compose_file" config --services | grep -q "^$service$"; then
        log_error "Service $service not found in $compose_file"
        return 1
    fi
    
    # Check if service is already running
    if docker ps --format '{{.Names}}' | grep -q "$service"; then
        log_warn "Service $service is already running"
        return 0
    fi
    
    # Start service
    docker compose -f "$compose_file" up -d "$service"
    
    # Check if service started successfully
    if docker ps --format '{{.Names}}' | grep -q "$service"; then
        log_info "✅ Service $service started successfully"
        return 0
    else
        log_error "❌ Failed to start service $service"
        log_error "Check logs for more information: docker compose -f $compose_file logs $service"
        return 1
    fi
}

# Function to stop a specific service
stop_service() {
    local service="$1"
    local compose_file="${2:-$ROOT_DIR/compose.yaml}"
    
    log_info "Stopping service: $service"
    
    # Check if service exists in compose file
    if ! docker compose -f "$compose_file" config --services | grep -q "^$service$"; then
        log_error "Service $service not found in $compose_file"
        return 1
    fi
    
    # Check if service is running
    if ! docker ps --format '{{.Names}}' | grep -q "$service"; then
        log_warn "Service $service is not running"
        return 0
    fi
    
    # Stop service
    docker compose -f "$compose_file" stop "$service"
    
    # Check if service stopped successfully
    if ! docker ps --format '{{.Names}}' | grep -q "$service"; then
        log_info "✅ Service $service stopped successfully"
        return 0
    else
        log_error "❌ Failed to stop service $service"
        log_error "Try force stopping: docker compose -f $compose_file kill $service"
        return 1
    fi
}

# Function to restart a specific service
restart_service() {
    local service="$1"
    local compose_file="${2:-$ROOT_DIR/compose.yaml}"
    
    log_info "Restarting service: $service"
    
    # Check if service exists in compose file
    if ! docker compose -f "$compose_file" config --services | grep -q "^$service$"; then
        log_error "Service $service not found in $compose_file"
        return 1
    fi
    
    # Restart service
    docker compose -f "$compose_file" restart "$service"
    
    # Check if service is running after restart
    if docker ps --format '{{.Names}}' | grep -q "$service"; then
        log_info "✅ Service $service restarted successfully"
        return 0
    else
        log_error "❌ Failed to restart service $service"
        log_error "Check logs for more information: docker compose -f $compose_file logs $service"
        return 1
    fi
}

# Function to view logs of a specific service
view_service_logs() {
    local service="$1"
    local lines="${2:-100}"
    local follow="${3:-false}"
    local compose_file="${4:-$ROOT_DIR/compose.yaml}"
    
    log_info "Viewing logs for service: $service"
    
    # Check if service exists in compose file
    if ! docker compose -f "$compose_file" config --services | grep -q "^$service$"; then
        log_error "Service $service not found in $compose_file"
        return 1
    fi
    
    # View logs
    if [[ "$follow" == "true" ]]; then
        docker compose -f "$compose_file" logs --tail "$lines" -f "$service"
    else
        docker compose -f "$compose_file" logs --tail "$lines" "$service"
    fi
    
    return 0
}

# Function to check if a service is running
is_service_running() {
    local service="$1"
    
    if docker ps --format '{{.Names}}' | grep -q "$service"; then
        return 0  # Service is running
    else
        return 1  # Service is not running
    fi
}

# Function to get service status
get_service_status() {
    local service="$1"
    local compose_file="${2:-$ROOT_DIR/compose.yaml}"
    
    # Check if service exists in compose file
    if ! docker compose -f "$compose_file" config --services | grep -q "^$service$"; then
        echo "Service $service not found in $compose_file"
        return 1
    fi
    
    # Check if service is running
    if is_service_running "$service"; then
        local container_id
        container_id=$(docker ps --filter "name=$service" --format '{{.ID}}')
        
        local status
        status=$(docker inspect --format '{{.State.Status}}' "$container_id")
        
        local health=""
        # Check if container has health check
        if docker inspect --format '{{.State.Health.Status}}' "$container_id" 2>/dev/null; then
            health=$(docker inspect --format '{{.State.Health.Status}}' "$container_id")
            echo "$service: $status (health: $health)"
        else
            echo "$service: $status"
        fi
        
        # Get resource usage
        local cpu
        cpu=$(docker stats --no-stream --format "{{.CPUPerc}}" "$container_id")
        
        local memory
        memory=$(docker stats --no-stream --format "{{.MemUsage}}" "$container_id")
        
        echo "  CPU: $cpu, Memory: $memory"
        
        return 0
    else
        echo "$service: not running"
        return 1
    fi
}

# Function to start services by category
start_services_by_category() {
    local category="$1"
    local compose_file="${2:-$ROOT_DIR/compose.yaml}"
    
    log_info "Starting services in category: $category"
    
    # Get services based on category
    local services=()
    
    case "$category" in
        models)
            # Get all model services
            mapfile -t services < <(docker compose -f "$compose_file" config --services | grep "model-runner")
            ;;
        mcp)
            # Get all MCP services
            mapfile -t services < <(docker compose -f "$compose_file" config --services | grep "mcp-")
            ;;
        database)
            # Database services
            services=("postgres" "sqlite-server" "mcp-postgres" "mcp-sqlite")
            ;;
        network)
            # Network-related services
            services=("mcp-fetch" "nginx")
            ;;
        vcs)
            # Version control services
            services=("mcp-git" "mcp-github" "mcp-gitlab")
            ;;
        monitoring)
            # Monitoring services
            services=("prometheus" "grafana" "mcp-sentry")
            ;;
        *)
            log_error "Unknown category: $category"
            log_error "Available categories: models, mcp, database, network, vcs, monitoring"
            return 1
            ;;
    esac
    
    # Check if we found any services
    if [[ ${#services[@]} -eq 0 ]]; then
        log_error "No services found in category: $category"
        return 1
    fi
    
    # Start each service
    local success_count=0
    local failed_services=()
    
    for service in "${services[@]}"; do
        # Check if service exists in compose file
        if ! docker compose -f "$compose_file" config --services | grep -q "^$service$"; then
            log_warn "Service $service not found in $compose_file, skipping"
            continue
        fi
        
        log_info "Starting service: $service"
        
        if start_service "$service" "$compose_file"; then
            ((success_count++))
        else
            failed_services+=("$service")
        fi
    done
    
    # Report results
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        log_info "✅ All services in category $category started successfully"
        return 0
    else
        log_error "❌ Failed to start ${#failed_services[@]} service(s): ${failed_services[*]}"
        log_info "Successfully started $success_count service(s)"
        return 1
    fi
}

# Function to stop services by category
stop_services_by_category() {
    local category="$1"
    local compose_file="${2:-$ROOT_DIR/compose.yaml}"
    
    log_info "Stopping services in category: $category"
    
    # Get services based on category
    local services=()
    
    case "$category" in
        models)
            # Get all model services
            mapfile -t services < <(docker compose -f "$compose_file" config --services | grep "model-runner")
            ;;
        mcp)
            # Get all MCP services
            mapfile -t services < <(docker compose -f "$compose_file" config --services | grep "mcp-")
            ;;
        database)
            # Database services
            services=("postgres" "sqlite-server" "mcp-postgres" "mcp-sqlite")
            ;;
        network)
            # Network-related services
            services=("mcp-fetch" "nginx")
            ;;
        vcs)
            # Version control services
            services=("mcp-git" "mcp-github" "mcp-gitlab")
            ;;
        monitoring)
            # Monitoring services
            services=("prometheus" "grafana" "mcp-sentry")
            ;;
        *)
            log_error "Unknown category: $category"
            log_error "Available categories: models, mcp, database, network, vcs, monitoring"
            return 1
            ;;
    esac
    
    # Check if we found any services
    if [[ ${#services[@]} -eq 0 ]]; then
        log_error "No services found in category: $category"
        return 1
    fi
    
    # Stop each service
    local success_count=0
    local failed_services=()
    
    for service in "${services[@]}"; do
        # Check if service exists in compose file
        if ! docker compose -f "$compose_file" config --services | grep -q "^$service$"; then
            log_warn "Service $service not found in $compose_file, skipping"
            continue
        fi
        
        log_info "Stopping service: $service"
        
        if stop_service "$service" "$compose_file"; then
            ((success_count++))
        else
            failed_services+=("$service")
        fi
    done
    
    # Report results
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        log_info "✅ All services in category $category stopped successfully"
        return 0
    else
        log_error "❌ Failed to stop ${#failed_services[@]} service(s): ${failed_services[*]}"
        log_info "Successfully stopped $success_count service(s)"
        return 1
    fi
}

# Function to get status of all services
get_all_services_status() {
    local compose_file="${1:-$ROOT_DIR/compose.yaml}"
    
    log_info "Getting status of all services..."
    
    # Get all services
    local services
    mapfile -t services < <(docker compose -f "$compose_file" config --services)
    
    # Display status for each service
    local running_count=0
    local stopped_count=0
    
    echo "========================================"
    echo "         MCP Stack Service Status       "
    echo "========================================"
    
    # Group services by category
    echo "--- Model Runners ---"
    for service in "${services[@]}"; do
        if [[ "$service" == model-runner* ]]; then
            if get_service_status "$service" "$compose_file" | grep -q "running"; then
                ((running_count++))
            else
                ((stopped_count++))
            fi
        fi
    done
    
    echo ""
    echo "--- MCP Servers ---"
    for service in "${services[@]}"; do
        if [[ "$service" == mcp-* && "$service" != *postgres* && "$service" != *sqlite* ]]; then
            if get_service_status "$service" "$compose_file" | grep -q "running"; then
                ((running_count++))
            else
                ((stopped_count++))
            fi
        fi
    done
    
    echo ""
    echo "--- Databases ---"
    for service in "${services[@]}"; do
        if [[ "$service" == *postgres* || "$service" == *sqlite* ]]; then
            if get_service_status "$service" "$compose_file" | grep -q "running"; then
                ((running_count++))
            else
                ((stopped_count++))
            fi
        fi
    done
    
    echo ""
    echo "--- Monitoring ---"
    for service in "${services[@]}"; do
        if [[ "$service" == prometheus || "$service" == grafana ]]; then
            if get_service_status "$service" "$compose_file" | grep -q "running"; then
                ((running_count++))
            else
                ((stopped_count++))
            fi
        fi
    done
    
    echo ""
    echo "--- Other Services ---"
    for service in "${services[@]}"; do
        if [[ "$service" != model-runner* && "$service" != mcp-* && "$service" != postgres* && "$service" != *sqlite* && "$service" != prometheus && "$service" != grafana ]]; then
            if get_service_status "$service" "$compose_file" | grep -q "running"; then
                ((running_count++))
            else
                ((stopped_count++))
            fi
        fi
    done
    
    echo "========================================"
    echo "Total services: $((running_count + stopped_count))"
    echo "Running: $running_count"
    echo "Stopped: $stopped_count"
    echo "========================================"
    
    return 0
}

# Function to clean up a specific service
cleanup_service() {
    local service="$1"
    local remove_volumes="${2:-false}"
    local compose_file="${3:-$ROOT_DIR/compose.yaml}"
    
    log_info "Cleaning up service: $service"
    
    # Check if service exists in compose file
    if ! docker compose -f "$compose_file" config --services | grep -q "^$service$"; then
        log_error "Service $service not found in $compose_file"
        return 1
    fi
    
    # Stop service if it's running
    if is_service_running "$service"; then
        log_info "Stopping service $service before cleanup"
        stop_service "$service" "$compose_file"
    fi
    
    # Remove containers
    log_info "Removing containers for service $service"
    if [[ "$remove_volumes" == "true" ]]; then
        docker compose -f "$compose_file" rm -fsv "$service"
    else
        docker compose -f "$compose_file" rm -fs "$service"
    fi
    
    log_info "✅ Service $service cleaned up"
    return 0
}

# Function to update service configuration
update_service_config() {
    local service="$1"
    local config_key="$2"
    local config_value="$3"
    local compose_file="${4:-$ROOT_DIR/compose.yaml}"
    
    log_info "Updating configuration for service: $service"
    log_info "Setting $config_key = $config_value"
    
    # Check if service exists in compose file
    if ! docker compose -f "$compose_file" config --services | grep -q "^$service$"; then
        log_error "Service $service not found in $compose_file"
        return 1
    fi
    
    # Get the current configuration
    local temp_file
    temp_file=$(mktemp)
    
    # Extract service config
    docker compose -f "$compose_file" config | yq ".services.$service" > "$temp_file"
    
    # Update configuration using yq if available
    if command -v yq &> /dev/null; then
        yq -i ".$config_key = \"$config_value\"" "$temp_file"
        
        log_info "Updated configuration for $service"
        log_info "New configuration: $(cat "$temp_file")"
        
        log_warn "Note: This update is temporary and will not modify your compose file"
        log_warn "To make permanent changes, edit $compose_file directly"
        
        # Cleanup
        rm "$temp_file"
        
        return 0
    else
        log_error "yq command not found, unable to update configuration"
        log_error "Please install yq to use this feature"
        
        # Cleanup
        rm "$temp_file"
        
        return 1
    fi
}

# Function to get service dependencies
get_service_dependencies() {
    local service="$1"
    local compose_file="${2:-$ROOT_DIR/compose.yaml}"
    
    log_info "Getting dependencies for service: $service"
    
    # Check if service exists in compose file
    if ! docker compose -f "$compose_file" config --services | grep -q "^$service$"; then
        log_error "Service $service not found in $compose_file"
        return 1
    fi
    
    # Get dependencies using yq if available
    if command -v yq &> /dev/null; then
        log_info "Direct dependencies for $service:"
        
        # Extract depends_on if it exists
        local dependencies
        dependencies=$(docker compose -f "$compose_file" config | yq ".services.$service.depends_on")
        
        if [[ "$dependencies" == "null" ]]; then
            log_info "No direct dependencies found"
        else
            # Extract keys from depends_on
            docker compose -f "$compose_file" config | yq ".services.$service.depends_on | keys[]"
        fi
        
        return 0
    else
        log_error "yq command not found, unable to get dependencies"
        log_error "Please install yq to use this feature"
        return 1
    fi
}

# Function to list all available services
list_available_services() {
    local compose_file="${1:-$ROOT_DIR/compose.yaml}"
    
    log_info "Listing all available services in $compose_file"
    
    # Get all services
    local services
    mapfile -t services < <(docker compose -f "$compose_file" config --services)
    
    # Group services by category
    local model_runners=()
    local mcp_servers=()
    local databases=()
    local monitoring=()
    local others=()
    
    for service in "${services[@]}"; do
        if [[ "$service" == model-runner* ]]; then
            model_runners+=("$service")
        elif [[ "$service" == mcp-* && "$service" != *postgres* && "$service" != *sqlite* ]]; then
            mcp_servers+=("$service")
        elif [[ "$service" == *postgres* || "$service" == *sqlite* ]]; then
            databases+=("$service")
        elif [[ "$service" == prometheus || "$service" == grafana ]]; then
            monitoring+=("$service")
        else
            others+=("$service")
        fi
    done
    
    # Display services by category
    echo "======================================"
    echo "      Available MCP Stack Services    "
    echo "======================================"
    
    echo "--- Model Runners (${#model_runners[@]}) ---"
    for service in "${model_runners[@]}"; do
        if is_service_running "$service"; then
            echo "  ✅ $service (running)"
        else
            echo "  ❌ $service (stopped)"
        fi
    done
    
    echo ""
    echo "--- MCP Servers (${#mcp_servers[@]}) ---"
    for service in "${mcp_servers[@]}"; do
        if is_service_running "$service"; then
            echo "  ✅ $service (running)"
        else
            echo "  ❌ $service (stopped)"
        fi
    done
    
    echo ""
    echo "--- Databases (${#databases[@]}) ---"
    for service in "${databases[@]}"; do
        if is_service_running "$service"; then
            echo "  ✅ $service (running)"
        else
            echo "  ❌ $service (stopped)"
        fi
    done
    
    echo ""
    echo "--- Monitoring (${#monitoring[@]}) ---"
    for service in "${monitoring[@]}"; do
        if is_service_running "$service"; then
            echo "  ✅ $service (running)"
        else
            echo "  ❌ $service (stopped)"
        fi
    done
    
    echo ""
    echo "--- Other Services (${#others[@]}) ---"
    for service in "${others[@]}"; do
        if is_service_running "$service"; then
            echo "  ✅ $service (running)"
        else
            echo "  ❌ $service (stopped)"
        fi
    done
    
    echo "======================================"
    echo "Total services: ${#services[@]}"
    echo "======================================"
    
    return 0
}

# Print usage
print_usage() {
    cat << EOF
Service Manager for Docker MCP Stack

Usage: $0 <command> [options]

Commands:
  start <service> [compose_file]      Start a specific service
  stop <service> [compose_file]       Stop a specific service
  restart <service> [compose_file]    Restart a specific service
  logs <service> [lines] [follow] [compose_file]
                                     View logs of a specific service
  status <service> [compose_file]     Get status of a specific service
  all-status [compose_file]           Get status of all services
  list [compose_file]                 List all available services
  start-cat <category> [compose_file] Start services by category
  stop-cat <category> [compose_file]  Stop services by category
  cleanup <service> [remove_volumes] [compose_file]
                                     Clean up a specific service
  deps <service> [compose_file]       Get service dependencies
  help                                Show this help message

Categories:
  models     - All model runner services
  mcp        - All MCP server services
  database   - Database services
  network    - Network-related services
  vcs        - Version control services
  monitoring - Monitoring services

Examples:
  $0 start model-runner-smollm2
  $0 stop postgres
  $0 restart mcp-time
  $0 logs mcp-postgres 100 true
  $0 status model-runner-smollm2
  $0 all-status
  $0 start-cat models
  $0 stop-cat mcp
  $0 list
  $0 cleanup model-runner-llama3-3 true
  $0 deps mcp-postgres
EOF
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        print_usage
        return 0
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        start)
            if [[ $# -lt 1 ]]; then
                log_error "Missing service name"
                print_usage
                return 1
            fi
            local service="$1"
            local compose_file="${2:-$ROOT_DIR/compose.yaml}"
            
            start_service "$service" "$compose_file"
            ;;
        stop)
            if [[ $# -lt 1 ]]; then
                log_error "Missing service name"
                print_usage
                return 1
            fi
            local service="$1"
            local compose_file="${2:-$ROOT_DIR/compose.yaml}"
            
            stop_service "$service" "$compose_file"
            ;;
        restart)
            if [[ $# -lt 1 ]]; then
                log_error "Missing service name"
                print_usage
                return 1
            fi
            local service="$1"
            local compose_file="${2:-$ROOT_DIR/compose.yaml}"
            
            restart_service "$service" "$compose_file"
            ;;
        logs)
            if [[ $# -lt 1 ]]; then
                log_error "Missing service name"
                print_usage
                return 1
            fi
            local service="$1"
            local lines="${2:-100}"
            local follow="${3:-false}"
            local compose_file="${4:-$ROOT_DIR/compose.yaml}"
            
            view_service_logs "$service" "$lines" "$follow" "$compose_file"
            ;;
        status)
            if [[ $# -lt 1 ]]; then
                log_error "Missing service name"
                print_usage
                return 1
            fi
            local service="$1"
            local compose_file="${2:-$ROOT_DIR/compose.yaml}"
            
            get_service_status "$service" "$compose_file"
            ;;
        all-status)
            local compose_file="${1:-$ROOT_DIR/compose.yaml}"
            
            get_all_services_status "$
