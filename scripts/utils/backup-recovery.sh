#!/bin/bash
# Backup & Recovery Utility Library for Docker MCP Stack
# This script provides common functions for backup and recovery operations

# Enable strict mode
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
UTILS_DIR="$ROOT_DIR/scripts/utils"

# Import utility scripts if they exist
if [[ -f "$UTILS_DIR/validation.sh" ]]; then
    # shellcheck disable=SC1091
    source "$UTILS_DIR/validation.sh"
else
    # Define minimal logging functions if validation.sh is not available
    # ANSI color codes
    RESET="\033[0m"
    RED="\033[31m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    BLUE="\033[34m"
    CYAN="\033[36m"

    log_error() {
        echo -e "${RED}[ERROR] $*${RESET}" >&2
    }

    log_warn() {
        echo -e "${YELLOW}[WARN] $*${RESET}" >&2
    }

    log_info() {
        echo -e "${GREEN}[INFO] $*${RESET}"
    }

    log_debug() {
        echo -e "${CYAN}[DEBUG] $*${RESET}"
    }
fi

# Backup types
BACKUP_TYPE_FULL="full"
BACKUP_TYPE_INCREMENTAL="incremental"
BACKUP_TYPE_DIFFERENTIAL="differential"
BACKUP_TYPE_SELECTIVE="selective"

# Default settings
DEFAULT_BACKUP_DIR="$ROOT_DIR/backups"
DEFAULT_RETENTION_DAYS=30
DEFAULT_COMPRESSION_LEVEL=6
DEFAULT_ENABLE_ENCRYPTION=false
DEFAULT_ENABLE_VERIFICATION=true
DEFAULT_MAX_PARALLEL_OPERATIONS=2

# Metadata file name
METADATA_FILENAME="backup-metadata.json"

# Load configuration from .env file
load_env_config() {
    if [[ -f "$ROOT_DIR/.env" ]]; then
        log_debug "Loading environment variables from .env file"
        set -a
        # shellcheck disable=SC1091
        source "$ROOT_DIR/.env"
        set +a
    else
        log_warn "No .env file found, using default settings"
    fi

    # Set configuration variables with defaults from .env or use hardcoded defaults
    BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
    BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-$DEFAULT_RETENTION_DAYS}"
    BACKUP_COMPRESSION_LEVEL="${BACKUP_COMPRESSION_LEVEL:-$DEFAULT_COMPRESSION_LEVEL}"
    BACKUP_ENABLE_ENCRYPTION="${BACKUP_ENABLE_ENCRYPTION:-$DEFAULT_ENABLE_ENCRYPTION}"
    BACKUP_ENABLE_VERIFICATION="${BACKUP_ENABLE_VERIFICATION:-$DEFAULT_ENABLE_VERIFICATION}"
    BACKUP_MAX_PARALLEL_OPERATIONS="${BACKUP_MAX_PARALLEL_OPERATIONS:-$DEFAULT_MAX_PARALLEL_OPERATIONS}"
    
    # Export for subprocesses
    export BACKUP_DIR
    export BACKUP_RETENTION_DAYS
    export BACKUP_COMPRESSION_LEVEL
    export BACKUP_ENABLE_ENCRYPTION
    export BACKUP_ENABLE_VERIFICATION
    export BACKUP_MAX_PARALLEL_OPERATIONS
}

# Generate a timestamp in the format YYYYMMdd_HHMMSS
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# Generate a unique backup ID
generate_backup_id() {
    local timestamp
    timestamp=$(get_timestamp)
    local random
    random=$(hexdump -n 4 -e '4/4 "%08X" 1 "\n"' /dev/urandom 2>/dev/null || 
             python -c "import random; print(format(random.randint(0, 0xFFFFFFFF), '08x'))" 2>/dev/null || 
             echo "$(( RANDOM % 10000 ))")
    
    echo "backup_${timestamp}_${random}"
}

# Get the path for a backup type
get_backup_path() {
    local backup_type="$1"
    local backup_id="$2"
    local backup_path

    case "$backup_type" in
        "$BACKUP_TYPE_FULL")
            backup_path="$BACKUP_DIR/full/$backup_id"
            ;;
        "$BACKUP_TYPE_INCREMENTAL")
            backup_path="$BACKUP_DIR/incremental/$backup_id"
            ;;
        "$BACKUP_TYPE_DIFFERENTIAL")
            backup_path="$BACKUP_DIR/differential/$backup_id"
            ;;
        "$BACKUP_TYPE_SELECTIVE")
            backup_path="$BACKUP_DIR/selective/$backup_id"
            ;;
        *)
            log_error "Unknown backup type: $backup_type"
            return 1
            ;;
    esac

    echo "$backup_path"
}

# Create backup metadata file
create_backup_metadata() {
    local backup_path="$1"
    local backup_type="$2"
    local parent_backup_id="${3:-}"
    local selected_components="${4:-}"
    local timestamp
    timestamp=$(get_timestamp)
    
    local metadata_file="$backup_path/$METADATA_FILENAME"
    
    # Create metadata JSON
    cat > "$metadata_file" << EOF
{
    "timestamp": "$timestamp",
    "type": "$backup_type",
    "parent": "$parent_backup_id",
    "components": [$selected_components],
    "hostname": "$(hostname)",
    "docker_version": "$(docker --version 2>/dev/null || echo 'unknown')",
    "compression_level": "$BACKUP_COMPRESSION_LEVEL",
    "encrypted": $BACKUP_ENABLE_ENCRYPTION,
    "verified": false
}
EOF

    log_debug "Created backup metadata at $metadata_file"
}

# Update backup metadata
update_backup_metadata() {
    local backup_path="$1"
    local key="$2"
    local value="$3"
    
    local metadata_file="$backup_path/$METADATA_FILENAME"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_error "Metadata file not found at $metadata_file"
        return 1
    fi
    
    # Check if jq is available
    if command -v jq &>/dev/null; then
        # Use jq to update the metadata
        local temp_file
        temp_file=$(mktemp)
        jq ".$key = $value" "$metadata_file" > "$temp_file"
        mv "$temp_file" "$metadata_file"
    else
        # Fallback to sed (less robust)
        log_warn "jq not found, using sed to update metadata (less reliable)"
        sed -i "s/\"$key\": .*,/\"$key\": $value,/" "$metadata_file"
    fi
    
    log_debug "Updated backup metadata: $key = $value"
}

# Get all Docker volumes
get_all_volumes() {
    log_debug "Getting all Docker volumes"
    docker volume ls --format "{{.Name}}"
}

# Get MCP-related Docker volumes
get_mcp_volumes() {
    log_debug "Getting MCP-related Docker volumes"
    docker volume ls --format "{{.Name}}" | grep -E "^(mcp_|gordon_)"
}

# Check if a volume exists
volume_exists() {
    local volume_name="$1"
    docker volume inspect "$volume_name" &>/dev/null
}

# Backup a Docker volume
backup_volume() {
    local volume_name="$1"
    local backup_path="$2"
    local compress="${3:-true}"
    
    if ! volume_exists "$volume_name"; then
        log_warn "Volume $volume_name does not exist, skipping backup"
        return 0
    fi
    
    log_info "Backing up volume: $volume_name"
    mkdir -p "$backup_path/volumes"
    
    local compression_args=""
    if [[ "$compress" == "true" ]]; then
        compression_args="-z"
    fi
    
    # Create volume backup using tar
    if ! docker run --rm -v "$volume_name":/source -v "$(realpath "$backup_path/volumes")":/backup \
         alpine sh -c "cd /source && tar -c $compression_args -f /backup/$volume_name.tar${compress:+.gz} ."; then
        log_error "Failed to backup volume $volume_name"
        return 1
    fi
    
    # Create checksum for the backup file
    local backup_file="$backup_path/volumes/$volume_name.tar${compress:+.gz}"
    create_checksum "$backup_file"
    
    log_info "✅ Volume $volume_name backed up successfully"
    return 0
}

# Create a checksum file for a given file
create_checksum() {
    local file="$1"
    local checksum_file="$file.sha256"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    # Create checksum file
    if command -v sha256sum &>/dev/null; then
        sha256sum "$file" | cut -d ' ' -f 1 > "$checksum_file"
    elif command -v openssl &>/dev/null; then
        openssl dgst -sha256 "$file" | cut -d ' ' -f 2 > "$checksum_file"
    else
        log_warn "No checksum tool found (sha256sum or openssl), skipping checksum creation"
        return 0
    fi
    
    log_debug "Created checksum for $file: $(cat "$checksum_file")"
    return 0
}

# Verify a checksum file against its source file
verify_checksum() {
    local file="$1"
    local checksum_file="$file.sha256"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    if [[ ! -f "$checksum_file" ]]; then
        log_error "Checksum file not found: $checksum_file"
        return 1
    fi
    
    local expected_checksum
    expected_checksum=$(cat "$checksum_file")
    
    local actual_checksum
    if command -v sha256sum &>/dev/null; then
        actual_checksum=$(sha256sum "$file" | cut -d ' ' -f 1)
    elif command -v openssl &>/dev/null; then
        actual_checksum=$(openssl dgst -sha256 "$file" | cut -d ' ' -f 2)
    else
        log_warn "No checksum tool found (sha256sum or openssl), skipping verification"
        return 0
    fi
    
    if [[ "$expected_checksum" == "$actual_checksum" ]]; then
        log_debug "Checksum verified for $file"
        return 0
    else
        log_error "Checksum verification failed for $file"
        log_error "Expected: $expected_checksum"
        log_error "Actual:   $actual_checksum"
        return 1
    fi
}

# Backup configuration files
backup_config_files() {
    local backup_path="$1"
    
    log_info "Backing up configuration files"
    mkdir -p "$backup_path/config"
    
    # List of configuration files to backup
    local config_files=(
        ".env"
        "gordon-mcp.yml"
        "compose.yaml"
        "Makefile"
        "run.sh"
    )
    
    # List of directories to backup
    local config_dirs=(
        "nginx"
        "prometheus"
        "grafana"
        "cron"
    )
    
    # Backup individual files
    for file in "${config_files[@]}"; do
        if [[ -f "$ROOT_DIR/$file" ]]; then
            cp "$ROOT_DIR/$file" "$backup_path/config/" || log_warn "Failed to backup $file"
        fi
    done
    
    # Backup directories
    for dir in "${config_dirs[@]}"; do
        if [[ -d "$ROOT_DIR/$dir" ]]; then
            cp -r "$ROOT_DIR/$dir" "$backup_path/config/" || log_warn "Failed to backup directory $dir"
        fi
    done
    
    # Create a tar archive of the config directory
    (cd "$backup_path" && tar -czf "config.tar.gz" config && rm -rf config)
    
    # Create checksum for the config archive
    create_checksum "$backup_path/config.tar.gz"
    
    log_info "✅ Configuration files backed up successfully"
    return 0
}

# Find the latest full backup
find_latest_full_backup() {
    local full_backup_dir="$BACKUP_DIR/full"
    
    if [[ ! -d "$full_backup_dir" ]]; then
        log_error "Full backup directory not found: $full_backup_dir"
        return 1
    fi
    
    # Find directories with metadata files
    local latest_backup=""
    local latest_timestamp=0
    
    while IFS= read -r metadata_file; do
        if [[ -f "$metadata_file" ]]; then
            local backup_dir
            backup_dir=$(dirname "$metadata_file")
            local timestamp
            
            # Extract timestamp from metadata
            if command -v jq &>/dev/null; then
                timestamp=$(jq -r '.timestamp' "$metadata_file" | tr -d '[:punct:]' | tr -d '[:alpha:]' | tr -d ' ')
            else
                timestamp=$(grep -o '"timestamp": "[^"]*"' "$metadata_file" | cut -d '"' -f 4 | tr -d '[:punct:]' | tr -d '[:alpha:]' | tr -d ' ')
            fi
            
            if [[ "$timestamp" -gt "$latest_timestamp" ]]; then
                latest_timestamp=$timestamp
                latest_backup=$backup_dir
            fi
        fi
    done < <(find "$full_backup_dir" -name "$METADATA_FILENAME" -type f)
    
    if [[ -z "$latest_backup" ]]; then
        log_error "No full backups found"
        return 1
    fi
    
    echo "$latest_backup"
    return 0
}

# Calculate backup size
calculate_backup_size() {
    local backup_path="$1"
    
    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup directory not found: $backup_path"
        return 1
    fi
    
    local size
    if command -v du &>/dev/null; then
        size=$(du -sh "$backup_path" | cut -f1)
    else
        size="unknown"
    fi
    
    echo "$size"
    return 0
}

# Verify a backup
verify_backup() {
    local backup_path="$1"
    
    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup directory not found: $backup_path"
        return 1
    fi
    
    local metadata_file="$backup_path/$METADATA_FILENAME"
    if [[ ! -f "$metadata_file" ]]; then
        log_error "Metadata file not found: $metadata_file"
        return 1
    }
    
    log_info "Verifying backup: $backup_path"
    local verification_failed=false
    
    # Verify checksums for all files with .sha256 extension
    while IFS= read -r checksum_file; do
        local file="${checksum_file%.sha256}"
        if [[ -f "$file" ]]; then
            if ! verify_checksum "$file"; then
                verification_failed=true
            fi
        else
            log_error "File not found for checksum: $file"
            verification_failed=true
        fi
    done < <(find "$backup_path" -name "*.sha256" -type f)
    
    if [[ "$verification_failed" == "true" ]]; then
        log_error "❌ Backup verification failed"
        return 1
    else
        log_info "✅ Backup verification successful"
        # Update metadata to mark as verified
        update_backup_metadata "$backup_path" "verified" "true"
        return 0
    fi
}

# Clean up old backups based on retention policy
cleanup_old_backups() {
    local backup_type="$1"
    local retention_days="${2:-$BACKUP_RETENTION_DAYS}"
    
    local backup_dir
    case "$backup_type" in
        "$BACKUP_TYPE_FULL")
            backup_dir="$BACKUP_DIR/full"
            ;;
        "$BACKUP_TYPE_INCREMENTAL")
            backup_dir="$BACKUP_DIR/incremental"
            ;;
        "$BACKUP_TYPE_DIFFERENTIAL")
            backup_dir="$BACKUP_DIR/differential"
            ;;
        "$BACKUP_TYPE_SELECTIVE")
            backup_dir="$BACKUP_DIR/selective"
            ;;
        *)
            log_error "Unknown backup type: $backup_type"
            return 1
            ;;
    esac
    
    if [[ ! -d "$backup_dir" ]]; then
        log_warn "Backup directory not found: $backup_dir"
        return 0
    }
    
    log_info "Cleaning up old $backup_type backups (retention: $retention_days days)"
    
    # Calculate cutoff date in seconds since epoch
    local cutoff
    cutoff=$(date -d "-$retention_days days" +%s 2>/dev/null || 
             python -c "import time, datetime; print(int((datetime.datetime.now() - datetime.timedelta(days=$retention_days)).timestamp()))" 2>/dev/null ||
             echo $(($(date +%s) - retention_days * 86400)))
    
    local deleted_count=0
    
    # Find directories with metadata files
    while IFS= read -r metadata_file; do
        if [[ -f "$metadata_file" ]]; then
            local backup_dir
            backup_dir=$(dirname "$metadata_file")
            local timestamp
            
            # Extract timestamp from metadata
            if command -v jq &>/dev/null; then
                timestamp_str=$(jq -r '.timestamp' "$metadata_file")
            else
                timestamp_str=$(grep -o '"timestamp": "[^"]*"' "$metadata_file" | cut -d '"' -f 4)
            fi
            
            # Convert timestamp to seconds since epoch
            local backup_time
            backup_time=$(date -d "$timestamp_str" +%s 2>/dev/null || 
                         python -c "import time; print(int(time.mktime(time.strptime('$timestamp_str', '%Y%m%d_%H%M%S'))))" 2>/dev/null ||
                         echo 0)
            
            if [[ "$backup_time" -lt "$cutoff" ]]; then
                log_info "Deleting old backup: $backup_dir"
                rm -rf "$backup_dir"
                ((deleted_count++))
            fi
        fi
    done < <(find "$backup_dir" -name "$METADATA_FILENAME" -type f)
    
    log_info "Deleted $deleted_count old $backup_type backup(s)"
    return 0
}

# Restore a Docker volume from a backup
restore_volume() {
    local volume_name="$1"
    local backup_path="$2"
    local force="${3:-false}"
    
    local backup_file="$backup_path/volumes/$volume_name.tar.gz"
    if [[ ! -f "$backup_file" ]]; then
        # Try without compression
        backup_file="$backup_path/volumes/$volume_name.tar"
        if [[ ! -f "$backup_file" ]]; then
            log_error "Backup file not found for volume $volume_name"
            return 1
        fi
    fi
    
    # Verify the backup file
    if [[ -f "$backup_file.sha256" ]]; then
        if ! verify_checksum "$backup_file"; then
            log_error "Checksum verification failed for $backup_file"
            if [[ "$force" != "true" ]]; then
                log_error "Use --force to restore anyway"
                return 1
            else
                log_warn "Proceeding with restore despite checksum failure (--force enabled)"
            fi
        fi
    else
        log_warn "No checksum file found for $backup_file, skipping verification"
    fi
    
    # Check if volume exists
    if volume_exists "$volume_name"; then
        if [[ "$force" != "true" ]]; then
            log_error "Volume $volume_name already exists"
            log_error "Use --force to overwrite existing volume"
            return 1
        else
            log_warn "Overwriting existing volume $volume_name (--force enabled)"
        fi
    else
        # Create volume if it doesn't exist
        log_info "Creating volume $volume_name"
        docker volume create "$volume_name"
    fi
    
    log_info "Restoring volume $volume_name from $backup_file"
    
    # Determine if backup is compressed
    local is_compressed=false
    if [[ "$backup_file" == *.gz ]]; then
        is_compressed=true
    fi
    
    # Restore volume data
    if [[ "$is_compressed" == "true" ]]; then
        if ! docker run --rm -v "$volume_name":/dest -v "$(realpath "$backup_path/volumes")":/backup \
             alpine sh -c "rm -rf /dest/* /dest/.[!.]* 2>/dev/null || true && cd /dest && tar -xzf /backup/$(basename "$backup_file")"; then
            log_error "Failed to restore volume $volume_name"
            return 1
        fi
    else
        if ! docker run --rm -v "$volume_name":/dest -v "$(realpath "$backup_path/volumes")":/backup \
             alpine sh -c "rm -rf /dest/* /dest/.[!.]* 2>/dev/null || true && cd /dest && tar -xf /backup/$(basename "$backup_file")"; then
            log_error "Failed to restore volume $volume_name"
            return 1
        fi
    fi
    
    log_info "✅ Volume $volume_name restored successfully"
    return 0
}

# Restore configuration files
restore_config_files() {
    local backup_path="$1"
    local force="${2:-false}"
    
    local config_archive="$backup_path/config.tar.gz"
    if [[ ! -f "$config_archive" ]]; then
        log_error "Config archive not found: $config_archive"
        return 1
    fi
    
    # Verify the config archive
    if [[ -f "$config_archive.sha256" ]]; then
        if ! verify_checksum "$config_archive"; then
            log_error "Checksum verification failed for $config_archive"
            if [[ "$force" != "true" ]]; then
                log_error "Use --force to restore anyway"
                return 1
            else
                log_warn "Proceeding with restore despite checksum failure (--force enabled)"
            fi
        fi
    else
        log_warn "No checksum file found for $config_archive, skipping verification"
    fi
    
    # Extract the config archive to a temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    log_info "Extracting configuration files to $temp_dir"
    
    if ! tar -xzf "$config_archive" -C "$temp_dir"; then
        log_error "Failed to extract config archive"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Check for conflicts
    local has_conflicts=false
    local config_files=(
        ".env"
        "gordon-mcp.yml"
        "compose.yaml"
        "Makefile"
        "run.sh"
    )
    
    for file in "${config_files[@]}"; do
        if [[ -f "$ROOT_DIR/$file" && -f "$temp_dir/config/$file" ]]; then
            if [[ "$force" != "true" ]]; then
                log_warn "Configuration file conflict: $file already exists"
                has_conflicts=true
            fi
        fi
    done
    
    if [[ "$has_conflicts" == "true" && "$force" != "true" ]]; then
        log_error "Configuration file conflicts detected"
        log_error "Use --force to overwrite existing files"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Copy configuration files
    log_info "Restoring configuration files"
    
    # Copy individual files
    for file in "${config_files[@]}"; do
        if [[ -f "$temp_dir/config/$file" ]]; then
            cp "$temp_dir/config/$file" "$ROOT_DIR/" || log_warn "Failed to restore $file"
        fi
    done
    
    # Copy directories
    local config_dirs=(
        "nginx"
        "prometheus"
        "grafana"
        "cron"
    )
    
    for dir in "${config_dirs[@]}"; do
        if [[ -d "$temp_dir/config/$dir" ]]; then
            # Ensure target directory exists
            mkdir -p "$ROOT_DIR/$dir"
            
            # Use cp -r for directories
            cp -r "$temp_dir/config/$dir"/* "$ROOT_DIR/$dir/" || log_warn "Failed to restore directory $dir"
        fi
    done
    
    # Clean up
    rm -rf "$temp_dir"
    
    log_info "✅ Configuration files restored successfully"
    return 0
}

# List all available backups
list_all_backups() {
    log_info "Listing all available backups"
    
    # Array to store all backup metadata
    local all_backups=()
    
    # Function to collect backups of a specific type
    collect_backups() {
        local backup_type="$1"
        local backup_dir
        
        case "$backup_type" in
            "$BACKUP_TYPE_FULL")
                backup_dir="$BACKUP_DIR/full"
                ;;
            "$BACKUP_TYPE_INCREMENTAL")
                backup_dir="$BACKUP_DIR/incremental"
                ;;
            "$BACKUP_TYPE_DIFFERENTIAL")
                backup_dir="$BACKUP_DIR/differential"
                ;;
            "$BACKUP_TYPE_SELECTIVE")
                backup_dir="$BACKUP_DIR/selective"
                ;;
            *)
                log_error "Unknown backup type: $backup_type"
                return 1
                ;;
        esac
        
        if [[ ! -d "$backup_dir" ]]; then
            return 0
        fi
        
        # Find directories with metadata files
        while IFS= read -r metadata_file; do
            if [[ -f "$metadata_file" ]]; then
                local backup_dir
                backup_dir=$(dirname "$metadata_file")
                local backup_id
                backup_id=$(basename "$backup_dir")
                
                # Read metadata
                local timestamp
                local verified
                
                if command -v jq &>/dev/null; then
                    timestamp=$(jq -r '.timestamp' "$metadata_file")
                    verified=$(jq -r '.verified' "$metadata_file")
                else
                    timestamp=$(grep -o '"timestamp": "[^"]*"' "$metadata_file" | cut -d '"' -f 4)
                    verified=$(grep -o '"verified": [^,}]*' "$metadata_file" | cut -d ':' -f 2 | tr -d ' ')
                fi
                
                # Calculate size
                local size
                size=$(calculate_backup_size "$backup_dir")
                
                # Add to array
                all_backups+=("$backup_type|$backup_id|$timestamp|$size|$verified")
            fi
        done < <(find "$backup_dir" -name "$METADATA_FILENAME" -type f)
    }
    
    # Collect backups of all types
    collect_backups "$BACKUP_TYPE_FULL"
    collect_backups "$BACKUP_TYPE_INCREMENTAL"
    collect_backups "$BACKUP_TYPE_DIFFERENTIAL"
    collect_backups "$BACKUP_TYPE_SELECTIVE"
    
    # Sort by timestamp (newest first)
    IFS=$'\n' all_backups=($(sort -t'|' -k3,3r <<<"${all_backups[*]}"))
    unset IFS
    
    # Print results as a table
    echo "--------------------------------------------------------------"
    echo "| Type          | ID             | Timestamp        | Size    | Verified |"
    echo "--------------------------------------------------------------"
    
    for backup in "${all_backups[@]}"; do
        IFS='|' read -r type id timestamp size verified <<< "$backup"
        
        # Format timestamp for display
        display_timestamp=$(date -d "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp")
        
        # Format verification status
        if [[ "$verified" == "true" ]]; then
            verified_status="✓"
        else
            verified_status="✗"
        fi
        
        printf "| %-13s | %-14s | %-16s | %-7s | %-8s |\n" "$type" "$id" "$display_timestamp" "$size" "$verified_status"
    done
    
    echo "--------------------------------------------------------------"
    echo "Total backups: ${#all_backups[@]}"
    
    return 0
}

# Get details of a specific backup
get_backup_details() {
    local backup_id="$1"
    
    log_info "Getting details for backup: $backup_id"
    
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
    
    local metadata_file="$backup_path/$METADATA_FILENAME"
    if [[ ! -f "$metadata_file" ]]; then
        log_error "Metadata file not found: $metadata_file"
        return 1
    }
