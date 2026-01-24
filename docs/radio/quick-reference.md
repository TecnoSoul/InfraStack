# InfraStack Radio Module - Quick Reference

Quick command reference for common radio module operations.

## Deployment Commands

### Deploy New Station

```bash
# AzuraCast - Basic deployment
sudo infrastack radio deploy azuracast -i 340 -n main-station

# AzuraCast - Custom resources
sudo infrastack radio deploy azuracast -i 341 -n big-station -c 8 -m 16384 -q 1T

# LibreTime - Basic deployment
sudo infrastack radio deploy libretime -i 201 -n station1

# LibreTime - Custom resources
sudo infrastack radio deploy libretime -i 202 -n fm-rock -c 4 -m 8192 -q 500G
```

### Access Station

**AzuraCast:**
- Web Interface: `http://192.168.2.{CTID}`
- Complete setup wizard on first access

**LibreTime:**
- Web Interface: `http://192.168.2.{CTID}:8080`
- Default Login: admin / admin (change immediately!)
- Icecast Stream: `http://192.168.2.{CTID}:8000/main`

## Status and Monitoring

```bash
# Check all stations
sudo infrastack radio status

# Check specific container
sudo infrastack radio status --ctid 340

# Check by platform
sudo infrastack radio status --platform azuracast

# Get detailed info
sudo infrastack radio info --ctid 340

# System summary
sudo infrastack radio info --summary
```

## Logs

```bash
# View application logs (default)
sudo infrastack radio logs --ctid 340

# View last 100 lines
sudo infrastack radio logs --ctid 340 --lines 100

# Follow logs in real-time
sudo infrastack radio logs --ctid 340 --follow

# View container system logs
sudo infrastack radio logs --ctid 340 --type container

# View both
sudo infrastack radio logs --ctid 340 --type both

# View specific service logs
sudo infrastack radio logs --ctid 340 --service liquidsoap
```

## Updates

```bash
# Update specific container
sudo infrastack radio update --ctid 340

# Update all of one platform
sudo infrastack radio update --platform azuracast

# Update all radio containers
sudo infrastack radio update --all
```

## Backups

```bash
# Backup specific container (vzdump)
sudo infrastack radio backup --ctid 340

# Backup with application data
sudo infrastack radio backup --ctid 340 --type application

# Full backup (container + ZFS snapshot)
sudo infrastack radio backup --ctid 340 --type full

# Backup all containers
sudo infrastack radio backup --all

# List available backups
sudo infrastack radio backup --list

# List backups for specific container
sudo infrastack radio backup --list --ctid 340
```

## Container Management

```bash
# Using InfraStack (for radio-specific operations)
sudo infrastack radio status --ctid 340
sudo infrastack radio info --ctid 340
sudo infrastack radio logs --ctid 340

# Using Proxmox directly
sudo pct status 340
sudo pct start 340
sudo pct stop 340
sudo pct restart 340
sudo pct enter 340
sudo pct exec 340 -- bash
sudo pct config 340
```

## Docker Services (Inside Container)

```bash
# All commands via pct exec or after entering container

# Service status
docker compose -f /opt/libretime/docker-compose.yml ps

# View all logs
docker compose -f /opt/libretime/docker-compose.yml logs --tail 100

# View specific service logs
docker compose -f /opt/libretime/docker-compose.yml logs liquidsoap --tail 50
docker compose -f /opt/libretime/docker-compose.yml logs playout --tail 50

# Restart all services
docker compose -f /opt/libretime/docker-compose.yml restart

# Restart specific service
docker compose -f /opt/libretime/docker-compose.yml restart liquidsoap
```

## Removal

```bash
# Remove container (keep data)
sudo infrastack radio remove --ctid 340

# Remove container AND data
sudo infrastack radio remove --ctid 340 --data

# Emergency: Remove all containers (dangerous!)
sudo infrastack radio remove --purge-all
```

## Configuration Files

### On Proxmox Host
```
InfraStack Installation:    /opt/infrastack
Radio Scripts:              /opt/infrastack/scripts/radio/
Inventory File:             /etc/infrastack/inventory/stations.csv
Configuration:              /etc/infrastack/infrastack.conf
ZFS Media Datasets:         /hdd-pool/container-data/{platform}-media/{station}
Container Config:           /etc/pve/lxc/{CTID}.conf
```

### Inside Container (LibreTime)
```
Installation:               /opt/libretime
Configuration:              /opt/libretime/config.yml
Environment Variables:      /opt/libretime/.env
Docker Compose:             /opt/libretime/docker-compose.yml
Media Storage:              /srv/libretime
```

### Inside Container (AzuraCast)
```
Installation:               /var/azuracast
Docker Compose:             /var/azuracast/docker-compose.yml
Media Storage:              /var/azuracast/stations
```

## Troubleshooting Quick Commands

### No Audio Streaming (LibreTime)

```bash
# Check playout service
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml logs playout

# Check liquidsoap
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml logs liquidsoap

# Fix file permissions
sudo pct exec 201 -- chown -R 1000:1000 /srv/libretime/
```

### Web Interface Not Loading

```bash
# Check nginx
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml logs nginx

# Test from inside
sudo pct exec 201 -- curl -I http://localhost:8080
```

### Database Errors

```bash
# Re-run migrations
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml exec -T api libretime-api migrate

# Restart services
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml restart
```

### Services Not Starting After Reboot

```bash
# Check Docker status
sudo pct exec 201 -- systemctl status docker

# Enable Docker autostart
sudo pct exec 201 -- systemctl enable docker
```

## Storage Management

```bash
# Check ZFS usage
sudo zfs list | grep -E "(azuracast|libretime)-media"

# Check inside container
sudo pct exec 201 -- df -h /srv/libretime

# Increase quota
sudo zfs set quota=1T hdd-pool/container-data/libretime-media/station1

# Create manual snapshot
sudo zfs snapshot hdd-pool/container-data/libretime-media/station1@$(date +%Y%m%d)
```

## Media Management

```bash
# Upload single file
sudo pct push 201 /path/to/song.mp3 /srv/libretime/imported/

# Upload directory
sudo pct push 201 /path/to/music /srv/libretime/imported/

# Fix permissions after upload
sudo pct exec 201 -- chown -R 1000:1000 /srv/libretime/imported/
```

## Quick Health Check

```bash
# One command to check everything (LibreTime)
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml ps && \
sudo pct exec 201 -- curl -s -o /dev/null -w "HTTP: %{http_code}\n" http://localhost:8080 && \
echo "Checks passed"
```

## Emergency Recovery

### Complete Service Restart

```bash
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml down
sudo pct exec 201 -- docker compose -f /opt/libretime/docker-compose.yml up -d
```

### Nuclear Option (Redeploy)

```bash
# DANGER: Destroys everything!
sudo pct stop 201
sudo pct destroy 201
sudo zfs destroy hdd-pool/container-data/libretime-media/station1

# Redeploy fresh
sudo infrastack radio deploy libretime -i 201 -n station1
```

## Common Port Mapping

```
Port    Service
----    -------
80      AzuraCast Web Interface
8080    LibreTime Web Interface
8000    Icecast Streaming Server
8001    Harbor Input (Master/Live)
8002    Harbor Input (Show)
```

## Getting Help

```bash
# InfraStack help
infrastack help
infrastack radio help

# Radio module documentation
ls /opt/infrastack/docs/radio/
```

---

**Pro Tip**: Create shell aliases for common commands:

```bash
# Add to ~/.bashrc
alias radio-status='sudo infrastack radio status'
alias radio-logs='sudo infrastack radio logs'
alias lt-logs='docker compose -f /opt/libretime/docker-compose.yml logs'
alias lt-ps='docker compose -f /opt/libretime/docker-compose.yml ps'
alias lt-restart='docker compose -f /opt/libretime/docker-compose.yml restart'
```
