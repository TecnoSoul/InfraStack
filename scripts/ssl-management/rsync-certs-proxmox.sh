#!/bin/bash
################################################################################
# Script: rsync-certs-proxmox.sh
# Description: Pull SSL certificates from hosting1.ts and deploy to Proxmox
# Author: TecnoSoul Infrastructure Team
# Repository: https://github.com/TecnoSoul/InfraStack
#
# Configuration:
#   Create /root/.rsync-certs-proxmox.conf to override defaults
#   See rsync-certs-proxmox.conf.example for options
################################################################################

# ===== DEFAULT CONFIGURATION =====
# These can be overridden in /root/.rsync-certs-proxmox.conf

LOCALDIR=/tmp/ssl-staging/
REMOTEHOST=hosting1.tecnosoul.com.ar
REMOTEPORT=2200
REMOTEUSER="tecno"
REMOTEDIR=/home/tecno/
PROXMOX_CERT_DIR=/etc/pve/local
LOG_FILE=/var/log/ssl-cert-sync.log

# ===== COMMAND LINE OPTIONS =====
SKIP_CONFIRM=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes|--skip-confirm)
            SKIP_CONFIRM=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -y, --yes, --skip-confirm    Skip confirmation prompt (for cron)"
            echo "  -h, --help                   Show this help message"
            echo ""
            echo "Configuration:"
            echo "  Create /root/.rsync-certs-proxmox.conf to override defaults"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ===== LOAD LOCAL CONFIG (if exists) =====
CONFIG_FILE="/root/.rsync-certs-proxmox.conf"
CONFIG_SOURCE="defaults"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    CONFIG_SOURCE="$CONFIG_FILE"
fi

# ===== DISPLAY CONFIGURATION =====
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        Proxmox SSL Certificate Sync Configuration         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Hostname:           $(hostname -f)"
echo "  Config source:      $CONFIG_SOURCE"
echo ""
echo "  Remote host:        $REMOTEHOST:$REMOTEPORT"
echo "  Remote user:        $REMOTEUSER"
echo "  Remote directory:   $REMOTEDIR"
echo ""
echo "  Local staging:      $LOCALDIR"
echo "  Proxmox cert dir:   $PROXMOX_CERT_DIR"
echo "  Log file:           $LOG_FILE"
echo ""
echo "────────────────────────────────────────────────────────────"

# ===== CONFIRMATION PROMPT =====
if [ $SKIP_CONFIRM -eq 0 ]; then
    echo ""
    read -p "Proceed with certificate sync? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted by user."
        exit 0
    fi
    echo ""
fi

# ===== LOG START =====
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting certificate sync from $REMOTEHOST (config: $CONFIG_SOURCE)" >> $LOG_FILE

# ===== MAIN SCRIPT =====

echo "→ Creating staging directory..."
mkdir -p $LOCALDIR

echo "→ Pulling certificates from $REMOTEHOST:$REMOTEPORT..."
rsync -arz -e "ssh -p $REMOTEPORT" --include 'ssl.*' --exclude '*' \
    $REMOTEUSER@$REMOTEHOST:$REMOTEDIR $LOCALDIR

if [ $? -ne 0 ]; then
    echo "✗ ERROR: Failed to pull certificates from $REMOTEHOST"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to pull certificates from $REMOTEHOST" >> $LOG_FILE
    exit 1
fi
echo "✓ Certificates pulled successfully"

# Verify downloaded files
if [ ! -f "$LOCALDIR/ssl.cert" ] || [ ! -f "$LOCALDIR/ssl.key" ]; then
    echo "✗ ERROR: Certificate files not found after download"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Certificate files missing after download" >> $LOG_FILE
    exit 1
fi

# Show certificate info
echo ""
echo "→ Certificate information:"
openssl x509 -in $LOCALDIR/ssl.cert -noout -subject -dates -issuer | sed 's/^/  /'
echo ""

# Backup existing Proxmox certificates
if [ -f $PROXMOX_CERT_DIR/pve-ssl.pem ]; then
    echo "→ Backing up existing certificates..."
    cp $PROXMOX_CERT_DIR/pve-ssl.pem $PROXMOX_CERT_DIR/pve-ssl.pem.backup.$(date +%Y%m%d) 2>/dev/null
    cp $PROXMOX_CERT_DIR/pve-ssl.key $PROXMOX_CERT_DIR/pve-ssl.key.backup.$(date +%Y%m%d) 2>/dev/null
    echo "✓ Backup created"
fi

echo "→ Preparing Proxmox certificate format..."
cat $LOCALDIR/ssl.cert $LOCALDIR/ssl.key > $PROXMOX_CERT_DIR/pve-ssl.pem
cp $LOCALDIR/ssl.key $PROXMOX_CERT_DIR/pve-ssl.key

# Set correct permissions
chmod 640 $PROXMOX_CERT_DIR/pve-ssl.pem
chmod 640 $PROXMOX_CERT_DIR/pve-ssl.key
chown root:www-data $PROXMOX_CERT_DIR/pve-ssl.pem
chown root:www-data $PROXMOX_CERT_DIR/pve-ssl.key
echo "✓ Certificates deployed to $PROXMOX_CERT_DIR"

echo "→ Restarting pveproxy service..."
systemctl restart pveproxy

if [ $? -eq 0 ]; then
    echo "✓ pveproxy restarted successfully"
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    ✓ SUCCESS                               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Proxmox SSL certificates updated on $(hostname -f)"
    echo "  Access web interface: https://$(hostname -f):8006"
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Proxmox SSL certificates updated on $(hostname)" >> $LOG_FILE
else
    echo "✗ ERROR: Failed to restart pveproxy"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to restart pveproxy on $(hostname)" >> $LOG_FILE
    exit 1
fi

# Cleanup staging directory
echo "→ Cleaning up..."
rm -rf $LOCALDIR
echo "✓ Temporary files removed"
echo ""

#script END