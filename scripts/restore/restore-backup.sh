#!/bin/bash
# Restore Script for Docker MCP Stack
# This script restores a backup of the Docker MCP Stack

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

# Function to list available backups
list_backups() {
    log_info "Listing available backups"
    list_all_backups
}

# Function to restore a backup
restore_backup() {
    local backup_id="$1"
    local components="$2"
    local force="$3"
    
    # Load environment configuration
    load_env_config
    
    log_info "Starting restore of backup ID: $backup_id"
    
    # Find the backup
    local backup_path=""
    local backup_type=""
    
    for type in "$BACKUP_TYPE_FULL" "$BACKUP_TYPE_INCREMENTAL" "$BACKUP_TYPE_DIFFERENTIAL" "$BACKUP_TYPE_SELECTIVE"; do
        local type_dir
        case "$type" in
            "$BACKUP_TYPE_FULL")
                type_dir="$BACKUP_DIR/full"
                ;;
            "$BACKUP_TYPE_INCREMENTAL")
                type_dir="$BACKUP_DIR/incremental"
                ;;
            "$BACKUP_TYPE_DIFFERENTIAL")
                type_dir="$BACKUP_DIR/differential"
                ;;
            "$BACKUP_TYPE_SELECTIVE")
                type_dir="$BACKUP_DIR/selective"
                ;;
        esac
        
        if [[ -d "$type_dir/$backup_id" ]]; then
            backup_path="$type_dir/$backup_id"
            backup_type="$type"
            break
        fi
    done
    
    if [[ -z "$backup_path" ]]; then
        log_error "Backup not found: $backup_id"
        return 1
    fi
    
    log_info "Found backup of type '$backup_type' at $backup_path"
    
    # For incremental backups, we need to handle parent backups
    if [[ "$backup_type" == "$BACKUP_TYPE_INCREMENTAL" ]]; then
        log_info "Preparing to restore an incremental backup"
        
        # Get parent backup ID
        local metadata_file="$backup_path/$METADATA_FILENAME"
        if [[ ! -f "$metadata_file" ]]; then
            log_error "Metadata file not found: $metadata_file"
            return 1
        fi
        
        local parent_backup_id
        if command -v jq &>/dev/null; then
            parent_backup_id=$(jq -r '.parent' "$metadata_file")
        else
            parent_backup_id=$(grep -o '"parent": "[^"]*"' "$metadata_file" | cut -d '"' -f 4)
        fi
        
        # Check if parent backup exists
        if [[ -z "$parent_backup_id" || "$parent_backup_id" == "null" ]]; then
            log_error "Parent backup ID not found in metadata"
            return 1
        fi
        
        local parent_backup_path
        parent_backup_path=$(get_backup_path "$BACKUP_TYPE_FULL" "$parent_backup_id")
        if [[ ! -d "$parent_backup_path" ]]; then
            log_error "Parent backup not found: $parent_backup_id"
            return 1
        fi
        
        log_info "Found parent backup: $parent_backup_id at $parent_backup_path"
    fi
    
    # Determine what to restore based on components parameter
    if [[ -z "$components" || "$components" == "all" ]]; then
        log_info "Restoring all components"
        
        # Restore configuration files
        if restore_config_files "$backup_path" "$force"; then
            log_info "Configuration files restored successfully"
        else
            log_error "Failed to restore configuration files"
            if [[ "$force" != "true" ]]; then
                log_error "Use --force to override conflicts"
                return 1
            fi
        fi
        
        # Get all MCP volumes
        local volumes=()
        if [[ "$backup_type" == "$BACKUP_TYPE_INCREMENTAL" ]]; then
            # For incremental backups, combine volumes from parent and incremental
            local parent_volumes=()
            local incremental_volumes=()
            
            # Get volumes from parent backup
            if [[ -d "$parent_backup_path/volumes" ]]; then
                while IFS= read -r volume_file; do
                    local volume_name
                    volume_name=$(basename "$volume_file" .tar.gz)
                    volume_name="${volume_name%.tar}"
                    parent_volumes+=("$volume_name")
                done < <(find "$parent_backup_path/volumes" -name "*.tar*")
            fi
            
            # Get volumes from incremental backup
            if [[ -d "$backup_path/volumes" ]]; then
                while IFS= read -r volume_file; do
                    local volume_name
                    volume_name=$(basename "$volume_file" .tar.gz)
                    volume_name="${volume_name%.tar}"
                    incremental_volumes+=("$volume_name")
                done < <(find "$backup_path/volumes" -name "*.tar*")
            fi
            
            # Combine the volumes, with incremental taking precedence
            for volume in "${parent_volumes[@]}"; do
                # Only add if not already in incremental_volumes
                if ! [[ " ${incremental_volumes[*]} " =~ " ${volume} " ]]; then
                    volumes+=("$volume")
                fi
            done
            
            # Add all incremental volumes
            volumes+=("${incremental_volumes[@]}")
        else
            # For full backups, just get volumes from the backup
            if [[ -d "$backup_path/volumes" ]]; then
                while IFS= read -r volume_file; do
                    local volume_name
                    volume_name=$(basename "$volume_file" .tar.gz)
                    volume_name="${volume_name%.tar}"
                    volumes+=("$volume_name")
                done < <(find "$backup_path/volumes" -name "*.tar*")
            fi
        fi
        
        # Check if any volumes were found
        if [[ ${#volumes[@]} -eq 0 ]]; then
            log_warn "No volumes found to restore"
        else
            log_info "Found ${#volumes[@]} volumes to restore"
        fi
        
        # Track successful and failed volumes
        local successful_volumes=()
        local failed_volumes=()
        
        # Stop the Docker MCP stack if running
        log_info "Stopping Docker MCP stack before restoring volumes"
        if docker-compose -f "$ROOT_DIR/compose.yaml" down; then
            log_info "Docker MCP stack stopped successfully"
        else
            log_warn "Failed to stop Docker MCP stack, proceeding anyway"
        fi
        
        # Restore each volume
        for volume in "${volumes[@]}"; do
            local restore_source="$backup_path"
            
            # For incremental backups, check if the volume exists in the incremental backup
            if [[ "$backup_type" == "$BACKUP_TYPE_INCREMENTAL" ]]; then
                if [[ -f "$backup_path/volumes/$volume.tar.gz" || -f "$backup_path/volumes/$volume.tar" ]]; then
                    restore_source="$backup_path"
                else
                    restore_source="$parent_backup_path"
                fi
            fi
            
            if restore_volume "$volume" "$restore_source" "$force"; then
                successful_volumes+=("$volume")
            else
                failed_volumes+=("$volume")
            fi
        done
        
        # Report results
        log_info "Successfully restored ${#successful_volumes[@]} volumes"
        if [[ ${#failed_volumes[@]} -gt 0 ]]; then
            log_warn "Failed to restore ${#failed_volumes[@]} volumes: ${failed_volumes[*]}"
        fi
        
        # Start the Docker MCP stack again
        log_info "Starting Docker MCP stack"
        if docker-compose -f "$ROOT_DIR/compose.yaml" up -d; then
            log_info "Docker MCP stack started successfully"
        else
            log_error "Failed to start Docker MCP stack"
            log_error "Please check configurations and try starting manually"
        fi
    else
        # Selective restore based on specified components
        log_info "Performing selective restore of components: $components"
        
        # Parse components
        IFS=',' read -ra component_array <<< "$components"
        
        for component in "${component_array[@]}"; do
            case "$component" in
                config)
                    log_info "Restoring configuration files"
                    if restore_config_files "$backup_path" "$force"; then
                        log_info "Configuration files restored successfully"
                    else
                        log_error "Failed to restore configuration files"
                    fi
                    ;;
                volume:*)
                    local volume_name
                    volume_name="${component#volume:}"
                    log_info "Restoring volume: $volume_name"
                    
                    # For incremental backups, check where the volume exists
                    local restore_source="$backup_path"
                    if [[ "$backup_type" == "$BACKUP_TYPE_INCREMENTAL" ]]; then
                        if [[ -f "$backup_path/volumes/$volume_name.tar.gz" || -f "$backup_path/volumes/$volume_name.tar" ]]; then
                            restore_source="$backup_path"
                        else
                            restore_source="$parent_backup_path"
                        fi
                    fi
                    
                    if restore_volume "$volume_name" "$restore_source" "$force"; then
                        log_info "Volume $volume_name restored successfully"
                    else
                        log_error "Failed to restore volume $volume_name"
                    fi
                    ;;
                *)
                    log_warn "Unknown component: $component"
                    ;;
            esac
        done
    fi
    
    # Create a restore log file
    local log_file="$BACKUP_DIR/logs/restore-$backup_id-$(get_timestamp).log"
    {
        echo "Restore Summary"
        echo "==============="
        echo "Backup ID: $backup_id"
        echo "Backup Type: $backup_type"
        echo "Timestamp: $(date)"
        echo "Components: ${components:-all}"
        echo "Force: $force"
        echo ""
        if [[ -n "${successful_volumes[*]}" ]]; then
            echo "Successfully restored volumes:"
            for volume in "${successful_volumes[@]}"; do
                echo "  - $volume"
            done
        fi
        echo ""
        if [[ -n "${failed_volumes[*]}" ]]; then
            echo "Failed to restore volumes:"
            for volume in "${failed_volumes[@]}"; do
                echo "  - $volume"
            done
        fi
    } > "$log_file"
    
    log_info "✅ Restore completed"
    log_info "Restore log: $log_file"
    
    return 0
}

# Print usage
print_usage() {
    cat << EOF
Restore Script for Docker MCP Stack

Usage: $0 [command] [options]

Commands:
  list                          List all available backups
  restore <backup_id> [options] Restore a specific backup

Options for 'restore':
  --components <component_list> Specify components to restore (comma-separated)
                                Use 'all' for everything (default)
                                For volumes, use 'volume:<name>'
                                Example: --components config,volume:mcp_data
  --force                       Force restore, overwriting existing data
  --help                        Show this help message

Examples:
  $0 list
  $0 restore backup_20250601_120000_abcdef
  $0 restore backup_20250601_120000_abcdef --components config
  $0 restore backup_20250601_120000_abcdef --force
EOF
}

# Main function
main() {
    # Check if no arguments were provided
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 1
    fi
    
    # Parse command
    local command="$1"
    shift
    
    case "$command" in
        list)
            list_backups
            ;;
        restore)
            if [[ $# -eq 0 ]]; then
                log_error "Error: Backup ID is required for restore"
                print_usage
                exit 1
            fi
            
            local backup_id="$1"
            shift
            
            local components="all"
            local force="false"
            
            # Parse options
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --components)
                        if [[ -n "$2" && "$2" != --* ]]; then
                            components="$2"
                            shift 2
                        else
                            log_error "Error: Argument for $1 is missing"
                            print_usage
                            exit 1
                        fi
                        ;;
                    --force)
                        force="true"
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
            
            restore_backup "$backup_id" "$components" "$force"
            ;;
        --help)
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
