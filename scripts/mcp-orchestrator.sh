#!/bin/bash
# MCP Orchestrator - Main orchestration script for Docker MCP Stack
# This script ties together all utilities and provides a central interface

# Enable strict mode
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UTILS_DIR="$ROOT_DIR/scripts/utils"
SERVICES_DIR="$ROOT_DIR/scripts/services"
TEST_DIR="$ROOT_DIR/scripts/test"

# Colors
RESET="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"

# Logging functions
log_error() { echo -e "${RED}[ERROR] $*${RESET}" >&2; }
log_warn() { echo -e "${YELLOW}[WARN] $*${RESET}" >&2; }
log_info() { echo -e "${GREEN}[INFO] $*${RESET}"; }
log_debug() { echo -e "${CYAN}[DEBUG] $*${RESET}"; }

# Check for required scripts
check_scripts() {
    local missing_scripts=()
    
    # Utility scripts
    if [[ ! -f "$UTILS_DIR/health-monitor.sh" ]]; then
        missing_scripts+=("$UTILS_DIR/health-monitor.sh")
    fi
    
    if [[ ! -f "$UTILS_DIR/validation.sh" ]]; then
        missing_scripts+=("$UTILS_DIR/validation.sh")
    fi

    if [[ ! -f "$UTILS_DIR/backup-recovery.sh" ]]; then
        missing_scripts+=("$UTILS_DIR/backup-recovery.sh")
    fi
    
    # Service scripts
    if [[ ! -f "$SERVICES_DIR/service-manager.sh" ]]; then
        missing_scripts+=("$SERVICES_DIR/service-manager.sh")
    fi
    
    # Test scripts
    if [[ ! -f "$TEST_DIR/benchmark.sh" ]]; then
        missing_scripts+=("$TEST_DIR/benchmark.sh")
    fi
    
    # Backup and recovery scripts
    if [[ ! -f "$SCRIPT_DIR/backup/full-backup.sh" ]]; then
        missing_scripts+=("$SCRIPT_DIR/backup/full-backup.sh")
    fi
    
    if [[ ! -f "$SCRIPT_DIR/backup/incremental-backup.sh" ]]; then
        missing_scripts+=("$SCRIPT_DIR/backup/incremental-backup.sh")
    fi
    
    if [[ ! -f "$SCRIPT_DIR/restore/restore-backup.sh" ]]; then
        missing_scripts+=("$SCRIPT_DIR/restore/restore-backup.sh")
    fi
    
    if [[ ! -f "$SCRIPT_DIR/backup-recovery-manager.sh" ]]; then
        missing_scripts+=("$SCRIPT_DIR/backup-recovery-manager.sh")
    fi
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        log_error "Required scripts not found:"
        for script in "${missing_scripts[@]}"; do
            log_error "  - $script"
        done
        log_error "Please install missing components or run the setup script"
        return 1
    fi
    
    return 0
}

# Function to display header
display_header() {
    echo ""
    echo "========================================================"
    echo "             DOCKER MCP STACK ORCHESTRATOR              "
    echo "========================================================"
    echo ""
}

# Function to handle health monitoring
run_health_check() {
    log_info "Running health checks..."
    bash "$UTILS_DIR/health-monitor.sh" "$@"
}

# Function to handle validation
run_validation() {
    log_info "Running validation checks..."
    bash "$UTILS_DIR/validation.sh" "$@"
}

# Function to handle service management
manage_services() {
    log_info "Managing services..."
    bash "$SERVICES_DIR/service-manager.sh" "$@"
}

# Function to handle performance benchmarking
run_benchmark() {
    log_info "Running performance benchmarks..."
    bash "$TEST_DIR/benchmark.sh" "$@"
}

# Function to handle backup and recovery
manage_backup_recovery() {
    log_info "Managing backup and recovery..."
    bash "$SCRIPT_DIR/backup-recovery-manager.sh" "$@"
}

# Function to run a comprehensive system check
run_system_check() {
    log_info "Running comprehensive system check..."
    
    # Run validation first
    log_info "Step 1: Configuration validation"
    if bash "$UTILS_DIR/validation.sh" --quiet; then
        log_info "✅ Configuration validation passed"
    else
        log_warn "⚠️ Configuration validation found issues"
    fi
    
    # Run health checks
    log_info "Step 2: Health monitoring"
    if bash "$UTILS_DIR/health-monitor.sh" --quiet; then
        log_info "✅ Health check passed"
    else
        log_warn "⚠️ Health check found issues"
    fi
    
    # Check backup health
    log_info "Step 3: Backup health check"
    if bash "$SCRIPT_DIR/backup-recovery-manager.sh" health-check 7 --quiet; then
        log_info "✅ Backup health check passed"
    else
        log_warn "⚠️ Backup health check found issues"
    fi
    
    log_info "System check complete"
}

# Function to show system status dashboard
show_dashboard() {
    log_info "Displaying system status dashboard..."
    
    display_header
    
    # Service status
    echo "SERVICE STATUS"
    echo "-------------"
    bash "$SERVICES_DIR/service-manager.sh" status
    echo ""
    
    # System health summary
    echo "SYSTEM HEALTH"
    echo "-------------"
    bash "$UTILS_DIR/health-monitor.sh" --summary
    echo ""
    
    # Recent backups
    echo "RECENT BACKUPS"
    echo "-------------"
    bash "$SCRIPT_DIR/backup-recovery-manager.sh" list --last 5
    echo ""
    
    # Performance metrics
    echo "PERFORMANCE METRICS"
    echo "-----------------"
    bash "$TEST_DIR/benchmark.sh" --summary
    echo ""
}

# Function to initialize system
initialize_system() {
    log_info "Initializing Docker MCP Stack system..."
    
    # Create necessary directories
    log_info "Creating directory structure..."
    mkdir -p "$ROOT_DIR/backups/full"
    mkdir -p "$ROOT_DIR/backups/incremental"
    mkdir -p "$ROOT_DIR/backups/differential"
    mkdir -p "$ROOT_DIR/backups/logs"
    
    # Create environment template
    log_info "Creating environment templates..."
    bash "$SCRIPT_DIR/backup-recovery-manager.sh" create-env-template
    
    # Make scripts executable
    log_info "Setting execution permissions..."
    chmod +x "$UTILS_DIR"/*.sh "$SERVICES_DIR"/*.sh "$TEST_DIR"/*.sh "$SCRIPT_DIR/backup"/*.sh "$SCRIPT_DIR/restore"/*.sh "$SCRIPT_DIR"/*.sh 2>/dev/null || true
    
    # Authenticate with Docker Hub if credentials are provided
    if [[ -f "$ROOT_DIR/.env" ]]; then
        # Source the .env file to get Docker Hub credentials
        # shellcheck disable=SC1090
        source "$ROOT_DIR/.env"
        
        if [[ -n "${DOCKER_HUB_USERNAME:-}" && -n "${DOCKER_HUB_TOKEN:-}" ]]; then
            log_info "Authenticating with Docker Hub..."
            if echo "$DOCKER_HUB_TOKEN" | docker login -u "$DOCKER_HUB_USERNAME" --password-stdin; then
                log_info "✅ Docker Hub authentication successful"
            else
                log_warn "⚠️ Docker Hub authentication failed"
            fi
        else
            log_info "No Docker Hub credentials found, skipping authentication"
        fi
    fi
    
    log_info "System initialization complete"
}

# Print usage
print_usage() {
    cat << EOF
MCP Orchestrator - Main orchestration script for Docker MCP Stack

Usage: $0 <command> [options]

Commands:
  health                           Run health checks
  validate                         Run validation checks
  service <subcommand> [options]   Manage services
  benchmark [options]              Run performance benchmarks
  backup <subcommand> [options]    Manage backups and recovery
  check                            Run comprehensive system check
  dashboard                        Show system status dashboard
  init                             Initialize system
  help                             Show this help message

Examples:
  $0 health
  $0 validate
  $0 service start --all
  $0 benchmark --model gpt-4
  $0 backup full-backup
  $0 check
  $0 dashboard
  $0 init

For help with specific commands:
  $0 health --help
  $0 service --help
  $0 benchmark --help
  $0 backup --help
EOF
}

# Main function
main() {
    # Check if no arguments were provided
    if [[ $# -eq 0 ]]; then
        display_header
        print_usage
        exit 1
    fi
    
    # Parse command
    local command="$1"
    shift
    
    case "$command" in
        health)
            run_health_check "$@"
            ;;
        validate)
            run_validation "$@"
            ;;
        service)
            manage_services "$@"
            ;;
        benchmark)
            run_benchmark "$@"
            ;;
        backup)
            manage_backup_recovery "$@"
            ;;
        check)
            run_system_check
            ;;
        dashboard)
            show_dashboard
            ;;
        init)
            initialize_system
            ;;
        help)
            display_header
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            print_usage
            exit 1
            ;;
    esac
}

# Execute main function if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
