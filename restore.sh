#!/bin/bash
# Docker MCP Stack - Restore Script
# This script restores data from a backup created by backup.sh

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if a backup file is provided
if [ $# -ne 1 ]; then
    echo -e "${RED}Error: No backup file specified.${NC}"
    echo -e "Usage: $0 <backup_file>"
    echo -e "Example: $0 backups/mcp_backup_20250608_123456.tar.gz"
    exit 1
fi

BACKUP_FILE=$1

# Check if the backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}Error: Backup file '$BACKUP_FILE' not found.${NC}"
    exit 1
fi

echo -e "${BLUE}Starting restoration of Docker MCP Stack from backup: $BACKUP_FILE${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi

# Create temporary directory for extraction
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Extract the backup archive
echo -e "${BLUE}Extracting backup archive...${NC}"
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to extract backup archive.${NC}"
    exit 1
fi

# Check if the extracted backup has the expected structure
if [ ! -d "$TEMP_DIR/config" ] || [ ! -d "$TEMP_DIR/volumes" ]; then
    echo -e "${RED}Error: Invalid backup archive structure.${NC}"
    exit 1
fi

# Stop all services before restoration
echo -e "${BLUE}Stopping all services...${NC}"
docker compose down
docker compose -f gordon-mcp.yml down

# Restore configuration files
echo -e "${BLUE}Restoring configuration files...${NC}"
if [ -d "$TEMP_DIR/config" ]; then
    # Copy config files but don't overwrite unless user confirms
    if [ -f .env ] || [ -f compose.yaml ] || [ -f gordon-mcp.yml ]; then
        echo -e "${YELLOW}Warning: Some configuration files already exist.${NC}"
        read -p "Do you want to overwrite existing configuration files? [y/N] " -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp -r "$TEMP_DIR/config/"* .
            echo -e "${GREEN}Configuration files restored.${NC}"
        else
            echo -e "${YELLOW}Skipping configuration files restoration.${NC}"
        fi
    else
        # No conflict, safe to copy
        cp -r "$TEMP_DIR/config/"* .
        echo -e "${GREEN}Configuration files restored.${NC}"
    fi
fi

# Function to restore a Docker volume
restore_volume() {
    local VOLUME_NAME=$1
    local BACKUP_FILE="$TEMP_DIR/volumes/$VOLUME_NAME.tar.gz"
    
    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "  ${YELLOW}Backup for volume $VOLUME_NAME not found, skipping...${NC}"
        return
    fi
    
    echo -e "  Restoring volume: ${YELLOW}$VOLUME_NAME${NC}"
    
    # Create volume if it doesn't exist
    if ! docker volume inspect "$VOLUME_NAME" > /dev/null 2>&1; then
        docker volume create "$VOLUME_NAME"
    else
        # Ask for confirmation before overwriting existing volume
        read -p "  Volume $VOLUME_NAME already exists. Overwrite? [y/N] " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "  ${YELLOW}Skipping restoration of volume $VOLUME_NAME.${NC}"
            return
        fi
    fi
    
    # Restore volume data
    docker run --rm -v "$VOLUME_NAME":/dest -v "$(pwd)/$TEMP_DIR/volumes":/backup alpine sh -c "rm -rf /dest/* /dest/.[!.]* 2>/dev/null || true && cd /dest && tar -xzf /backup/$VOLUME_NAME.tar.gz"
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}Volume $VOLUME_NAME restored successfully.${NC}"
    else
        echo -e "  ${RED}Failed to restore volume $VOLUME_NAME.${NC}"
    fi
}

# Restore volumes
echo -e "${BLUE}Restoring volumes...${NC}"

# Restore model cache
restore_volume "mcp_model_cache"

# Restore database data
restore_volume "mcp_postgres_data"

# Restore filesystem data
restore_volume "mcp_fs_data"

# Restore git data
restore_volume "mcp_git_data"

# Restore sqlite data
restore_volume "mcp_sqlite_data"

# Restore monitoring data
restore_volume "mcp_prometheus_data"
restore_volume "mcp_grafana_data"

# Restore Gordon data
restore_volume "gordon_git_workspace"
restore_volume "gordon_sqlite_data"

echo -e "${BLUE}Restore process completed.${NC}"
echo -e "${GREEN}You can now start the services again with:${NC}"
echo -e "  ./run.sh start"
echo -e "  or"
echo -e "  make start"

# Clean up temporary directory
rm -rf "$TEMP_DIR"

exit 0
