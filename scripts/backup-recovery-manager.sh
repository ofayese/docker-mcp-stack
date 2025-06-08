#!/bin/bash
# Backup & Recovery Manager for Docker MCP Stack
# This script provides a central interface for backup and recovery operations

# Enable strict mode
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UTILS_DIR="$ROOT_DIR/scripts/utils"
BACKUP_DIR="$ROOT_DIR/scripts/backup"
RESTORE_DIR="$ROOT_DIR/scripts/restore"

# Import utility scripts
if [[ ! -f "$UTILS_DIR/backup-recovery.sh" ]]; then
    echo "Error: Backup & Recovery Utility Library not found at $UTILS_DIR/backup-recovery.sh"
    exit 1
fi

# shellcheck disable=SC1090
source "$UTILS_DIR/backup-recovery.sh"

# Check for required scripts
check_scripts() {
    local missing_scripts=()
    
    if [[ ! -f "$BACKUP_DIR/full-backup.sh" ]]; then
        missing_scripts+=("$BACKUP_DIR/full-backup.sh")
    fi
    
    if [[ ! -f "$BACKUP_DIR/incremental-backup.sh" ]]; then
        missing_scripts+=("$BACKUP_DIR/incremental-backup.sh")
    fi
    
    if [[ ! -f "$RESTORE_DIR/restore-backup.sh" ]]; then
        missing_scripts+=("$RESTORE_DIR/restore-backup.sh")
    fi
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        log_error "Required scripts not found:"
        for script in "${missing_scripts[@]}"; do
            log_error "  - $script"
        done
        return 1
    fi
    
    # Make scripts executable
    chmod +x "$BACKUP_DIR/full-backup.sh" "$BACKUP_DIR/incremental-backup.sh" "$RESTORE_DIR/restore-backup.sh"
    
    return 0
}

# Function to schedule backups using cron
schedule_backups() {
    local full_schedule="$1"
    local incremental_schedule="$2"
    
    log_info "Scheduling backups:"
    log_info "  Full backups: $full_schedule"
    log_info "  Incremental backups: $incremental_schedule"
    
    # Create cron directory if it doesn't exist
    mkdir -p "$ROOT_DIR/cron"
    
    # Create backup cron file
    local cron_file="$ROOT_DIR/cron/backup-cron"
    {
        echo "# Docker MCP Stack Backup Schedule"
        echo "# Generated on $(date)"
        echo ""
        echo "# Full backups"
        echo "$full_schedule $BACKUP_DIR/full-backup.sh >> $ROOT_DIR/backups/logs/scheduled-full-backup.log 2>&1"
        echo ""
        echo "# Incremental backups"
        echo "$incremental_schedule $BACKUP_DIR/incremental-backup.sh >> $ROOT_DIR/backups/logs/scheduled-incremental-backup.log 2>&1"
    } > "$cron_file"
    
    log_info "Created cron file at $cron_file"
    log_info "To install the cron jobs, run:"
    log_info "  crontab $cron_file"
    
    return 0
}

# Function to create an environment template with backup settings
create_env_template() {
    local template_file="$ROOT_DIR/.env.backup"
    
    log_info "Creating backup environment template at $template_file"
    
    # Create template file
    cat > "$template_file" << EOF
# Backup & Recovery Configuration
# Add these variables to your .env file

# Backup directory (default: $DEFAULT_BACKUP_DIR)
BACKUP_DIR=$DEFAULT_BACKUP_DIR

# Backup retention period in days (default: $DEFAULT_RETENTION_DAYS)
BACKUP_RETENTION_DAYS=$DEFAULT_RETENTION_DAYS

# Backup compression level (1-9, default: $DEFAULT_COMPRESSION_LEVEL)
BACKUP_COMPRESSION_LEVEL=$DEFAULT_COMPRESSION_LEVEL

# Enable backup encryption (true/false, default: $DEFAULT_ENABLE_ENCRYPTION)
BACKUP_ENABLE_ENCRYPTION=$DEFAULT_ENABLE_ENCRYPTION

# Enable backup verification (true/false, default: $DEFAULT_ENABLE_VERIFICATION)
BACKUP_ENABLE_VERIFICATION=$DEFAULT_ENABLE_VERIFICATION

# Maximum parallel backup operations (default: $DEFAULT_MAX_PARALLEL_OPERATIONS)
BACKUP_MAX_PARALLEL_OPERATIONS=$DEFAULT_MAX_PARALLEL_OPERATIONS
EOF
    
    log_info "Template created successfully"
    log_info "Copy these variables to your .env file to customize backup settings"
    
    return 0
}

# Function to perform a full backup
perform_full_backup() {
    log_info "Starting full backup"
    "$BACKUP_DIR/full-backup.sh" "$@"
}

# Function to perform an incremental backup
perform_incremental_backup() {
    log_info "Starting incremental backup"
    "$BACKUP_DIR/incremental-backup.sh" "$@"
}

# Function to restore a backup
restore_backup() {
    log_info "Starting backup restore"
    "$RESTORE_DIR/restore-backup.sh" restore "$@"
}

# Function to list backups
list_backups() {
    log_info "Listing available backups"
    "$RESTORE_DIR/restore-backup.sh" list
}

# Function to verify backup health
verify_backup_health() {
    local days="${1:-7}"
    
    log_info "Verifying backup health for the last $days days"
    
    # Load environment configuration
    load_env_config
    
    # Track issues
    local issues_found=0
    
    # Calculate cutoff date in seconds since epoch
    local cutoff
    cutoff=$(date -d "-$days days" +%s 2>/dev/null || 
             python -c "import time, datetime; print(int((datetime.datetime.now() - datetime.timedelta(days=$days)).timestamp()))" 2>/dev/null ||
             echo $(($(date +%s) - days * 86400)))
    
    # Find full backups in the period
    log_info "Checking full backups..."
    local full_count=0
    local full_issues=0
    
    while IFS= read -r metadata_file; do
        if [[ -f "$metadata_file" ]]; then
            local backup_dir
            backup_dir=$(dirname "$metadata_file")
            local timestamp
            local verified
            
            # Extract timestamp and verification status from metadata
            if command -v jq &>/dev/null; then
                timestamp_str=$(jq -r '.timestamp' "$metadata_file")
                verified=$(jq -r '.verified' "$metadata_file")
            else
                timestamp_str=$(grep -o '"timestamp": "[^"]*"' "$metadata_file" | cut -d '"' -f 4)
                verified=$(grep -o '"verified": [^,}]*' "$metadata_file" | cut -d ':' -f 2 | tr -d ' ')
            fi
            
            # Convert timestamp to seconds since epoch
            local backup_time
            backup_time=$(date -d "$timestamp_str" +%s 2>/dev/null || 
                         python -c "import time; print(int(time.mktime(time.strptime('$timestamp_str', '%Y%m%d_%H%M%S'))))" 2>/dev/null ||
                         echo 0)
            
            if [[ "$backup_time" -gt "$cutoff" ]]; then
                ((full_count++))
                
                # Check verification status
                if [[ "$verified" != "true" ]]; then
                    log_warn "Full backup at $backup_dir is not verified"
                    ((full_issues++))
                    ((issues_found++))
                fi
                
                # Check for volume files
                if [[ ! -d "$backup_dir/volumes" ]]; then
                    log_warn "Full backup at $backup_dir has no volumes directory"
                    ((full_issues++))
                    ((issues_found++))
                fi
                
                # Check for config files
                if [[ ! -f "$backup_dir/config.tar.gz" ]]; then
                    log_warn "Full backup at $backup_dir has no config archive"
                    ((full_issues++))
                    ((issues_found++))
                fi
            fi
        fi
    done < <(find "$BACKUP_DIR/full" -name "$METADATA_FILENAME" -type f)
    
    # Report full backup status
    if [[ $full_count -eq 0 ]]; then
        log_warn "No full backups found in the last $days days"
        ((issues_found++))
    else
        log_info "Found $full_count full backups in the last $days days"
        if [[ $full_issues -gt 0 ]]; then
            log_warn "Found $full_issues issues with full backups"
        else
            log_info "All full backups are healthy"
        fi
    fi
    
    # Find incremental backups in the period
    log_info "Checking incremental backups..."
    local incremental_count=0
    local incremental_issues=0
    
    while IFS= read -r metadata_file; do
        if [[ -f "$metadata_file" ]]; then
            local backup_dir
            backup_dir=$(dirname "$metadata_file")
            local timestamp
            local verified
            local parent
            
            # Extract timestamp, verification status, and parent ID from metadata
            if command -v jq &>/dev/null; then
                timestamp_str=$(jq -r '.timestamp' "$metadata_file")
                verified=$(jq -r '.verified' "$metadata_file")
                parent=$(jq -r '.parent' "$metadata_file")
            else
                timestamp_str=$(grep -o '"timestamp": "[^"]*"' "$metadata_file" | cut -d '"' -f 4)
                verified=$(grep -o '"verified": [^,}]*' "$metadata_file" | cut -d ':' -f 2 | tr -d ' ')
                parent=$(grep -o '"parent": "[^"]*"' "$metadata_file" | cut -d '"' -f 4)
            fi
            
            # Convert timestamp to seconds since epoch
            local backup_time
            backup_time=$(date -d "$timestamp_str" +%s 2>/dev/null || 
                         python -c "import time; print(int(time.mktime(time.strptime('$timestamp_str', '%Y%m%d_%H%M%S'))))" 2>/dev/null ||
                         echo 0)
            
            if [[ "$backup_time" -gt "$cutoff" ]]; then
                ((incremental_count++))
                
                # Check verification status
                if [[ "$verified" != "true" ]]; then
                    log_warn "Incremental backup at $backup_dir is not verified"
                    ((incremental_issues++))
                    ((issues_found++))
                fi
                
                # Check parent backup exists
                if [[ -n "$parent" && "$parent" != "null" ]]; then
                    local parent_path
                    parent_path=$(get_backup_path "$BACKUP_TYPE_FULL" "$parent")
                    if [[ ! -d "$parent_path" ]]; then
                        log_warn "Incremental backup at $backup_dir has missing parent backup: $parent"
                        ((incremental_issues++))
                        ((issues_found++))
                    fi
                else
                    log_warn "Incremental backup at $backup_dir has no parent backup ID"
                    ((incremental_issues++))
                    ((issues_found++))
                fi
            fi
        fi
    done < <(find "$BACKUP_DIR/incremental" -name "$METADATA_FILENAME" -type f)
    
    # Report incremental backup status
    if [[ $incremental_count -eq 0 ]]; then
        log_warn "No incremental backups found in the last $days days"
        ((issues_found++))
    else
        log_info "Found $incremental_count incremental backups in the last $days days"
        if [[ $incremental_issues -gt 0 ]]; then
            log_warn "Found $incremental_issues issues with incremental backups"
        else
            log_info "All incremental backups are healthy"
        fi
    fi
    
    # Check backup logs directory
    if [[ ! -d "$ROOT_DIR/backups/logs" ]]; then
        log_warn "Backup logs directory not found"
        ((issues_found++))
    else
        # Check for recent log files
        local recent_logs
        recent_logs=$(find "$ROOT_DIR/backups/logs" -name "*.log" -mtime -"$days" | wc -l)
        if [[ $recent_logs -eq 0 ]]; then
            log_warn "No recent backup logs found in the last $days days"
            ((issues_found++))
        else
            log_info "Found $recent_logs backup logs in the last $days days"
        fi
    fi
    
    # Final report
    if [[ $issues_found -eq 0 ]]; then
        log_info "✅ Backup health check passed - all systems healthy"
    else
        log_warn "⚠️ Backup health check found $issues_found issues"
    fi
    
    return $issues_found
}

# Print usage
print_usage() {
    cat << EOF
Backup & Recovery Manager for Docker MCP Stack

Usage: $0 <command> [options]

Commands:
  full-backup [options]              Perform a full backup
  incremental-backup [options]       Perform an incremental backup
  restore <backup_id> [options]      Restore a backup
  list                               List available backups
  schedule                           Schedule automatic backups
  health-check [days]                Check backup health (last N days, default: 7)
  create-env-template                Create environment variables template
  help                               Show this help message

Examples:
  $0 full-backup
  $0 incremental-backup
  $0 restore backup_20250601_120000_abcdef
  $0 list
  $0 schedule "0 2 * * 0" "0 2 * * 1-6"
  $0 health-check 14
  $0 create-env-template

For help with specific commands:
  $0 full-backup --help
  $0 incremental-backup --help
  $0 restore --help
EOF
}

# Main function
main() {
    # Check for required scripts
    if ! check_scripts; then
        log_error "Required scripts missing. Cannot continue."
        exit 1
    fi
    
    # Check if no arguments were provided
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 1
    fi
    
    # Parse command
    local command="$1"
    shift
    
    case "$command" in
        full-backup)
            perform_full_backup "$@"
            ;;
        incremental-backup)
            perform_incremental_backup "$@"
            ;;
        restore)
            restore_backup "$@"
            ;;
        list)
            list_backups
            ;;
        schedule)
            local full_schedule="${1:-0 2 * * 0}"  # Default: Sunday at 2 AM
            local inc_schedule="${2:-0 2 * * 1-6}" # Default: Monday-Saturday at 2 AM
            schedule_backups "$full_schedule" "$inc_schedule"
            ;;
        health-check)
            local days="${1:-7}"
            verify_backup_health "$days"
            ;;
        create-env-template)
            create_env_template
            ;;
        help)
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
