#!/bin/bash
# Health Monitor for Docker MCP Stack
# This script provides functions to check the health of services and models

# Enable strict mode
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
UTILS_DIR="$ROOT_DIR/scripts/utils"
REPORT_DIR="$ROOT_DIR/reports"

# Import utility scripts
# shellcheck disable=SC1091
source "$UTILS_DIR/validation.sh"

# Function to check if a service is healthy
check_service_health() {
    local service="$1"
    local max_retries="${2:-3}"
    local retry_delay="${3:-5}"
    local healthy=false
    
    log_info "Checking health of service: $service"
    
    # Check if service is running
    if ! docker ps --format '{{.Names}}' | grep -q "$service"; then
        log_error "Service $service is not running"
        return 1
    fi
    
    # Check if service has health check
    if docker inspect --format '{{.State.Health.Status}}' "$service" 2>/dev/null | grep -q "healthy\|unhealthy"; then
        # Service has health check
        for ((i=1; i<=max_retries; i++)); do
            local health_status
            health_status=$(docker inspect --format '{{.State.Health.Status}}' "$service")
            
            if [[ "$health_status" == "healthy" ]]; then
                healthy=true
                break
            fi
            
            log_info "Service $service health status: $health_status (attempt $i/$max_retries)"
            
            if [[ $i -lt $max_retries ]]; then
                log_info "Waiting ${retry_delay}s before next check..."
                sleep "$retry_delay"
            fi
        done
        
        if [[ "$healthy" == true ]]; then
            log_info "✅ Service $service is healthy"
            return 0
        else
            log_error "❌ Service $service is unhealthy"
            return 1
        fi
    else
        # Service doesn't have health check, check if it's running
        log_info "Service $service does not have a health check, checking if it's running"
        
        if docker ps --format '{{.Status}}' --filter "name=$service" | grep -q "Up"; then
            log_info "✅ Service $service is running"
            return 0
        else
            log_error "❌ Service $service is not running properly"
            return 1
        fi
    fi
}

# Function to check model health
check_model_health() {
    local model="$1"
    local port="$2"
    local max_retries="${3:-3}"
    local retry_delay="${4:-5}"
    local healthy=false
    
    log_info "Checking health of model: $model on port $port"
    
    # Container name for this model
    local container_name="model-runner-${model//./-}"
    
    # Check if model container is running
    if ! docker ps --format '{{.Names}}' | grep -q "$container_name"; then
        log_error "Model container $container_name is not running"
        return 1
    fi
    
    # Check if model API is responding
    for ((i=1; i<=max_retries; i++)); do
        if curl -s "http://localhost:$port/engines/v1/models" > /dev/null; then
            healthy=true
            break
        fi
        
        log_info "Model $model API not responding (attempt $i/$max_retries)"
        
        if [[ $i -lt $max_retries ]]; then
            log_info "Waiting ${retry_delay}s before next check..."
            sleep "$retry_delay"
        fi
    done
    
    if [[ "$healthy" == true ]]; then
        log_info "✅ Model $model is healthy and responding"
        
        # Check model details
        local model_details
        model_details=$(curl -s "http://localhost:$port/engines/v1/models")
        
        log_debug "Model details: $model_details"
        
        # Test a simple query to ensure model is working properly
        log_info "Testing model with a simple query..."
        local response
        response=$(curl -s "http://localhost:$port/engines/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"ai/$model\",
                \"messages\": [{\"role\": \"user\", \"content\": \"Hello, are you working?\"}],
                \"max_tokens\": 10
            }")
        
        log_debug "Response: $response"
        
        # Check if response contains content
        if echo "$response" | grep -q "content"; then
            log_info "✅ Model $model returned a valid response"
            return 0
        else
            log_warn "⚠️ Model $model API is responding but returned an invalid response"
            return 1
        fi
    else
        log_error "❌ Model $model API is not responding"
        return 1
    fi
}

# Function to check all services
check_all_services() {
    log_info "Checking health of all services..."
    local failed_services=()
    
    # Get all running services
    local services
    services=$(docker ps --format '{{.Names}}' | grep -v "model-runner")
    
    # If no services are running, warn and return
    if [[ -z "$services" ]]; then
        log_warn "No services are currently running"
        return 0
    fi
    
    # Check each service
    for service in $services; do
        if ! check_service_health "$service"; then
            failed_services+=("$service")
        fi
    done
    
    # Report results
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        log_info "✅ All services are healthy"
        return 0
    else
        log_error "❌ ${#failed_services[@]} service(s) are unhealthy: ${failed_services[*]}"
        return 1
    fi
}

# Function to check all models
check_all_models() {
    log_info "Checking health of all models..."
    local failed_models=()
    
    # Load environment variables
    if [[ -f "$ROOT_DIR/.env" ]]; then
        set -a
        source "$ROOT_DIR/.env"
        set +a
    fi
    
    # Get running model containers
    local model_containers
    model_containers=$(docker ps --format '{{.Names}}' | grep "model-runner")
    
    # If no models are running, warn and return
    if [[ -z "$model_containers" ]]; then
        log_warn "No models are currently running"
        return 0
    fi
    
    # Check each model
    for container in $model_containers; do
        # Extract model name from container name
        local model="${container#model-runner-}"
        model="${model//-/.}"
        
        # Determine port from model name
        local var_name="MODEL_PORT_${model^^}"
        var_name="${var_name//-/_}"
        var_name="${var_name//./_}"
        
        if [[ -z "${!var_name+x}" ]]; then
            log_warn "Port for model $model not found in environment variables"
            log_warn "Skipping health check for model $model"
            continue
        fi
        
        local port="${!var_name}"
        
        if ! check_model_health "$model" "$port"; then
            failed_models+=("$model")
        fi
    done
    
    # Report results
    if [[ ${#failed_models[@]} -eq 0 ]]; then
        log_info "✅ All models are healthy"
        return 0
    else
        log_error "❌ ${#failed_models[@]} model(s) are unhealthy: ${failed_models[*]}"
        return 1
    fi
}

# Function to check database connections
check_database_connections() {
    log_info "Checking database connections..."
    local failed_dbs=()
    
    # Check PostgreSQL
    if docker ps --format '{{.Names}}' | grep -q "mcp-postgres"; then
        log_info "Checking PostgreSQL connection..."
        
        # Load environment variables
        if [[ -f "$ROOT_DIR/.env" ]]; then
            set -a
            source "$ROOT_DIR/.env"
            set +a
        fi
        
        # Try to connect to PostgreSQL
        if ! docker exec mcp-postgres pg_isready -U "${POSTGRES_USER:-mcp}" -d "${POSTGRES_DB:-mcp}" > /dev/null; then
            log_error "❌ PostgreSQL connection failed"
            failed_dbs+=("postgres")
        else
            log_info "✅ PostgreSQL connection successful"
        fi
    fi
    
    # Check SQLite
    if docker ps --format '{{.Names}}' | grep -q "mcp-sqlite"; then
        log_info "Checking SQLite database..."
        
        # Try to check SQLite file exists
        if ! docker exec mcp-sqlite-host ls /data/mcp.db > /dev/null 2>&1; then
            log_warn "⚠️ SQLite database file not found"
            failed_dbs+=("sqlite")
        else
            log_info "✅ SQLite database file exists"
        fi
    fi
    
    # Report results
    if [[ ${#failed_dbs[@]} -eq 0 ]]; then
        log_info "✅ All database connections are healthy"
        return 0
    else
        log_error "❌ ${#failed_dbs[@]} database(s) have connection issues: ${failed_dbs[*]}"
        return 1
    fi
}

# Function to check MCP servers
check_mcp_servers() {
    log_info "Checking MCP servers..."
    local failed_servers=()
    
    # Get all running MCP servers
    local mcp_servers
    mcp_servers=$(docker ps --format '{{.Names}}' | grep "mcp-" | grep -v "postgres" | grep -v "sqlite")
    
    # If no MCP servers are running, warn and return
    if [[ -z "$mcp_servers" ]]; then
        log_warn "No MCP servers are currently running"
        return 0
    fi
    
    # Check each MCP server
    for server in $mcp_servers; do
        if ! check_service_health "$server"; then
            failed_servers+=("$server")
        fi
    done
    
    # Report results
    if [[ ${#failed_servers[@]} -eq 0 ]]; then
        log_info "✅ All MCP servers are healthy"
        return 0
    else
        log_error "❌ ${#failed_servers[@]} MCP server(s) are unhealthy: ${failed_servers[*]}"
        return 1
    fi
}

# Function to check disk usage
check_disk_usage() {
    log_info "Checking disk usage..."
    local threshold="${1:-90}"  # Default threshold: 90%
    
    # Get disk usage percentage
    local disk_usage
    disk_usage=$(df -h . | awk 'NR==2 {print $5}' | tr -d '%')
    
    log_info "Current disk usage: ${disk_usage}%"
    
    if [[ "$disk_usage" -gt "$threshold" ]]; then
        log_error "❌ Disk usage is above threshold: ${disk_usage}% > ${threshold}%"
        return 1
    else
        log_info "✅ Disk usage is below threshold: ${disk_usage}% <= ${threshold}%"
        return 0
    fi
}

# Function to check memory usage
check_memory_usage() {
    log_info "Checking memory usage..."
    local threshold="${1:-90}"  # Default threshold: 90%
    
    # Check if free command is available
    if ! command -v free &> /dev/null; then
        log_warn "⚠️ Cannot check memory usage: 'free' command not available"
        return 0
    fi
    
    # Get memory usage percentage
    local memory_usage
    memory_usage=$(free | awk '/^Mem:/ {print int($3/$2 * 100)}')
    
    log_info "Current memory usage: ${memory_usage}%"
    
    if [[ "$memory_usage" -gt "$threshold" ]]; then
        log_error "❌ Memory usage is above threshold: ${memory_usage}% > ${threshold}%"
        return 1
    else
        log_info "✅ Memory usage is below threshold: ${memory_usage}% <= ${threshold}%"
        return 0
    fi
}

# Function to check container resource usage
check_container_resources() {
    log_info "Checking container resource usage..."
    local cpu_threshold="${1:-80}"    # Default CPU threshold: 80%
    local memory_threshold="${2:-80}" # Default memory threshold: 80%
    local failed_containers=()
    
    # Get resource usage for all containers
    local containers
    containers=$(docker stats --no-stream --format "{{.Name}}")
    
    # If no containers are running, warn and return
    if [[ -z "$containers" ]]; then
        log_warn "No containers are currently running"
        return 0
    fi
    
    # Check each container
    for container in $containers; do
        # Get CPU and memory usage
        local stats
        stats=$(docker stats --no-stream --format "{{.Name}} {{.CPUPerc}} {{.MemPerc}}" "$container")
        local cpu_usage
        cpu_usage=$(echo "$stats" | awk '{print $2}' | tr -d '%')
        local memory_usage
        memory_usage=$(echo "$stats" | awk '{print $3}' | tr -d '%')
        
        # Check thresholds
        if [[ "$cpu_usage" -gt "$cpu_threshold" ]] || [[ "$memory_usage" -gt "$memory_threshold" ]]; then
            log_warn "⚠️ Container $container has high resource usage: CPU ${cpu_usage}%, Memory ${memory_usage}%"
            failed_containers+=("$container")
        else
            log_debug "Container $container resource usage: CPU ${cpu_usage}%, Memory ${memory_usage}%"
        fi
    done
    
    # Report results
    if [[ ${#failed_containers[@]} -eq 0 ]]; then
        log_info "✅ All containers have acceptable resource usage"
        return 0
    else
        log_warn "⚠️ ${#failed_containers[@]} container(s) have high resource usage: ${failed_containers[*]}"
        return 1
    fi
}

# Function to check network connectivity
check_network_connectivity() {
    log_info "Checking network connectivity..."
    local failed_checks=()
    
    # Check Docker network
    log_info "Checking Docker network..."
    if ! docker network ls | grep -q "mcp_network"; then
        log_error "❌ Docker network 'mcp_network' not found"
        failed_checks+=("docker_network")
    else
        log_info "✅ Docker network 'mcp_network' exists"
    fi
    
    # Check if containers can communicate
    if docker ps --format '{{.Names}}' | grep -q "mcp-postgres" && docker ps --format '{{.Names}}' | grep -q "postgres"; then
        log_info "Checking container connectivity..."
        if ! docker exec mcp-postgres-server ping -c 1 postgres > /dev/null 2>&1; then
            log_error "❌ Container connectivity check failed"
            failed_checks+=("container_connectivity")
        else
            log_info "✅ Container connectivity check passed"
        fi
    fi
    
    # Report results
    if [[ ${#failed_checks[@]} -eq 0 ]]; then
        log_info "✅ Network connectivity checks passed"
        return 0
    else
        log_error "❌ ${#failed_checks[@]} network check(s) failed: ${failed_checks[*]}"
        return 1
    fi
}

# Function to check gordon-mcp.yml configuration
check_gordon_config() {
    log_info "Checking gordon-mcp.yml configuration..."
    
    # Check if gordon-mcp.yml exists
    if [[ ! -f "$ROOT_DIR/gordon-mcp.yml" ]]; then
        log_error "❌ gordon-mcp.yml not found"
        return 1
    fi
    
    # Check if gordon-mcp.yml is valid YAML
    if ! docker compose -f "$ROOT_DIR/gordon-mcp.yml" config > /dev/null 2>&1; then
        log_error "❌ gordon-mcp.yml is not a valid Docker Compose file"
        return 1
    fi
    
    # Check if gordon-mcp.yml contains necessary services
    local missing_services=()
    local required_services=("time" "filesystem")
    
    for service in "${required_services[@]}"; do
        if ! grep -q "services:.*$service:" -A 5 "$ROOT_DIR/gordon-mcp.yml"; then
            missing_services+=("$service")
        fi
    done
    
    if [[ ${#missing_services[@]} -gt 0 ]]; then
        log_error "❌ gordon-mcp.yml is missing required services: ${missing_services[*]}"
        return 1
    fi
    
    log_info "✅ gordon-mcp.yml configuration is valid"
    return 0
}

# Function to run all health checks
run_all_health_checks() {
    log_info "Running all health checks..."
    local failed_checks=0
    
    # Create results array
    local results=()
    
    # Check services
    if check_all_services; then
        results+=("✅ Services: All services are healthy")
    else
        results+=("❌ Services: Some services are unhealthy")
        ((failed_checks++))
    fi
    
    # Check models
    if check_all_models; then
        results+=("✅ Models: All models are healthy")
    else
        results+=("❌ Models: Some models are unhealthy")
        ((failed_checks++))
    fi
    
    # Check database connections
    if check_database_connections; then
        results+=("✅ Databases: All database connections are healthy")
    else
        results+=("❌ Databases: Some database connections failed")
        ((failed_checks++))
    fi
    
    # Check MCP servers
    if check_mcp_servers; then
        results+=("✅ MCP Servers: All MCP servers are healthy")
    else
        results+=("❌ MCP Servers: Some MCP servers are unhealthy")
        ((failed_checks++))
    fi
    
    # Check disk usage
    if check_disk_usage 90; then
        results+=("✅ Disk Usage: Below threshold")
    else
        results+=("❌ Disk Usage: Above threshold")
        ((failed_checks++))
    fi
    
    # Check memory usage
    if check_memory_usage 90; then
        results+=("✅ Memory Usage: Below threshold")
    else
        results+=("❌ Memory Usage: Above threshold")
        ((failed_checks++))
    fi
    
    # Check container resources
    if check_container_resources 80 80; then
        results+=("✅ Container Resources: All containers have acceptable resource usage")
    else
        results+=("⚠️ Container Resources: Some containers have high resource usage")
        # Not counting as a failure, just a warning
    fi
    
    # Check network connectivity
    if check_network_connectivity; then
        results+=("✅ Network Connectivity: All network checks passed")
    else
        results+=("❌ Network Connectivity: Some network checks failed")
        ((failed_checks++))
    fi
    
    # Check gordon-mcp.yml configuration
    if check_gordon_config; then
        results+=("✅ Gordon Config: gordon-mcp.yml configuration is valid")
    else
        results+=("❌ Gordon Config: gordon-mcp.yml configuration is invalid")
        ((failed_checks++))
    fi
    
    # Report results
    log_info "Health check results:"
    for result in "${results[@]}"; do
        echo "$result"
    done
    
    if [[ $failed_checks -eq 0 ]]; then
        log_info "✅ All health checks passed"
        return 0
    else
        log_error "❌ ${failed_checks} health check(s) failed"
        return 1
    fi
}

# Function to generate a health report
generate_health_report() {
    log_info "Generating health report..."
    
    # Create reports directory if it doesn't exist
    mkdir -p "$REPORT_DIR"
    
    # Generate report filename with timestamp
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local report_file="$REPORT_DIR/health-report-$timestamp.md"
    
    # Create report header
    {
        echo "# MCP Stack Health Report"
        echo ""
        echo "**Date:** $(date)"
        echo "**Hostname:** $(hostname)"
        echo ""
        echo "## Summary"
        echo ""
    } > "$report_file"
    
    # Run health checks and capture output
    log_info "Running health checks for report..."
    
    # Capture results in variables
    local services_result=0
    local services_output
    services_output=$(check_all_services) || services_result=$?
    
    local models_result=0
    local models_output
    models_output=$(check_all_models) || models_result=$?
    
    local db_result=0
    local db_output
    db_output=$(check_database_connections) || db_result=$?
    
    local mcp_result=0
    local mcp_output
    mcp_output=$(check_mcp_servers) || mcp_result=$?
    
    local disk_result=0
    local disk_output
    disk_output=$(check_disk_usage 90) || disk_result=$?
    
    local memory_result=0
    local memory_output
    memory_output=$(check_memory_usage 90) || memory_result=$?
    
    local resources_result=0
    local resources_output
    resources_output=$(check_container_resources 80 80) || resources_result=$?
    
    local network_result=0
    local network_output
    network_output=$(check_network_connectivity) || network_result=$?
    
    local gordon_result=0
    local gordon_output
    gordon_output=$(check_gordon_config) || gordon_result=$?
    
    # Calculate overall status
    local failed_checks=$((services_result + models_result + db_result + mcp_result + disk_result + memory_result + network_result + gordon_result))
    local status="✅ Healthy"
    
    if [[ $failed_checks -gt 0 ]]; then
        status="❌ Unhealthy ($failed_checks issues)"
    elif [[ $resources_result -ne 0 ]]; then
        status="⚠️ Warning (resource usage high)"
    fi
    
    # Add overall status to report
    {
        echo "**Overall Status:** $status"
        echo ""
        echo "## Detailed Results"
        echo ""
        
        # Services section
        echo "### Services"
        echo ""
        if [[ $services_result -eq 0 ]]; then
            echo "**Status:** ✅ Healthy"
        else
            echo "**Status:** ❌ Unhealthy"
        fi
        echo ""
        echo '```'
        echo "$services_output"
        echo '```'
        echo ""
        
        # Models section
        echo "### Models"
        echo ""
        if [[ $models_result -eq 0 ]]; then
            echo "**Status:** ✅ Healthy"
        else
            echo "**Status:** ❌ Unhealthy"
        fi
        echo ""
        echo '```'
        echo "$models_output"
        echo '```'
        echo ""
        
        # Databases section
        echo "### Databases"
        echo ""
        if [[ $db_result -eq 0 ]]; then
            echo "**Status:** ✅ Healthy"
        else
            echo "**Status:** ❌ Unhealthy"
        fi
        echo ""
        echo '```'
        echo "$db_output"
        echo '```'
        echo ""
        
        # MCP Servers section
        echo "### MCP Servers"
        echo ""
        if [[ $mcp_result -eq 0 ]]; then
            echo "**Status:** ✅ Healthy"
        else
            echo "**Status:** ❌ Unhealthy"
        fi
        echo ""
        echo '```'
        echo "$mcp_output"
        echo '```'
        echo ""
        
        # System Resources section
        echo "### System Resources"
        echo ""
        if [[ $disk_result -eq 0 && $memory_result -eq 0 && $resources_result -eq 0 ]]; then
            echo "**Status:** ✅ Healthy"
        elif [[ $disk_result -ne 0 || $memory_result -ne 0 ]]; then
            echo "**Status:** ❌ Unhealthy"
        else
            echo "**Status:** ⚠️ Warning"
        fi
        echo ""
        echo "#### Disk Usage"
        echo '```'
        echo "$disk_output"
        echo '```'
        echo ""
        echo "#### Memory Usage"
        echo '```'
        echo "$memory_output"
        echo '```'
        echo ""
        echo "#### Container Resources"
        echo '```'
        echo "$resources_output"
        echo '```'
        echo ""
        
        # Network section
        echo "### Network"
        echo ""
        if [[ $network_result -eq 0 ]]; then
            echo "**Status:** ✅ Healthy"
        else
            echo "**Status:** ❌ Unhealthy"
        fi
        echo ""
        echo '```'
        echo "$network_output"
        echo '```'
        echo ""
        
        # Configuration section
        echo "### Configuration"
        echo ""
        if [[ $gordon_result -eq 0 ]]; then
            echo "**Status:** ✅ Healthy"
        else
            echo "**Status:** ❌ Unhealthy"
        fi
        echo ""
        echo '```'
        echo "$gordon_output"
        echo '```'
        echo ""
        
        # Docker info
        echo "### Docker Information"
        echo ""
        echo '```'
        docker info | grep -E "Server Version|Containers|Images|Server|OS/Arch|CPUs|Total Memory"
        echo '```'
        echo ""
        
        # Running containers
        echo "### Running Containers"
        echo ""
        echo '```'
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo '```'
        echo ""
        
    } >> "$report_file"
    
    log_info "✅ Health report generated: $report_file"
    
    # Open the report if xdg-open is available
    if command -v xdg-open &> /dev/null; then
        xdg-open "$report_file" &
    elif command -v open &> /dev/null; then
        open "$report_file" &
    else
        log_info "To view the report, open: $report_file"
    fi
    
    return 0
}

# Print usage
print_usage() {
    cat << EOF
Health Monitor for Docker MCP Stack

Usage: $0 <command> [options]

Commands:
  check                    Run all health checks
  service <service>        Check health of a specific service
  model <model> <port>     Check health of a specific model
  database                 Check database connections
  mcp                      Check MCP servers
  disk                     Check disk usage
  memory                   Check memory usage
  resources                Check container resource usage
  network                  Check network connectivity
  gordon                   Check gordon-mcp.yml configuration
  report                   Generate a health report
  help                     Show this help message

Examples:
  $0 check
  $0 service postgres
  $0 model smollm2 12434
  $0 report
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
        check)
            run_all_health_checks
            ;;
        service)
            if [[ $# -eq 0 ]]; then
                log_error "Missing service name"
                print_usage
                return 1
            fi
            check_service_health "$1"
            ;;
        model)
            if [[ $# -lt 2 ]]; then
                log_error "Missing model name or port"
                print_usage
                return 1
            fi
            check_model_health "$1" "$2"
            ;;
        database)
            check_database_connections
            ;;
        mcp)
            check_mcp_servers
            ;;
        disk)
            local threshold=90
            if [[ $# -gt 0 ]]; then
                threshold="$1"
            fi
            check_disk_usage "$threshold"
            ;;
        memory)
            local threshold=90
            if [[ $# -gt 0 ]]; then
                threshold="$1"
            fi
            check_memory_usage "$threshold"
            ;;
        resources)
            local cpu_threshold=80
            local memory_threshold=80
            if [[ $# -gt 0 ]]; then
                cpu_threshold="$1"
            fi
            if [[ $# -gt 1 ]]; then
                memory_threshold="$2"
            fi
            check_container_resources "$cpu_threshold" "$memory_threshold"
            ;;
        network)
            check_network_connectivity
            ;;
        gordon)
            check_gordon_config
            ;;
        report)
            generate_health_report
            ;;
        help)
            print_usage
            ;;
        *)
            log_error "Unknown command: $command"
            print_usage
            return 1
            ;;
    esac
}

# Execute main function if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
