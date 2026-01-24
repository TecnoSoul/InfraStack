# InfraStack Radio Module

Radio platform deployment and management for Proxmox VE environments.

**Formerly RadioStack** - This module was integrated from the standalone RadioStack project during the InfraStack consolidation. All RadioStack functionality is preserved and enhanced.

## Overview

The Radio Module provides automated deployment, management, and monitoring of radio streaming platforms in LXC containers with ZFS storage optimization.

### Supported Platforms

- **AzuraCast** - Full-featured radio automation platform
- **LibreTime** - Open source radio automation (formerly Airtime)
- **Icecast** - Standalone streaming server (planned)

### Features

- Automated LXC container creation with optimal settings
- ZFS dataset management for media storage
- Docker-based platform installation
- HDD storage optimization for media files
- Inventory tracking (CSV-based)
- Bulk operations (update, backup, status)
- Platform-specific management tools

## Quick Start

### Deploy AzuraCast Station

```bash
# Via InfraStack CLI
infrastack radio deploy azuracast -i 340 -n main-station

# Direct execution
./scripts/radio/platforms/azuracast.sh -i 340 -n main-station
```

### Deploy LibreTime Station

```bash
# Via InfraStack CLI
infrastack radio deploy libretime -i 350 -n station1

# Direct execution
./scripts/radio/platforms/libretime.sh -i 350 -n station1
```

### Check Status

```bash
# All stations
infrastack radio status

# Specific platform
infrastack radio status --platform azuracast

# Specific container
infrastack radio status --ctid 340
```

## Directory Structure

```
scripts/radio/
├── platforms/
│   ├── azuracast.sh      # AzuraCast deployment
│   ├── libretime.sh      # LibreTime deployment
│   └── deploy.sh         # Platform dispatcher
├── tools/
│   ├── status.sh         # Status monitoring
│   ├── update.sh         # Platform updates
│   ├── backup.sh         # Backup operations
│   ├── remove.sh         # Container removal
│   ├── logs.sh           # Log viewer
│   └── info.sh           # Detailed information
└── README.md             # This file
```

## Commands Reference

### Deployment

```bash
infrastack radio deploy <platform> [options]

Platforms: azuracast, libretime

Options:
  -i, --ctid ID         Container ID (required)
  -n, --name NAME       Station name (required)
  -c, --cores NUM       CPU cores
  -m, --memory MB       Memory in MB
  -q, --quota SIZE      Storage quota (e.g., 500G)
  -p, --ip-suffix NUM   IP address suffix
```

### Status

```bash
infrastack radio status [options]

Options:
  -a, --all             Show all containers (default)
  -p, --platform TYPE   Filter by platform
  -i, --ctid ID         Show specific container
```

### Update

```bash
infrastack radio update [options]

Options:
  -i, --ctid ID         Update specific container
  -p, --platform TYPE   Update all of platform type
  -a, --all             Update all containers
```

### Backup

```bash
infrastack radio backup [options]

Options:
  -i, --ctid ID         Backup specific container
  -a, --all             Backup all containers
  -t, --type TYPE       Backup type: container/application/full
  -l, --list            List available backups
```

### Remove

```bash
infrastack radio remove [options]

Options:
  -i, --ctid ID         Container to remove (required)
  -d, --data            Also remove ZFS dataset
  --purge-all           Remove all containers (dangerous)
```

### Logs

```bash
infrastack radio logs [options]

Options:
  -i, --ctid ID         Container ID (required)
  -t, --type TYPE       Log type: container/application/both
  -n, --lines NUM       Number of lines (default: 50)
  -f, --follow          Follow logs in real-time
  -s, --service NAME    Specific service logs
```

### Info

```bash
infrastack radio info [options]

Options:
  -i, --ctid ID         Show container details
  -s, --summary         Show system summary (default)
```

## Configuration

Default values can be customized in `/etc/infrastack/infrastack.conf`:

```bash
# AzuraCast defaults
DEFAULT_AZURACAST_CORES=4
DEFAULT_AZURACAST_MEMORY=4092
DEFAULT_AZURACAST_QUOTA="50G"

# LibreTime defaults
DEFAULT_LIBRETIME_CORES=2
DEFAULT_LIBRETIME_MEMORY=4092
DEFAULT_LIBRETIME_QUOTA="30G"
DEFAULT_LIBRETIME_VERSION="4.5.0"

# Network
DEFAULT_AZURACAST_NETWORK="192.168.2"
DEFAULT_LIBRETIME_NETWORK="192.168.2"

# Backup
DEFAULT_BACKUP_STORAGE="hdd-backups"
DEFAULT_BACKUP_MODE="snapshot"
DEFAULT_BACKUP_COMPRESS="zstd"
```

## Inventory System

Stations are tracked in `/etc/infrastack/inventory/stations.csv`:

```csv
CTID,Type,Hostname,IP,Description,Created,Status
340,azuracast,azuracast-main,192.168.2.140,"Main station",2025-01-20,active
350,libretime,libretime-station1,192.168.2.150,"Station 1",2025-01-21,active
```

### Inventory Commands

```bash
# List all stations
infrastack radio status

# Validate inventory
# (checks for orphaned entries, duplicates)
# Run from inventory.sh functions

# Cleanup orphaned entries
# Remove entries for containers that no longer exist
```

## Storage Architecture

The Radio Module uses a two-tier storage approach:

1. **Fast Storage (SSD/NVMe)** - Container root filesystem (32GB default)
2. **HDD Storage (ZFS)** - Media files with optimized settings

### ZFS Dataset Properties

```
compression=lz4
recordsize=128k
atime=off
quota=<configured>
```

### Mount Points

- AzuraCast: `/var/azuracast` (mp0)
- LibreTime: `/srv/libretime` (mp0)

## Migration from RadioStack

If you were using the standalone RadioStack:

1. Your stations continue to work - containers are unchanged
2. Update your scripts to use `infrastack radio` instead of `radiostack`
3. See [MIGRATION.md](../../MIGRATION.md) for detailed migration guide

### Command Mapping

| RadioStack | InfraStack |
|------------|------------|
| `radiostack deploy azuracast` | `infrastack radio deploy azuracast` |
| `radiostack status` | `infrastack radio status` |
| `radiostack update 340` | `infrastack radio update --ctid 340` |
| `radiostack backup 340` | `infrastack radio backup --ctid 340` |
| `radiostack remove 340` | `infrastack radio remove --ctid 340` |
| `radiostack logs 340` | `infrastack radio logs --ctid 340` |

## Troubleshooting

### Container won't start

```bash
# Check container status
pct status <ctid>

# View container config
pct config <ctid>

# Check logs
infrastack radio logs --ctid <ctid> --type container
```

### Storage issues

```bash
# Check ZFS dataset
zfs list | grep <station-name>

# Check mount point
pct config <ctid> | grep mp0

# Fix permissions
chown -R 100000:100000 /hdd-pool/container-data/<platform>-media/<station>
```

### Application not starting

```bash
# Enter container
pct enter <ctid>

# Check Docker status
docker ps -a
docker-compose logs
```

## Requirements

- Proxmox VE 7.x or 8.x
- ZFS storage pool (recommended: hdd-pool)
- Debian 12/13 container template
- Network bridge (vmbr1)

## Related Documentation

- [Getting Started](../../docs/radio/getting-started.md)
- [AzuraCast Guide](../../docs/radio/azuracast.md)
- [LibreTime Guide](../../docs/radio/libretime.md)
- [Storage Configuration](../../docs/radio/storage-configuration.md)
