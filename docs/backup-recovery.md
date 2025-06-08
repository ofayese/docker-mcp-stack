# Docker MCP Stack Backup & Recovery System

This document describes the backup and recovery system for the Docker MCP Stack.

## Overview

The backup and recovery system provides robust capabilities for maintaining and restoring data from your
Docker MCP Stack. It includes:

- **Full backups**: Complete backups of all Docker volumes and configuration files
- **Incremental backups**: Efficient backups that only store changes since the last full backup
- **Automated scheduling**: Configurable backup schedules using cron
- **Health monitoring**: Tools to verify backup integrity and monitor backup health
- **Flexible restoration**: Restore entire backups or specific components

## Directory Structure

```bash
docker-mcp-stack/
├── backups/                # Root backup storage directory
│   ├── full/               # Full backup storage
│   ├── incremental/        # Incremental backup storage
│   ├── differential/       # Differential backup storage (for future use)
│   └── logs/               # Backup and restore logs
├── scripts/
│   ├── backup/             # Backup scripts
│   │   ├── full-backup.sh  # Full backup script
│   │   └── incremental-backup.sh  # Incremental backup script
│   ├── restore/            # Restore scripts
│   │   └── restore-backup.sh  # Restore script
│   ├── utils/              # Utility scripts
│   │   └── backup-recovery.sh  # Backup & recovery utility library
│   └── backup-recovery-manager.sh  # Main backup & recovery manager
└── cron/
    └── backup-cron         # Cron configuration for scheduled backups
```bash

## Getting Started

### Configuration

Backup and recovery configuration options can be set in your `.env` file:

```bash
# Backup directory
BACKUP_DIR="/path/to/backups"

# Backup retention period in days
BACKUP_RETENTION_DAYS=30

# Backup compression level (1-9)
BACKUP_COMPRESSION_LEVEL=6

# Enable backup verification
BACKUP_ENABLE_VERIFICATION=true

# Maximum parallel backup operations
BACKUP_MAX_PARALLEL_OPERATIONS=2
```bash

To create a template configuration file:

```bash
bash scripts/backup-recovery-manager.sh create-env-template
```bash

## Usage

### Creating Backups

#### Full Backup

To create a full backup of all Docker MCP Stack data:

```bash
bash scripts/backup-recovery-manager.sh full-backup
```bash

Options:

- `--id <backup_id>`: Specify a custom backup ID
- `--no-verify`: Skip backup verification

#### Incremental Backup

To create an incremental backup (changes since the last full backup):

```bash
bash scripts/backup-recovery-manager.sh incremental-backup
```bash

Options:

- `--id <backup_id>`: Specify a custom backup ID
- `--parent <backup_id>`: Specify a parent backup ID
- `--no-verify`: Skip backup verification

### Listing Backups

To list all available backups:

```bash
bash scripts/backup-recovery-manager.sh list
```bash

### Restoring Backups

To restore a backup:

```bash
bash scripts/backup-recovery-manager.sh restore <backup_id>
```bash

Options:

- `--components <component_list>`: Comma-separated list of components to restore
  - Use `all` for everything (default)
  - Use `config` for configuration files only
  - Use `volume:<name>` for specific volumes
- `--force`: Force restore, overwriting existing data

Examples:

```bash
# Restore everything
bash scripts/backup-recovery-manager.sh restore backup_20250601_120000_abcdef

# Restore only configuration files
bash scripts/backup-recovery-manager.sh restore backup_20250601_120000_abcdef --components config

# Restore specific volumes
bash scripts/backup-recovery-manager.sh restore backup_20250601_120000_abcdef \
  --components volume:mcp_data,volume:gordon_models

# Force restore, overwriting existing data
bash scripts/backup-recovery-manager.sh restore backup_20250601_120000_abcdef --force
```bash

### Scheduling Backups

To schedule automatic backups:

```bash
bash scripts/backup-recovery-manager.sh schedule "0 2 * * 0" "0 2 * * 1-6"
```bash

This creates a cron configuration file that you can install with:

```bash
crontab /path/to/docker-mcp-stack/cron/backup-cron
```bash

By default:

- Full backups run every Sunday at 2 AM
- Incremental backups run Monday-Saturday at 2 AM

### Checking Backup Health

To verify the health of your backups:

```bash
bash scripts/backup-recovery-manager.sh health-check
```bash

Options:

- `<days>`: Number of days to check (default: 7)

## Backup Metadata

Each backup includes a metadata file (`backup-metadata.json`) with information about the backup:

```json
{
  "timestamp": "20250601_120000",
  "type": "full",
  "parent": "",
  "components": [],
  "hostname": "docker-host",
  "docker_version": "Docker version 25.0.3",
  "compression_level": "6",
  "encrypted": false,
  "verified": true
}
```bash

## Backup Verification

All backups include SHA-256 checksums for volume data and configuration files. The verification process ensures:

1. All checksums match their corresponding files
2. All required components are present
3. Incremental backups have valid parent backups

## Backup Types

### Full Backup

A complete backup of all Docker volumes and configuration files. This is the most comprehensive backup type.

### Incremental Backup

A backup of only the changes since the last full backup. This is more efficient for frequent backups.

### Differential Backup (Future)

A backup of all changes since the last full backup. Unlike incremental backups, differential backups
don't depend on previous differential backups.

## Best Practices

1. **Regular Full Backups**: Perform full backups at least weekly
2. **Daily Incremental Backups**: Use incremental backups for daily operations
3. **Verification**: Always verify backups unless performance is a concern
4. **External Storage**: Store backups on external storage or a different server
5. **Retention Policy**: Configure appropriate retention periods based on your needs
6. **Testing**: Regularly test restoration to ensure backups are valid

## Troubleshooting

### Common Issues

1. **Insufficient Disk Space**: Ensure adequate disk space for backups
2. **Permission Issues**: Check file and directory permissions
3. **Docker Volume Access**: Ensure the backup process has access to Docker volumes
4. **Missing Dependencies**: Check for required tools (tar, gzip, etc.)

### Logs

Backup and restore logs are stored in the `backups/logs/` directory.

## Advanced Topics

### Manual Backup Verification

To manually verify a backup:

```bash
# Load utility functions
source scripts/utils/backup-recovery.sh

# Verify a specific backup
verify_backup "/path/to/backup/full/backup_20250601_120000_abcdef"
```bash

### Custom Backup Paths

To use a custom backup directory:

```bash
# In .env file
BACKUP_DIR="/custom/backup/path"

# Or specify at runtime
BACKUP_DIR="/custom/backup/path" bash scripts/backup-recovery-manager.sh full-backup
```bash
