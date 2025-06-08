#!/bin/bash
# Backup and Recovery Utility Library for Docker MCP Stack
# This script provides shared functions for backup and recovery operations

# Enable strict mode
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
UTILS_DIR="$ROOT_DIR/scripts/utils"
BACKUP_DIR="$ROOT_DIR/backups"
FULL_BACKUP_DIR="$BACKUP_DIR/full"
INCREMENTAL_BACKUP_DIR="$BACKUP_DIR/incremental"
DIFFERENTIAL_BACKUP_DIR="$BACKUP_DIR/differential"
BACKUP_LOGS_DIR="$BACKUP_DIR/logs"

# Import common utility functions
# shellcheck disable=SC1091
source "$UTILS_DIR/validation.sh"

# Set default values
DEFAULT_BACKUP_KEEP_FULL=5
DEFAULT_BACKUP_KEEP_INCREMENTAL=14
DEFAULT_BACKUP_KEEP_DIFFERENTIAL=7
DEFAULT_BACKUP_COMPRESSION="gzip" # Options: gzip, bzip2, xz
DEFAULT_BACKUP_VERIFICATION=true

# Backup types
BACKUP_TYPE_FULL="full"
BACKUP_TYPE_INCREMENTAL="incremental"
BACKUP_TYPE_DIFFERENTIAL="differential"
BACKUP_TYPE_SELECTIVE="selective"

# Common timestamp format for backups
TIMESTAMP_FORMAT="%Y%m%d_%H%M%S"

#-----------------------------------------------------------------------------
# Logging Functions
#-----------------------------------------------------------------------------

# Function to log a message to backup log file
log_backup() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_file="$BACKUP_LOGS_DIR/backup_$(date +%Y%m%d).log"
    
    # Create logs directory if it doesn't exist
    mkdir -p "$BACKUP_LOGS_DIR"
    
    # Determine log level prefix and color
    local prefix=""
    case "$level" in
        INFO)
            prefix="${GREEN}INFO${NC}"
            ;;
        WARN)
            prefix="${YELLOW}WARN${NC}"
            ;;
        ERROR)
            prefix="${RED}ERROR${NC}"
            ;;
        DEBUG)
            prefix="${CYAN}DEBUG${NC}"
            ;;
        *)
            prefix="INFO"
            ;;
    esac
    
    # Log to console
    echo -e "[$timestamp] $prefix: $message"
    
    # Log to file (without colors)
    echo "[$timestamp] $level: $message" >> "$log_file"
}

log_backup_info() {
    log_backup "INFO" "$1"
}

log_backup_warn() {
    log_backup "WARN" "$1"
}

log_backup_error() {
    log_backup "ERROR" "$1"
}

log_backup_debug() {
    if [[ "${BACKUP_DEBUG:-false}" == "true" ]]; then
        log_backup "DEBUG" "$1"
    fi
}

#-----------------------------------------------------------------------------
# Utility Functions
#-----------------------------------------------------------------------------

# Function to get current timestamp
get_timestamp() {
    date "+$TIMESTAMP_FORMAT"
}

# Function to generate a backup ID
generate_backup_id() {
    local backup_type="$1"
    local timestamp
    timestamp=$(get_timestamp)
    echo "${backup_type}_${timestamp}"
}

# Function to get the backup directory for a specific type
get_backup_dir() {
    local backup_type="$1"
    
    case "$backup_type" in
        "$BACKUP_TYPE_FULL")
            echo "$FULL_BACKUP_DIR"
            ;;
        "$BACKUP_TYPE_INCREMENTAL")
            echo "$INCREMENTAL_BACKUP_DIR"
            ;;
        "$BACKUP_TYPE_DIFFERENTIAL")
            echo "$DIFFERENTIAL_BACKUP_DIR"
            ;;
        "$BACKUP_TYPE_SELECTIVE")
            echo "$FULL_BACKUP_DIR/selective"
            ;;
        *)
            echo "$BACKUP_DIR"
            ;;
    esac
}

# Function to get metadata file path for a backup
get_metadata_path() {
    local backup_id="$1"
    local backup_type
    backup_type=$(echo "$backup_id" | cut -d'_' -f1)
    local backup_dir
    backup_dir=$(get_backup_dir "$backup_type")
    
    echo "$backup_dir/$backup_id.meta"
}

# Function to get archive file path for a backup
get_archive_path() {
    local backup_id="$1"
    local backup_type
    backup_type=$(echo "$backup_id" | cut -d'_' -f1)
    local backup_dir
    backup_dir=$(get_backup_dir "$backup_type")
    
    echo "$backup_dir/$backup_id.tar.gz"
}

# Function to check if a backup exists
backup_exists() {
    local backup_id="$1"
    local archive_path
    archive_path=$(get_archive_path "$backup_id")
    
    [[ -f "$archive_path" ]]
}

# Function to list all available backups
list_all_backups() {
    local backup_type="${1:-all}"
    local backup_dirs=()
    
    if [[ "$backup_type" == "all" || "$backup_type" == "$BACKUP_TYPE_FULL" ]]; then
        backup_dirs+=("$FULL_BACKUP_DIR")
    fi
    
    if [[ "$backup_type" == "all" || "$backup_type" == "$BACKUP_TYPE_INCREMENTAL" ]]; then
        backup_dirs+=("$INCREMENTAL_BACKUP_DIR")
    fi
    
    if [[ "$backup_type" == "all" || "$backup_type" == "$BACKUP_TYPE_DIFFERENTIAL" ]]; then
        backup_dirs+=("$DIFFERENTIAL_BACKUP_DIR")
    fi
    
    # Create a list of all backup files
    local backup_files=()
    for dir in "${backup_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            mapfile -t files < <(find "$dir" -maxdepth 1 -name "*.tar.gz" | sort -r)
            backup_files+=("${files[@]}")
        fi
    done
    
    # Print backup information
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log_backup_info "No backups found."
        return 0
    fi
    
    log_backup_info "Available backups:"
    local count=1
    for file in "${backup_files[@]}"; do
        local filename
        filename=$(basename "$file")
        local backup_id="${filename%.tar.gz}"
        local backup_type
        backup_type=$(echo "$backup_id" | cut -d'_' -f1)
        local timestamp
        timestamp=$(echo "$backup_id" | cut -d'_' -f2-3)
        local size
        size=$(du -h "$file" | cut -f1)
        
        # Format the timestamp for display
        local formatted_timestamp
        formatted_timestamp=$(date -d "${timestamp//_/ }" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp")
        
        echo "  $count. $backup_id ($backup_type, $formatted_timestamp, $size)"
        
        # Print metadata if available
        local metadata_path
        metadata_path=$(get_metadata_path "$backup_id")
        if [[ -f "$metadata_path" ]]; then
            echo "     Description: $(grep -i "^description:" "$metadata_path" | cut -d':' -f2- | sed 's/^[[:space:]]*//')"
        fi
        
