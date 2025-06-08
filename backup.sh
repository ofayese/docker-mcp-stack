#!/bin/bash
# Docker MCP Stack - Backup Script
# This script creates a backup of all data in the Docker MCP Stack

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create backup directory if it doesn't exist
BACKUP_DIR="backups"
mkdir -p "$BACKUP_DIR"

# Get current date and time for backup filename
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/mcp_backup_$TIMESTAMP.tar.gz"

# Load environment variables
if [ -f .env ]; then
    source .env
fi

# Number of backups to keep
BACKUP_KEEP=${BACKUP_KEEP:-5}

echo -e "${BLUE}Starting backup of Docker MCP Stack...${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi

# Create temporary directory for backup
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Back up .env and configuration files
echo -e "${BLUE}Backing up configuration files...${NC}"
mkdir -p "$TEMP_DIR/config"
cp -r .env gordon-mcp.yml compose.yaml Makefile run.sh "$TEMP_DIR/config/" 2>/dev/null || true
cp -r nginx "$TEMP_DIR/config/" 2>/dev/null || true
cp -r prometheus "$TEMP_DIR/config/" 2>/dev/null || true
cp -r grafana "$TEMP_DIR/config/" 2>/dev/null || true

# Back up volumes
echo -e "${BLUE}Backing up volumes...${NC}"

# Function to backup a Docker volume
backup_volume() {
    local VOLUME_NAME=$1
    local BACKUP_PATH=$2
    
    if docker volume inspect "$VOLUME_NAME" > /dev/null 2>&1; then
        echo -e "  Backing up volume: ${YELLOW}$VOLUME_NAME${NC}"
        mkdir -p "$BACKUP_PATH"
        docker run --rm -v "$VOLUME_NAME":/source -v "$(pwd)/$BACKUP_PATH":/backup alpine sh -c "cd /source && tar -czf /backup/$VOLUME_NAME.tar.gz ."
    else
        echo -e "  ${YELLOW}Volume $VOLUME_NAME does not exist, skipping...${NC}"
    fi
}

# Back up model cache
backup_volume "mcp_model_cache" "$TEMP_DIR/volumes"

# Back up database data
backup_volume "mcp_postgres_data" "$TEMP_DIR/volumes"

# Back up filesystem data
backup_volume "mcp_fs_data" "$TEMP_DIR/volumes"

# Back up git data
backup_volume "mcp_git_data" "$TEMP_DIR/volumes"

# Back up sqlite data
backup_volume "mcp_sqlite_data" "$TEMP_DIR/volumes"

# Back up monitoring data
backup_volume "mcp_prometheus_data" "$TEMP_DIR/volumes"
backup_volume "mcp_grafana_data" "$TEMP_DIR/volumes"

# Back up Gordon data
backup_volume "gordon_git_workspace" "$TEMP_DIR/volumes"
backup_volume "gordon_sqlite_data" "$TEMP_DIR/volumes"

# Create final backup archive
echo -e "${BLUE}Creating final backup archive...${NC}"
tar -czf "$BACKUP_FILE" -C "$TEMP_DIR" .

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Backup created successfully: $BACKUP_FILE${NC}"
    
    # Clean up old backups
    echo -e "${BLUE}Cleaning up old backups...${NC}"
    ls -t "$BACKUP_DIR"/mcp_backup_*.tar.gz 2>/dev/null | tail -n +$((BACKUP_KEEP + 1)) | xargs rm -f 2>/dev/null || true
    
    echo -e "${BLUE}Backups in $BACKUP_DIR:${NC}"
    ls -lh "$BACKUP_DIR"/mcp_backup_*.tar.gz 2>/dev/null | awk '{print "  " $9 " - " $5}'
else
    echo -e "${RED}Error: Backup failed.${NC}"
    exit 1
fi

# Clean up temporary directory
rm -rf "$TEMP_DIR"

echo -e "${GREEN}Backup process completed!${NC}"
exit 0
