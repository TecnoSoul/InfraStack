# Migration Guide: RadioStack to InfraStack

This guide helps you migrate from the standalone RadioStack project to the InfraStack Radio Module.

## Overview

RadioStack has been integrated into InfraStack as a specialized radio module. All functionality has been preserved - your existing stations will continue to work without changes. Only the command interface has been updated.

## What Changed

### Command Structure

The main change is the command prefix. RadioStack commands are now accessed through the `infrastack radio` category:

| RadioStack (Old) | InfraStack (New) |
|------------------|------------------|
| `radiostack deploy azuracast` | `infrastack radio deploy azuracast` |
| `radiostack status` | `infrastack radio status` |
| `radiostack update 340` | `infrastack radio update --ctid 340` |
| `radiostack backup 340` | `infrastack radio backup --ctid 340` |
| `radiostack remove 340` | `infrastack radio remove --ctid 340` |
| `radiostack logs 340` | `infrastack radio logs --ctid 340` |
| `radiostack info 340` | `infrastack radio info --ctid 340` |

### Directory Structure

```
RadioStack (Standalone)          InfraStack (Integrated)
=======================          =======================
radiostack.sh                    infrastack.sh (with radio category)
scripts/platforms/               scripts/radio/platforms/
scripts/tools/                   scripts/radio/tools/
scripts/lib/                     scripts/lib/ (merged libraries)
docs/                            docs/radio/
```

### Configuration

- **Old**: `/etc/radiostack/radiostack.conf`
- **New**: `/etc/infrastack/infrastack.conf`

Configuration variables remain the same, just in a different file:

```bash
# AzuraCast defaults
DEFAULT_AZURACAST_CORES=4
DEFAULT_AZURACAST_MEMORY=4092
DEFAULT_AZURACAST_QUOTA="50G"

# LibreTime defaults
DEFAULT_LIBRETIME_CORES=2
DEFAULT_LIBRETIME_MEMORY=4092
DEFAULT_LIBRETIME_QUOTA="30G"

# Network
DEFAULT_AZURACAST_NETWORK="192.168.2"
DEFAULT_LIBRETIME_NETWORK="192.168.2"
```

### Inventory

- **Old**: `/etc/radiostack/inventory/stations.csv`
- **New**: `/etc/infrastack/inventory/stations.csv`

The format remains identical:
```csv
CTID,Type,Hostname,IP,Description,Created,Status
340,azuracast,azuracast-main,192.168.2.140,"Main station",2025-01-20,active
```

## Migration Steps

### Step 1: Install InfraStack

```bash
cd /opt
git clone https://github.com/TecnoSoul/InfraStack.git
cd InfraStack
```

### Step 2: Migrate Configuration (Optional)

If you had custom configuration:

```bash
# Copy configuration
sudo mkdir -p /etc/infrastack
sudo cp /etc/radiostack/radiostack.conf /etc/infrastack/infrastack.conf

# Migrate inventory
sudo mkdir -p /etc/infrastack/inventory
sudo cp /etc/radiostack/inventory/stations.csv /etc/infrastack/inventory/stations.csv
```

### Step 3: Update Scripts and Aliases

If you have scripts or cron jobs using RadioStack commands, update them:

```bash
# Old script
#!/bin/bash
radiostack backup --all
radiostack status

# New script
#!/bin/bash
infrastack radio backup --all
infrastack radio status
```

### Step 4: Verify Everything Works

```bash
# Check status of existing stations
infrastack radio status

# Verify a specific station
infrastack radio info --ctid 340

# View logs
infrastack radio logs --ctid 340
```

## Existing Stations

**Your existing stations are not affected.** The containers, ZFS datasets, and all data remain exactly where they are. Only the management commands have changed.

### Container Changes: None

- Containers continue running
- Docker services unchanged
- Network configuration unchanged
- Storage mounts unchanged

### What You Need to Do

1. Update any automation scripts to use the new command format
2. Update cron jobs if you have automated backups
3. Optionally migrate configuration files for consistency

## Direct Script Execution

You can still execute scripts directly without going through the CLI:

```bash
# Deploy AzuraCast directly
./scripts/radio/platforms/azuracast.sh -i 340 -n my-station

# Check status directly
./scripts/radio/tools/status.sh --all

# These work the same as:
infrastack radio deploy azuracast -i 340 -n my-station
infrastack radio status --all
```

## Rollback

If you need to continue using RadioStack temporarily:

1. Your RadioStack installation is still in place
2. Simply use the old commands
3. Both can coexist - they manage the same containers

However, we recommend completing the migration as RadioStack will not receive further updates.

## New Features in InfraStack

While the radio functionality is preserved, InfraStack also provides:

- **Setup tools**: Base package installation, Zsh setup
- **PHP tools**: Xdebug management, profiling
- **Health monitoring**: Server health checks
- **Unified CLI**: All sysadmin tools in one place

## Troubleshooting

### Command Not Found

Ensure InfraStack is in your PATH:

```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="/opt/infrastack:$PATH"

# Or create symlink
sudo ln -s /opt/infrastack/infrastack.sh /usr/local/bin/infrastack
```

### Permission Denied

Radio commands require root:

```bash
sudo infrastack radio status
```

### Inventory Not Found

If stations don't appear in status:

```bash
# Check inventory file location
cat /etc/infrastack/inventory/stations.csv

# If empty, containers still exist but aren't tracked
# Manually add them or run status with pct list
pct list | grep -E "azuracast|libretime"
```

### Old Configuration Being Used

Ensure you're not loading the old config:

```bash
# Check which config is loaded
infrastack version
# Should show: InfraStack v2.0.0

# Verify config path
echo $INFRASTACK_CONFIG
# Should be: /etc/infrastack/infrastack.conf
```

## Getting Help

- **Documentation**: `/opt/infrastack/docs/radio/`
- **Quick Reference**: `/opt/infrastack/docs/radio/quick-reference.md`
- **GitHub Issues**: https://github.com/TecnoSoul/InfraStack/issues

## Summary

| Aspect | Before | After |
|--------|--------|-------|
| Command prefix | `radiostack` | `infrastack radio` |
| Config location | `/etc/radiostack/` | `/etc/infrastack/` |
| Script location | `scripts/platforms/` | `scripts/radio/platforms/` |
| Documentation | `docs/` | `docs/radio/` |
| Containers | Unchanged | Unchanged |
| Data | Unchanged | Unchanged |
| ZFS datasets | Unchanged | Unchanged |

The migration is primarily a command-line interface change. Your infrastructure and data remain exactly as they were.
