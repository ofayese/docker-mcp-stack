#!/bin/bash
# Validation Utilities for Docker MCP Stack
# This script provides functions to validate the stack configuration and environment

# Enable strict mode
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Set up logging functions
# Log levels: ERROR, WARN, INFO, DEBUG
LOG_LEVEL=${LOG_LEVEL:-INFO}

# ANSI color codes
RESET="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"

# Logging functions
log_error() {
    if [[ "${LOG_LEVEL}" == "ERROR" || "${LOG_LEVEL}" == "WARN" || "${LOG_LEVEL}" == "INFO" || "${LOG_LEVEL}" == "DEBUG" ]]; then
        echo -e "${RED}[ERROR] $*${RESET}" >&2
    fi
}

log_warn() {
    if [[ "${LOG_LEVEL}" == "WARN" || "${LOG_LEVEL}" == "INFO" || "${LOG_LEVEL}" == "DEBUG" ]]; then
        echo -e "${YELLOW}[WARN] $*${RESET}" >&2
    fi
}

log_info() {
    if [[ "${LOG_LEVEL}" == "INFO" || "${LOG_LEVEL}" == "DEBUG" ]]; then
        echo -e "${GREEN}[INFO] $*${RESET}"
    fi
}

log_debug() {
    if [[ "${LOG_LEVEL}" == "DEBUG" ]]; then
        echo -e "${CYAN}[DEBUG] $*${RESET}"
    fi
}

# Function to check if Docker is installed and running
check_docker() {
    log_info "Checking Docker installation..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        log_error "Please install Docker before running this script"
        log_error "Visit https://docs.docker.com/get-docker/ for installation instructions"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        log_error "Please start Docker before running this script"
        return 1
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed or not available"
        log_error "Please ensure you have Docker Compose installed"
        log_error "Docker Compose is included with Docker Desktop or can be installed separately"
        return 1
    fi
    
    log_info "✅ Docker is installed and running"
    return 0
}

# Function to check if required ports are available
check_ports() {
    log_info "Checking if required ports are available..."
    
    # Load environment variables
    if [[ -f "$ROOT_DIR/.env" ]]; then
        set -a
        source "$ROOT_DIR/.env"
        set +a
    fi
    
    local ports=()
    local unavailable_ports=()
    
    # Add all model ports
    for var in $(env | grep -E "^MODEL_PORT_" | cut -d '=' -f1); do
        ports+=("${!var}")
    done
    
    # Add other required ports
    ports+=("${POSTGRES_PORT:-5432}")
    
    # Check if each port is available
    for port in "${ports[@]}"; do
        if command -v nc &> /dev/null; then
            # Use netcat if available
            if nc -z localhost "$port" &> /dev/null; then
                unavailable_ports+=("$port")
            fi
        elif command -v lsof &> /dev/null; then
            # Use lsof if available
            if lsof -i :"$port" &> /dev/null; then
                unavailable_ports+=("$port")
            fi
        else
            # Skip check if neither tool is available
            log_warn "Cannot check if port $port is available: no netcat or lsof found"
            continue
        fi
    done
    
    if [[ ${#unavailable_ports[@]} -gt 0 ]]; then
        log_error "The following ports are already in use: ${unavailable_ports[*]}"
        log_error "Please free up these ports before running the stack"
        return 1
    fi
    
    log_info "✅ All required ports are available"
    return 0
}

# Function to validate environment variables
validate_env_vars() {
    log_info "Validating environment variables..."
    
    # Check if .env file exists
    if [[ ! -f "$ROOT_DIR/.env" ]]; then
        log_warn ".env file not found, checking for .env.example"
        
        if [[ -f "$ROOT_DIR/.env.example" ]]; then
            log_info "Creating .env file from .env.example"
            cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
        else
            log_error "Neither .env nor .env.example file found"
            return 1
        fi
    fi
    
    # Load environment variables
    set -a
    source "$ROOT_DIR/.env"
    set +a
    
    # Check required variables
    local missing_vars=()
    
    # Database variables
    if [[ -z "${POSTGRES_DB:-}" ]]; then missing_vars+=("POSTGRES_DB"); fi
    if [[ -z "${POSTGRES_USER:-}" ]]; then missing_vars+=("POSTGRES_USER"); fi
    if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then missing_vars+=("POSTGRES_PASSWORD"); fi
    
    # At least one model port should be defined
    if ! env | grep -q -E "^MODEL_PORT_"; then
        missing_vars+=("MODEL_PORT_*")
        log_error "No model ports defined in .env file"
        log_error "At least one model port should be defined (e.g., MODEL_PORT_SMOLLM2=12434)"
    fi
    
    # Check for default passwords
    if [[ "${POSTGRES_PASSWORD:-}" == "mcp_password" ]]; then
        log_warn "Default database password detected in .env file"
        log_warn "Consider changing the default password for security reasons"
    fi
    
    # Report missing variables
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "The following required environment variables are missing: ${missing_vars[*]}"
        log_error "Please set these variables in the .env file"
        return 1
    fi
    
    log_info "✅ Environment variables validated successfully"
    return 0
}

# Function to validate password complexity
validate_password_complexity() {
    local password="$1"
    local min_length="${2:-12}"
    local errors=()
    
    log_debug "Validating password complexity (min length: $min_length)"
    
    # Check minimum length
    if [[ ${#password} -lt $min_length ]]; then
        errors+=("Password must be at least $min_length characters long")
    fi
    
    # Check for uppercase letter
    if [[ ! "$password" =~ [A-Z] ]]; then
        errors+=("Password must contain at least one uppercase letter")
    fi
    
    # Check for lowercase letter
    if [[ ! "$password" =~ [a-z] ]]; then
        errors+=("Password must contain at least one lowercase letter")
    fi
    
    # Check for digit
    if [[ ! "$password" =~ [0-9] ]]; then
        errors+=("Password must contain at least one digit")
    fi
    
    # Check for special character
    if [[ ! "$password" =~ [^a-zA-Z0-9] ]]; then
        errors+=("Password must contain at least one special character")
    fi
    
    # Check for common weak passwords
    local weak_passwords=("password" "123456" "admin" "root" "guest" "test" "demo")
    local lower_password
    lower_password=$(echo "$password" | tr '[:upper:]' '[:lower:]')
    
    for weak in "${weak_passwords[@]}"; do
        if [[ "$lower_password" == *"$weak"* ]]; then
            errors+=("Password contains common weak pattern: $weak")
            break
        fi
    done
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Password complexity validation failed:"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi
    
    log_info "✅ Password meets complexity requirements"
    return 0
}

# Function to validate security configuration
validate_security_config() {
    log_info "Validating security configuration..."
    local issues=()
    
    # Check for default passwords in .env file
    if [[ -f "$ROOT_DIR/.env" ]]; then
        # Check common default passwords
        local default_patterns=("admin" "password" "123456" "test" "demo" "guest")
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^[^#]*PASSWORD.*= ]]; then
                local password_value
                password_value=$(echo "$line" | cut -d'=' -f2 | tr -d '"'"'"' ')
                
                for pattern in "${default_patterns[@]}"; do
                    if [[ "$password_value" == *"$pattern"* ]]; then
                        issues+=("Weak default password detected in .env: ${line%%=*}")
                        break
                    fi
                done
                
                # Validate password complexity for non-default passwords
                if [[ ${#password_value} -gt 0 ]] && [[ ! "$password_value" =~ (your_|_here|_token|example) ]]; then
                    if ! validate_password_complexity "$password_value" 12 >/dev/null 2>&1; then
                        issues+=("Password complexity validation failed for: ${line%%=*}")
                    fi
                fi
            fi
        done < "$ROOT_DIR/.env"
    fi
    
    # Check if SSL is enabled
    if [[ -f "$ROOT_DIR/.env" ]] && ! grep -q "SSL_ENABLED=true" "$ROOT_DIR/.env"; then
        issues+=("SSL/TLS is not enabled")
    fi
    
    # Check for API authentication
    if [[ -f "$ROOT_DIR/.env" ]] && ! grep -q -E "(API_KEY|AUTH_TOKEN|ENABLE_AUTH=true)" "$ROOT_DIR/.env"; then
        issues+=("No API authentication configuration found")
    fi
    
    # Check Docker daemon security
    if docker info 2>/dev/null | grep -q "Security Options.*apparmor"; then
        log_info "✅ AppArmor security enabled"
    else
        issues+=("AppArmor security not enabled")
    fi
    
    if [[ ${#issues[@]} -gt 0 ]]; then
        log_warn "Security configuration issues found:"
        for issue in "${issues[@]}"; do
            log_warn "  - $issue"
        done
        log_warn "See SECURITY_RECOMMENDATIONS.md for detailed guidance"
        return 1
    fi
    
    log_info "✅ Security configuration validation passed"
    return 0
}

# Function to generate secure password
generate_secure_password() {
    local length="${1:-16}"
    local include_symbols="${2:-true}"
    
    log_info "Generating secure password (length: $length)"
    
    local charset="a-zA-Z0-9"
    if [[ "$include_symbols" == "true" ]]; then
        charset="${charset}!@#$%^&*()_+-=[]{}|;:,.<>?"
    fi
    
    # Generate password using /dev/urandom and tr
    local password
    password=$(LC_ALL=C tr -dc "$charset" < /dev/urandom | head -c "$length")
    
    # Ensure password meets complexity requirements
    if validate_password_complexity "$password" "$length" >/dev/null 2>&1; then
        echo "$password"
        return 0
    else
        # If generated password doesn't meet requirements, try again
        generate_secure_password "$length" "$include_symbols"
    fi
}

# Function to validate configuration files
validate_config_files() {
    log_info "Validating configuration files..."
    local missing_files=()
    
    # Check essential files
    if [[ ! -f "$ROOT_DIR/compose.yaml" ]]; then missing_files+=("compose.yaml"); fi
    if [[ ! -f "$ROOT_DIR/gordon-mcp.yml" ]]; then missing_files+=("gordon-mcp.yml"); fi
    
    # Report missing files
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "The following essential configuration files are missing: ${missing_files[*]}"
        return 1
    fi
    
    # Validate compose file
    log_info "Validating compose.yaml file..."
    if ! docker compose -f "$ROOT_DIR/compose.yaml" config > /dev/null; then
        log_error "compose.yaml is not valid"
        return 1
    fi
    
    # Validate gordon-mcp.yml file
    log_info "Validating gordon-mcp.yml file..."
    if ! docker compose -f "$ROOT_DIR/gordon-mcp.yml" config > /dev/null; then
        log_error "gordon-mcp.yml is not valid"
        return 1
    fi
    
    log_info "✅ Configuration files validated successfully"
    return 0
}

# Function to check system requirements
check_system_requirements() {
    log_info "Checking system requirements..."
    
    # Check disk space
    log_info "Checking available disk space..."
    local available_space
    available_space=$(df -h . | awk 'NR==2 {print $4}')
    log_info "Available disk space: $available_space"
    
    # Extract numeric value and unit
    local space_value
    local space_unit
    if [[ $available_space =~ ([0-9]+)([A-Za-z]) ]]; then
        space_value="${BASH_REMATCH[1]}"
        space_unit="${BASH_REMATCH[2]}"
        
        # Check if less than 10GB available
        if [[ "$space_unit" == "G" && "$space_value" -lt 10 ]] || [[ "$space_unit" == "M" ]]; then
            log_warn "Low disk space detected: $available_space"
            log_warn "MCP stack and models may require significant disk space"
            log_warn "Recommended: at least 10GB of free space"
        fi
    fi
    
    # Check memory
    if command -v free &> /dev/null; then
        log_info "Checking available memory..."
        local total_memory
        total_memory=$(free -h | awk '/^Mem:/ {print $2}')
        log_info "Total system memory: $total_memory"
        
        # Extract numeric value and unit
        local memory_value
        local memory_unit
        if [[ $total_memory =~ ([0-9]+)([A-Za-z]) ]]; then
            memory_value="${BASH_REMATCH[1]}"
            memory_unit="${BASH_REMATCH[2]}"
            
            # Check if less than 4GB memory
            if [[ "$memory_unit" == "G" && "$memory_value" -lt 4 ]] || [[ "$memory_unit" == "M" ]]; then
                log_warn "Low memory detected: $total_memory"
                log_warn "Running multiple models may require significant memory"
                log_warn "Recommended: at least 8GB of memory, 16GB+ for multiple models"
            fi
        fi
    fi
    
    # Check CPU cores
    if command -v nproc &> /dev/null; then
        log_info "Checking CPU cores..."
        local cpu_cores
        cpu_cores=$(nproc)
        log_info "CPU cores: $cpu_cores"
        
        if [[ "$cpu_cores" -lt 2 ]]; then
            log_warn "Low CPU core count detected: $cpu_cores"
            log_warn "Running models may be slow with limited CPU resources"
            log_warn "Recommended: at least 4 CPU cores"
        fi
    fi
    
    # Check for GPU
    log_info "Checking for NVIDIA GPU..."
    if command -v nvidia-smi &> /dev/null; then
        log_info "NVIDIA GPU detected"
        log_info "GPU information:"
        nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
    else
        log_warn "No NVIDIA GPU detected"
        log_warn "Models will run on CPU only, which may be significantly slower"
    fi
    
    log_info "✅ System requirements check completed"
    return 0
}

# Function to validate Docker image availability
validate_docker_images() {
    log_info "Validating Docker image availability..."
    
    # Load environment variables
    if [[ -f "$ROOT_DIR/.env" ]]; then
        set -a
        source "$ROOT_DIR/.env"
        set +a
    fi
    
    # List of required images
    local core_images=(
        "postgres:15"
        "mcp/time"
        "mcp/fetch"
        "mcp/filesystem"
        "mcp/postgres"
        "mcp/sqlite"
        "mcp/git"
    )
    
    # List of missing images
    local missing_images=()
    
    # Check core images
    for image in "${core_images[@]}"; do
        log_debug "Checking image: $image"
        if ! docker image inspect "$image" &> /dev/null; then
            missing_images+=("$image")
        fi
    done
    
    # Check model images based on environment variables
    for var in $(env | grep -E "^MODEL_PORT_" | cut -d '=' -f1); do
        # Convert MODEL_PORT_SMOLLM2 to smollm2
        local model
        model=$(echo "$var" | sed -E 's/MODEL_PORT_([^=]+)/\1/' | tr '[:upper:]' '[:lower:]' | tr '_' '-')
        log_debug "Checking model image: ai/$model"
        
        if ! docker image inspect "ai/$model" &> /dev/null; then
            missing_images+=("ai/$model")
        fi
    done
    
    # Report missing images
    if [[ ${#missing_images[@]} -gt 0 ]]; then
        log_warn "The following Docker images are not available locally:"
        for image in "${missing_images[@]}"; do
            log_warn "  - $image"
        done
        log_warn "Missing images will be pulled when needed"
    else
        log_info "✅ All required Docker images are available locally"
    fi
    
    return 0
}

# Function to run all validation checks
run_comprehensive_validation() {
    log_info "Running comprehensive validation..."
    local failed_checks=0
    
    # Check Docker
    if ! check_docker; then
        log_error "Docker validation failed"
        ((failed_checks++))
    fi
    
    # Validate environment variables
    if ! validate_env_vars; then
        log_error "Environment variable validation failed"
        ((failed_checks++))
    fi
    
    # Validate security configuration
    if ! validate_security_config; then
        log_warn "Security validation found issues (continuing with warnings)"
    fi
    
    # Validate configuration files
    if ! validate_config_files; then
        log_error "Configuration file validation failed"
        ((failed_checks++))
    fi
    
    # Check ports
    if ! check_ports; then
        log_error "Port validation failed"
        ((failed_checks++))
    fi
    
    # Check system requirements
    check_system_requirements || true  # Don't fail if system requirements check fails
    
    # Validate Docker images
    validate_docker_images || true  # Don't fail if image validation fails
    
    # Report results
    # Security validation
    log_info "Running security validation..."
    if validate_security_config; then
        log_info "✅ Security validation passed"
    else
        log_error "❌ Security validation failed"
        ((failed_checks++))
    fi

    if [[ $failed_checks -eq 0 ]]; then
        log_info "✅ All validation checks passed"
        return 0
    else
        log_error "❌ ${failed_checks} validation check(s) failed"
        return 1
    fi
}

# Print usage
print_usage() {
    cat << EOF
Validation Utilities for Docker MCP Stack

Usage: $0 <command> [options]

Commands:
  docker                   Check Docker installation
  ports                    Check if required ports are available
  env                      Validate environment variables
  config                   Validate configuration files
  system                   Check system requirements
  images                   Validate Docker image availability
  security                 Validate security configuration
  all                      Run all validation checks
  help                     Show this help message

Examples:
  $0 docker
  $0 env
  $0 all
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
        docker)
            check_docker
            ;;
        ports)
            check_ports
            ;;
        env)
            validate_env_vars
            ;;
        config)
            validate_config_files
            ;;
        system)
            check_system_requirements
            ;;
        images)
            validate_docker_images
            ;;
        all)
            run_comprehensive_validation
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
