#!/bin/bash
# Full Backup Script for Docker MCP Stack
# This script creates a complete backup of the Docker MCP Stack

# Enable strict mode
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
UTILS_DIR="$ROOT_DIR/scripts/utils"

# Import utility scripts
if [[ ! -f "$UTILS_DIR/backup-recovery.sh" ]]; then
    echo "Error: Backup & Recovery Utility Library not found at $UTILS_DIR/backup-recovery.sh"
    exit 1
fi

# shellcheck disable=SC1090
source "$UTILS_DIR/backup-recovery.sh"

# Function to perform a full backup
perform_full_backup() {
    local backup_id="${1:-}"
    local verify="${2:-$BACKUP_ENABLE_VERIFICATION}"
    
    # Load environment configuration
    load_env_config
    
    # Generate backup ID if not provided
    if [[ -z "$backup_id" ]]; then
        backup_id=$(generate_backup_id)
    fi
    
    log_info "Starting full backup with ID: $backup_id"
    
    # Create backup directory
    local backup_path
    backup_path=$(get_backup_path "$BACKUP_TYPE_FULL" "$backup_id")
    mkdir -p "$backup_path"
    
    # Create metadata file
    create_backup_metadata "$backup_path" "$BACKUP_TYPE_FULL"
    
    # Backup configuration files
    if ! backup_config_files "$backup_path"; then
        log_error "Failed to backup configuration files"
        return 1
    fi
    
    # Get all MCP volumes
    local volumes=()
    mapfile -t volumes < <(get_mcp_volumes)
    
    # Check if any volumes were found
    if [[ ${#volumes[@]} -eq 0 ]]; then
        log_warn "No MCP volumes found to backup"
    else
        log_info "Found ${#volumes[@]} MCP volumes to backup"
    fi
    
    # Track successful and failed volumes
    local successful_volumes=()
    local failed_volumes=()
    
    # Backup each volume
    for volume in "${volumes[@]}"; do
        if backup_volume "$volume" "$backup_path" true; then
            successful_volumes+=("$volume")
        else
            failed_volumes+=("$volume")
        fi
    done
    
    # Report results
    log_info "Successfully backed up ${#successful_volumes[@]} volumes"
    if [[ ${#failed_volumes[@]} -gt 0 ]]; then
        log_warn "Failed to backup ${#failed_volumes[@]} volumes: ${failed_volumes[*]}"
    fi
    
    # Calculate total backup size
    local backup_size
    backup_size=$(calculate_backup_size "$backup_path")
    log_info "Total backup size: $backup_size"
    
    # Verify backup if requested
    if [[ "$verify" == "true" ]]; then
        log_info "Verifying backup..."
        if verify_backup "$backup_path"; then
            log_info "Backup verification successful"
        else
            log_error "Backup verification failed"
            return 1
        fi
    fi
    
    # Cleanup old backups based on retention policy
    cleanup_old_backups "$BACKUP_TYPE_FULL"
    
    # Create a summary log file
    local log_file="$BACKUP_DIR/logs/full-backup-$backup_id.log"
    {
        echo "Full Backup Summary"
        echo "==================="
        echo "Backup ID: $backup_id"
        echo "Timestamp: $(date)"
        echo "Backup Path: $backup_path"
        echo "Backup Size: $backup_size"
        echo ""
        echo "Successfully backed up ${#successful_volumes[@]} volumes:"
        for volume in "${successful_volumes[@]}"; do
            echo "  - $volume"
        done
        echo ""
        if [[ ${#failed_volumes[@]} -gt 0 ]]; then
            echo "Failed to backup ${#failed_volumes[@]} volumes:"
            for volume in "${failed_volumes[@]}"; do
                echo "  - $volume"
            done
        else
            echo "All volumes backed up successfully."
        fi
        echo ""
        echo "Backup verified: $verify"
    } > "$log_file"
    
    log_info "✅ Full backup completed successfully"
    log_info "Backup ID: $backup_id"
    log_info "Backup Path: $backup_path"
    log_info "Backup Summary: $log_file"
    
    # Return the backup ID for scripts that might use it
    echo "$backup_id"
    return 0
}

# Print usage
print_usage() {
    cat << EOF
Full Backup Script for Docker MCP Stack

Usage: $0 [options]

Options:
  --id <backup_id>    Specify a custom backup ID (default: auto-generated)
  --no-verify         Skip backup verification
  --help              Show this help message

Examples:
  $0
  $0 --id my_custom_backup
  $0 --no-verify
EOF
}

# Main function
main() {
    local backup_id=""
    local verify="$BACKUP_ENABLE_VERIFICATION"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id)
                if [[ -n "$2" && "$2" != --* ]]; then
                    backup_id="$2"
                    shift 2
                else
                    log_error "Error: Argument for $1 is missing"
                    print_usage
                    exit 1
                fi
                ;;
            --no-verify)
                verify="false"
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Perform full backup
    perform_full_backup "$backup_id" "$verify"
}

# Execute main function if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
