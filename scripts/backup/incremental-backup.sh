#!/bin/bash
# Incremental Backup Script for Docker MCP Stack
# This script creates an incremental backup of the Docker MCP Stack

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

# Function to perform an incremental backup
perform_incremental_backup() {
    local backup_id="${1:-}"
    local parent_backup_id="${2:-}"
    local verify="${3:-$BACKUP_ENABLE_VERIFICATION}"
    
    # Load environment configuration
    load_env_config
    
    # Generate backup ID if not provided
    if [[ -z "$backup_id" ]]; then
        backup_id=$(generate_backup_id)
    fi
    
    # Find the latest full backup if parent_backup_id not provided
    if [[ -z "$parent_backup_id" ]]; then
        log_info "No parent backup ID provided, finding latest full backup..."
        local latest_full_backup
        if ! latest_full_backup=$(find_latest_full_backup); then
            log_error "No full backup found to use as a parent"
            log_error "Please create a full backup first"
            return 1
        fi
        parent_backup_id=$(basename "$latest_full_backup")
        log_info "Using latest full backup as parent: $parent_backup_id"
    fi
    
    # Validate parent backup exists
    local parent_backup_path
    parent_backup_path=$(get_backup_path "$BACKUP_TYPE_FULL" "$parent_backup_id")
    if [[ ! -d "$parent_backup_path" ]]; then
        log_error "Parent backup not found: $parent_backup_id"
        return 1
    fi
    
    log_info "Starting incremental backup with ID: $backup_id"
    log_info "Parent backup: $parent_backup_id"
    
    # Create backup directory
    local backup_path
    backup_path=$(get_backup_path "$BACKUP_TYPE_INCREMENTAL" "$backup_id")
    mkdir -p "$backup_path"
    
    # Create metadata file with parent backup ID
    create_backup_metadata "$backup_path" "$BACKUP_TYPE_INCREMENTAL" "$parent_backup_id"
    
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
    local skipped_volumes=()
    
    # For each volume, check if it's changed since the parent backup
    for volume in "${volumes[@]}"; do
        # Create a checksum file for the current volume state
        log_info "Checking for changes in volume: $volume"
        
        # Check if the volume exists in the parent backup
        local parent_volume_backup="$parent_backup_path/volumes/$volume.tar.gz"
        if [[ ! -f "$parent_volume_backup" ]]; then
            parent_volume_backup="$parent_backup_path/volumes/$volume.tar"
            if [[ ! -f "$parent_volume_backup" ]]; then
                log_info "Volume $volume not found in parent backup, performing full backup of this volume"
                if backup_volume "$volume" "$backup_path" true; then
                    successful_volumes+=("$volume")
                else
                    failed_volumes+=("$volume")
                fi
                continue
            fi
        fi
        
        # Create a temporary checksum of the current volume state
        local temp_dir
        temp_dir=$(mktemp -d)
        local current_checksum_file="$temp_dir/current_checksum.txt"
        
        # Generate checksum for the current volume
        if docker run --rm -v "$volume":/source alpine sh -c "cd /source && find . -type f -exec sha256sum {} \; | sort" > "$current_checksum_file" 2>/dev/null; then
            # Generate checksum for the parent backup volume
            local parent_checksum_file="$temp_dir/parent_checksum.txt"
            
            # Extract the parent backup to a temporary directory
            local extract_dir="$temp_dir/extract"
            mkdir -p "$extract_dir"
            
            # Determine if the parent backup is compressed
            local is_compressed=false
            if [[ "$parent_volume_backup" == *.gz ]]; then
                is_compressed=true
            fi
            
            # Extract and generate checksum
            if [[ "$is_compressed" == "true" ]]; then
                docker run --rm -v "$(realpath "$parent_volume_backup")":/backup.tar.gz -v "$(realpath "$extract_dir")":/extract alpine sh -c "cd /extract && tar -xzf /backup.tar.gz && find . -type f -exec sha256sum {} \; | sort" > "$parent_checksum_file" 2>/dev/null
            else
                docker run --rm -v "$(realpath "$parent_volume_backup")":/backup.tar -v "$(realpath "$extract_dir")":/extract alpine sh -c "cd /extract && tar -xf /backup.tar && find . -type f -exec sha256sum {} \; | sort" > "$parent_checksum_file" 2>/dev/null
            fi
            
            # Compare checksums
            if diff -q "$current_checksum_file" "$parent_checksum_file" >/dev/null 2>&1; then
                log_info "No changes detected in volume $volume, skipping backup"
                skipped_volumes+=("$volume")
            else
                log_info "Changes detected in volume $volume, backing up"
                if backup_volume "$volume" "$backup_path" true; then
                    successful_volumes+=("$volume")
                else
                    failed_volumes+=("$volume")
                fi
            fi
        else
            log_warn "Failed to generate checksum for volume $volume, performing backup anyway"
            if backup_volume "$volume" "$backup_path" true; then
                successful_volumes+=("$volume")
            else
                failed_volumes+=("$volume")
            fi
        fi
        
        # Clean up temporary directory
        rm -rf "$temp_dir"
    done
    
    # Report results
    log_info "Successfully backed up ${#successful_volumes[@]} volumes"
    log_info "Skipped ${#skipped_volumes[@]} unchanged volumes"
    if [[ ${#failed_volumes[@]} -gt 0 ]]; then
        log_warn "Failed to backup ${#failed_volumes[@]} volumes: ${failed_volumes[*]}"
    fi
    
    # Calculate total backup size
    local backup_size
    backup_size=$(calculate_backup_size "$backup_path")
    log_info "Total incremental backup size: $backup_size"
    
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
    cleanup_old_backups "$BACKUP_TYPE_INCREMENTAL"
    
    # Create a summary log file
    local log_file="$BACKUP_DIR/logs/incremental-backup-$backup_id.log"
    {
        echo "Incremental Backup Summary"
        echo "=========================="
        echo "Backup ID: $backup_id"
        echo "Parent Backup ID: $parent_backup_id"
        echo "Timestamp: $(date)"
        echo "Backup Path: $backup_path"
        echo "Backup Size: $backup_size"
        echo ""
        echo "Successfully backed up ${#successful_volumes[@]} volumes:"
        for volume in "${successful_volumes[@]}"; do
            echo "  - $volume"
        done
        echo ""
        echo "Skipped ${#skipped_volumes[@]} unchanged volumes:"
        for volume in "${skipped_volumes[@]}"; do
            echo "  - $volume"
        done
        echo ""
        if [[ ${#failed_volumes[@]} -gt 0 ]]; then
            echo "Failed to backup ${#failed_volumes[@]} volumes:"
            for volume in "${failed_volumes[@]}"; do
                echo "  - $volume"
            done
        else
            echo "All changed volumes backed up successfully."
        fi
        echo ""
        echo "Backup verified: $verify"
    } > "$log_file"
    
    log_info "✅ Incremental backup completed successfully"
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
Incremental Backup Script for Docker MCP Stack

Usage: $0 [options]

Options:
  --id <backup_id>       Specify a custom backup ID (default: auto-generated)
  --parent <backup_id>   Specify a parent backup ID (default: latest full backup)
  --no-verify            Skip backup verification
  --help                 Show this help message

Examples:
  $0
  $0 --id my_incremental_backup
  $0 --parent my_full_backup
  $0 --no-verify
EOF
}

# Main function
main() {
    local backup_id=""
    local parent_backup_id=""
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
            --parent)
                if [[ -n "$2" && "$2" != --* ]]; then
                    parent_backup_id="$2"
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
    
    # Perform incremental backup
    perform_incremental_backup "$backup_id" "$parent_backup_id" "$verify"
}

# Execute main function if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
