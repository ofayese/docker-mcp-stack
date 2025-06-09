#!/bin/bash
# Docker MCP Stack - Backup Script
# This script creates a backup of all data in the Docker MCP Stack

# Enable strict mode for better error handling
set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
BACKUP_DIR="backups"
TEMP_DIR=""
BACKUP_FILE=""

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        echo -e "${BLUE}Cleaning up temporary directory: $TEMP_DIR${NC}"
        rm -rf "$TEMP_DIR"
    fi
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}Backup failed with exit code $exit_code${NC}" >&2
        if [[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]]; then
            echo -e "${YELLOW}Removing incomplete backup file: $BACKUP_FILE${NC}"
            rm -f "$BACKUP_FILE"
        fi
    fi
    exit $exit_code
}

# Set up trap for cleanup
trap cleanup EXIT

# Validate environment
validate_environment() {
    # Check if we're in the right directory
    if [[ ! -f "compose.yaml" ]]; then
        echo -e "${RED}Error: compose.yaml not found. Please run this script from the project root directory.${NC}" >&2
        exit 1
    fi
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not installed or not in PATH.${NC}" >&2
        exit 1
    fi
    
    # Check if required tools are available
    for tool in tar mktemp; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo -e "${RED}Error: Required tool '$tool' is not available.${NC}" >&2
            exit 1
        fi
    done
}

# Load environment variables safely
load_environment() {
    if [[ -f .env ]]; then
        # shellcheck source=/dev/null
        set -a
        source .env
        set +a
        echo -e "${BLUE}Environment variables loaded from .env${NC}"
    else
        echo -e "${YELLOW}Warning: .env file not found. Using default values.${NC}"
    fi
}

# Create backup directory if it doesn't exist
initialize_backup_dir() {
    if ! mkdir -p "$BACKUP_DIR"; then
        echo -e "${RED}Error: Failed to create backup directory: $BACKUP_DIR${NC}" >&2
        exit 1
    fi
    
    # Check if backup directory is writable
    if [[ ! -w "$BACKUP_DIR" ]]; then
        echo -e "${RED}Error: Backup directory is not writable: $BACKUP_DIR${NC}" >&2
        exit 1
    fi
}

# Initialize backup process
initialize_backup() {
    validate_environment
    load_environment
    initialize_backup_dir
    
    # Get current date and time for backup filename
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="$BACKUP_DIR/mcp_backup_$timestamp.tar.gz"
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not running. Please start Docker and try again.${NC}" >&2
        exit 1
    fi
    
    # Create temporary directory for backup
    TEMP_DIR=$(mktemp -d)
    if [[ ! -d "$TEMP_DIR" ]]; then
        echo -e "${RED}Error: Failed to create temporary directory.${NC}" >&2
        exit 1
    fi
    
    echo -e "${BLUE}Temporary backup directory: $TEMP_DIR${NC}"
}

# Number of backups to keep (with validation)
get_backup_retention() {
    local backup_keep="${BACKUP_KEEP:-5}"
    
    # Validate backup retention value
    if ! [[ "$backup_keep" =~ ^[0-9]+$ ]] || [[ "$backup_keep" -lt 1 ]]; then
        echo -e "${YELLOW}Warning: Invalid BACKUP_KEEP value '$backup_keep'. Using default value 5.${NC}"
        backup_keep=5
    fi
    
    echo "$backup_keep"
}

# Back up .env and configuration files
echo -e "${BLUE}Backing up configuration files...${NC}"
mkdir -p "$TEMP_DIR/config"
cp -r .env gordon-mcp.yml compose.yaml Makefile run.sh "$TEMP_DIR/config/" 2>/dev/null || true
cp -r nginx "$TEMP_DIR/config/" 2>/dev/null || true
cp -r prometheus "$TEMP_DIR/config/" 2>/dev/null || true
cp -r grafana "$TEMP_DIR/config/" 2>/dev/null || true

# Back up volumes
echo -e "${BLUE}Backing up volumes...${NC}"

# Function to backup a Docker volume with enhanced error checking
backup_volume() {
    local volume_name="$1"
    local backup_path="$2"
    
    # Input validation
    if [[ -z "$volume_name" ]]; then
        echo -e "${RED}Error: Volume name cannot be empty${NC}" >&2
        return 1
    fi
    
    if [[ -z "$backup_path" ]]; then
        echo -e "${RED}Error: Backup path cannot be empty${NC}" >&2
        return 1
    fi
    
    # Validate volume name format
    if [[ ! "$volume_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Error: Invalid volume name format: $volume_name${NC}" >&2
        return 1
    fi
    
    if docker volume inspect "$volume_name" > /dev/null 2>&1; then
        echo -e "  Backing up volume: ${YELLOW}$volume_name${NC}"
        
        if ! mkdir -p "$backup_path"; then
            echo -e "${RED}Error: Failed to create backup path: $backup_path${NC}" >&2
            return 1
        fi
        
        # Use a more secure backup approach with explicit error checking
        if ! docker run --rm \
            -v "$volume_name":/source:ro \
            -v "$(pwd)/$backup_path":/backup \
            --user "$(id -u):$(id -g)" \
            alpine:latest \
            sh -c "cd /source && tar -czf /backup/$volume_name.tar.gz . 2>/dev/null"; then
            echo -e "${RED}Error: Failed to backup volume $volume_name${NC}" >&2
            return 1
        fi
        
        echo -e "  ${GREEN}✓${NC} Volume $volume_name backed up successfully"
    else
        echo -e "  ${YELLOW}Volume $volume_name does not exist, skipping...${NC}"
    fi
    
    return 0
}

# Main backup execution function
perform_backup() {
    echo -e "${BLUE}Starting backup of Docker MCP Stack...${NC}"
    
    # Initialize backup process
    initialize_backup
    
    # Back up configuration files
    echo -e "${BLUE}Backing up configuration files...${NC}"
    local config_dir="$TEMP_DIR/config"
    if ! mkdir -p "$config_dir"; then
        echo -e "${RED}Error: Failed to create config backup directory${NC}" >&2
        exit 1
    fi
    
    # List of configuration files to backup
    local config_files=(
        ".env"
        "gordon-mcp.yml"
        "compose.yaml"
        "Makefile"
        "run.sh"
        "backup.sh"
        "restore.sh"
    )
    
    # Backup individual config files
    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            cp "$file" "$config_dir/" 2>/dev/null || {
                echo -e "${YELLOW}Warning: Failed to backup $file${NC}"
            }
        fi
    done
    
    # Backup configuration directories
    local config_dirs=("nginx" "prometheus" "grafana" "scripts")
    for dir in "${config_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            cp -r "$dir" "$config_dir/" 2>/dev/null || {
                echo -e "${YELLOW}Warning: Failed to backup directory $dir${NC}"
            }
        fi
    done
    
    # Back up volumes
    echo -e "${BLUE}Backing up volumes...${NC}"
    
    # Define volumes to backup
    local volumes=(
        "mcp_model_cache"
        "mcp_postgres_data"
        "mcp_fs_data"
        "mcp_git_data"
        "mcp_sqlite_data"
        "mcp_prometheus_data"
        "mcp_grafana_data"
        "gordon_git_workspace"
        "gordon_sqlite_data"
    )
    
    # Backup each volume
    local failed_volumes=()
    for volume in "${volumes[@]}"; do
        if ! backup_volume "$volume" "$TEMP_DIR/volumes"; then
            failed_volumes+=("$volume")
        fi
    done
    
    # Report any failed volume backups
    if [[ ${#failed_volumes[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Warning: Failed to backup the following volumes:${NC}"
        printf '  %s\n' "${failed_volumes[@]}"
    fi
    
    # Create final backup archive
    echo -e "${BLUE}Creating final backup archive...${NC}"
    if ! tar -czf "$BACKUP_FILE" -C "$TEMP_DIR" .; then
        echo -e "${RED}Error: Failed to create backup archive${NC}" >&2
        exit 1
    fi
    
    # Verify backup file was created and has content
    if [[ ! -f "$BACKUP_FILE" ]] || [[ ! -s "$BACKUP_FILE" ]]; then
        echo -e "${RED}Error: Backup file is empty or was not created${NC}" >&2
        exit 1
    fi
    
    local backup_size
    backup_size=$(du -h "$BACKUP_FILE" | cut -f1)
    echo -e "${GREEN}Backup created successfully: $BACKUP_FILE (${backup_size})${NC}"
    
    # Clean up old backups
    cleanup_old_backups
    
    echo -e "${GREEN}Backup process completed successfully!${NC}"
}

# Clean up old backups with enhanced error handling
cleanup_old_backups() {
    echo -e "${BLUE}Cleaning up old backups...${NC}"
    
    local backup_keep
    backup_keep=$(get_backup_retention)
    
    # Get list of backup files sorted by modification time (newest first)
    local backup_files
    mapfile -t backup_files < <(find "$BACKUP_DIR" -name "mcp_backup_*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)
    
    # Remove old backups if we have more than the retention limit
    if [[ ${#backup_files[@]} -gt $backup_keep ]]; then
        echo -e "${BLUE}Removing old backups (keeping $backup_keep most recent)...${NC}"
        for ((i=backup_keep; i<${#backup_files[@]}; i++)); do
            local old_backup="${backup_files[$i]}"
            if rm -f "$old_backup"; then
                echo -e "  ${YELLOW}Removed: $(basename "$old_backup")${NC}"
            else
                echo -e "  ${RED}Failed to remove: $(basename "$old_backup")${NC}"
            fi
        done
    fi
    
    # List current backups
    echo -e "${BLUE}Current backups in $BACKUP_DIR:${NC}"
    if [[ ${#backup_files[@]} -gt 0 ]]; then
        for backup_file in "${backup_files[@]}"; do
            if [[ -f "$backup_file" ]]; then
                local size
                size=$(du -h "$backup_file" | cut -f1)
                local date
                date=$(stat -c %y "$backup_file" | cut -d' ' -f1)
                echo -e "  $(basename "$backup_file") - $size - $date"
            fi
        done
    else
        echo -e "  ${YELLOW}No backup files found${NC}"
    fi
}

# Main execution
main() {
    perform_backup
}

# Execute main function
main "$@"
