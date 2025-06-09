#!/bin/bash
# Docker MCP Stack - Restore Script
# This script restores data from a backup created by backup.sh

# Enable strict mode for better error handling
set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
BACKUP_FILE=""
TEMP_DIR=""

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        echo -e "${BLUE}Cleaning up temporary directory: $TEMP_DIR${NC}"
        rm -rf "$TEMP_DIR"
    fi
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}Restore failed with exit code $exit_code${NC}" >&2
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
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not running. Please start Docker and try again.${NC}" >&2
        exit 1
    fi
}

# Validate and process input arguments
validate_input() {
    # Check if a backup file is provided
    if [[ $# -ne 1 ]]; then
        echo -e "${RED}Error: No backup file specified.${NC}" >&2
        echo -e "Usage: $0 <backup_file>" >&2
        echo -e "Example: $0 backups/mcp_backup_20250608_123456.tar.gz" >&2
        exit 1
    fi
    
    BACKUP_FILE="$1"
    
    # Validate backup file path
    if [[ -z "$BACKUP_FILE" ]]; then
        echo -e "${RED}Error: Backup file path cannot be empty.${NC}" >&2
        exit 1
    fi
    
    # Check if the backup file exists
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo -e "${RED}Error: Backup file '$BACKUP_FILE' not found.${NC}" >&2
        exit 1
    fi
    
    # Check if the backup file is readable
    if [[ ! -r "$BACKUP_FILE" ]]; then
        echo -e "${RED}Error: Backup file '$BACKUP_FILE' is not readable.${NC}" >&2
        exit 1
    fi
    
    # Validate backup file format
    if [[ ! "$BACKUP_FILE" =~ \.tar\.gz$ ]]; then
        echo -e "${YELLOW}Warning: Backup file doesn't have .tar.gz extension. Proceeding anyway...${NC}"
    fi
    
    echo -e "${BLUE}Backup file validated: $BACKUP_FILE${NC}"
# Extract and validate backup archive
extract_backup() {
    echo -e "${BLUE}Starting restoration of Docker MCP Stack from backup: $BACKUP_FILE${NC}"
    
    # Create temporary directory for extraction
    TEMP_DIR=$(mktemp -d)
    if [[ ! -d "$TEMP_DIR" ]]; then
        echo -e "${RED}Error: Failed to create temporary directory.${NC}" >&2
        exit 1
    fi
    
    echo -e "${BLUE}Temporary extraction directory: $TEMP_DIR${NC}"
    
    # Extract the backup archive with error checking
    echo -e "${BLUE}Extracting backup archive...${NC}"
    if ! tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"; then
        echo -e "${RED}Error: Failed to extract backup archive.${NC}" >&2
        exit 1
    fi
    
    # Validate backup structure
    if [[ ! -d "$TEMP_DIR/config" ]] || [[ ! -d "$TEMP_DIR/volumes" ]]; then
        echo -e "${RED}Error: Invalid backup archive structure. Missing config or volumes directory.${NC}" >&2
        exit 1
    fi
    
    echo -e "${GREEN}Backup archive extracted and validated successfully.${NC}"
}

# Stop services safely
stop_services() {
    echo -e "${BLUE}Stopping all services...${NC}"
    
    # Stop main stack
    if [[ -f "compose.yaml" ]]; then
        if ! docker compose down 2>/dev/null; then
            echo -e "${YELLOW}Warning: Failed to stop some services with compose.yaml${NC}"
        fi
    fi
    
    # Stop Gordon MCP stack if present
    if [[ -f "gordon-mcp.yml" ]]; then
        if ! docker compose -f gordon-mcp.yml down 2>/dev/null; then
            echo -e "${YELLOW}Warning: Failed to stop Gordon MCP services${NC}"
        fi
    fi
    
    echo -e "${GREEN}Services stopped.${NC}"
}

# Confirm overwrite for existing files
confirm_overwrite() {
    local message="$1"
    echo -e "${YELLOW}$message${NC}"
    
    while true; do
        read -p "Do you want to proceed? [y/N] " -r response
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo]|"")
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Restore configuration files safely
restore_configuration() {
    echo -e "${BLUE}Restoring configuration files...${NC}"
    
    if [[ ! -d "$TEMP_DIR/config" ]]; then
        echo -e "${YELLOW}No configuration files found in backup.${NC}"
        return 0
    fi
    
    # Check for existing configuration files
    local existing_files=()
    local config_files=(".env" "compose.yaml" "gordon-mcp.yml" "Makefile" "run.sh" "backup.sh" "restore.sh")
    
    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            existing_files+=("$file")
        fi
    done
    
    # Check for existing directories
    local config_dirs=("nginx" "prometheus" "grafana" "scripts")
    for dir in "${config_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            existing_files+=("$dir/")
        fi
    done
    
    if [[ ${#existing_files[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Warning: The following configuration files/directories already exist:${NC}"
        printf '  %s\n' "${existing_files[@]}"
        
        if ! confirm_overwrite "This will overwrite existing configuration files."; then
            echo -e "${YELLOW}Skipping configuration files restoration.${NC}"
            return 0
        fi
    fi
    
    # Perform the restoration
    if cp -r "$TEMP_DIR/config/"* .; then
        echo -e "${GREEN}Configuration files restored successfully.${NC}"
    else
        echo -e "${RED}Error: Failed to restore configuration files.${NC}" >&2
        return 1
    fi
}

# Function to restore a Docker volume with enhanced error checking
restore_volume() {
    local volume_name="$1"
    local backup_file="$TEMP_DIR/volumes/$volume_name.tar.gz"
    
    # Input validation
    if [[ -z "$volume_name" ]]; then
        echo -e "${RED}Error: Volume name cannot be empty${NC}" >&2
        return 1
    fi
    
    # Validate volume name format
    if [[ ! "$volume_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Error: Invalid volume name format: $volume_name${NC}" >&2
        return 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        echo -e "  ${YELLOW}Backup for volume $volume_name not found, skipping...${NC}"
        return 0
    fi
    
    echo -e "  Restoring volume: ${YELLOW}$volume_name${NC}"
    
    # Check if volume already exists
    if docker volume inspect "$volume_name" > /dev/null 2>&1; then
        if ! confirm_overwrite "Volume $volume_name already exists. This will overwrite all data in the volume."; then
            echo -e "  ${YELLOW}Skipping restoration of volume $volume_name.${NC}"
            return 0
        fi
    else
        # Create volume if it doesn't exist
        if ! docker volume create "$volume_name" > /dev/null 2>&1; then
            echo -e "  ${RED}Failed to create volume $volume_name${NC}" >&2
            return 1
        fi
    fi
    
    # Restore volume data with enhanced security
    if docker run --rm \
        -v "$volume_name":/dest \
        -v "$(pwd)/$TEMP_DIR/volumes":/backup:ro \
        --user "$(id -u):$(id -g)" 2>/dev/null || echo "0:0" \
        alpine:latest \
        sh -c "rm -rf /dest/* /dest/.[!.]* 2>/dev/null || true && cd /dest && tar -xzf /backup/$volume_name.tar.gz"; then
        echo -e "  ${GREEN}✓${NC} Volume $volume_name restored successfully"
    else
        echo -e "  ${RED}✗${NC} Failed to restore volume $volume_name" >&2
        return 1
    fi
    
    return 0
}

# Restore all volumes
restore_volumes() {
    echo -e "${BLUE}Restoring volumes...${NC}"
    
    # Define volumes to restore
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
    
    # Restore each volume
    local failed_volumes=()
    for volume in "${volumes[@]}"; do
        if ! restore_volume "$volume"; then
            failed_volumes+=("$volume")
        fi
    done
    
    # Report any failed volume restorations
    if [[ ${#failed_volumes[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Warning: Failed to restore the following volumes:${NC}"
        printf '  %s\n' "${failed_volumes[@]}"
        return 1
    fi
    
    echo -e "${GREEN}All volumes restored successfully.${NC}"
    return 0
}

# Main restoration process
perform_restore() {
    validate_environment
    validate_input "$@"
    
    # Confirm the restoration process
    echo -e "${YELLOW}This will restore data from: $BACKUP_FILE${NC}"
    echo -e "${YELLOW}This process will stop all running services and may overwrite existing data.${NC}"
    
    if ! confirm_overwrite "Are you sure you want to proceed with the restoration?"; then
        echo -e "${BLUE}Restoration cancelled by user.${NC}"
        exit 0
    fi
    
    extract_backup
    stop_services
    restore_configuration
    restore_volumes
    
    echo -e "${GREEN}Restore process completed successfully!${NC}"
    echo -e "${BLUE}You can now start the services again with:${NC}"
    echo -e "  ${GREEN}./run.sh start${NC}"
    echo -e "  ${GREEN}make start${NC}"
}

# Main execution
main() {
    perform_restore "$@"
}

# Execute main function with all arguments
main "$@"
