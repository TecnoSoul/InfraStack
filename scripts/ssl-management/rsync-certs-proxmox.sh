#!/bin/bash
################################################################################
# Script: rsync-certs-proxmox.sh
# Description: Pull SSL certificates from hosting1.ts and deploy to Proxmox
# Author: TecnoSoul Infrastructure Team
# Repository: https://github.com/TecnoSoul/InfraStack
################################################################################

# Configuration
LOCALDIR=/tmp/ssl-staging/
REMOTEHOST=hosting1.tecnosoul.com.ar
REMOTEPORT=2200
REMOTEUSER="tecno"
REMOTEDIR=/home/tecno/
PROXMOX_CERT_DIR=/etc/pve/local

# Create local staging directory
mkdir -p $LOCALDIR

# Pull certificates from hosting1.ts
# Selecciono los archivos ssl.* con include y excluyo lo demas
rsync -arz -e "ssh -p $REMOTEPORT" --include 'ssl.*' --exclude '*' \
    $REMOTEUSER@$REMOTEHOST:$REMOTEDIR $LOCALDIR

# Backup existing Proxmox certificates
if [ -f $PROXMOX_CERT_DIR/pve-ssl.pem ]; then
    cp $PROXMOX_CERT_DIR/pve-ssl.pem $PROXMOX_CERT_DIR/pve-ssl.pem.backup.$(date +%Y%m%d)
    cp $PROXMOX_CERT_DIR/pve-ssl.key $PROXMOX_CERT_DIR/pve-ssl.key.backup.$(date +%Y%m%d)
fi

# Prepare Proxmox certificate format (cert + key combined for PEM)
cat $LOCALDIR/ssl.cert $LOCALDIR/ssl.key > $PROXMOX_CERT_DIR/pve-ssl.pem
cp $LOCALDIR/ssl.key $PROXMOX_CERT_DIR/pve-ssl.key

# Set correct permissions (Proxmox expects these)
chmod 640 $PROXMOX_CERT_DIR/pve-ssl.pem
chmod 640 $PROXMOX_CERT_DIR/pve-ssl.key
chown root:www-data $PROXMOX_CERT_DIR/pve-ssl.pem
chown root:www-data $PROXMOX_CERT_DIR/pve-ssl.key

# Restart pveproxy
systemctl restart pveproxy

# Cleanup staging directory
rm -rf $LOCALDIR

# Log completion
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Proxmox SSL certificates updated on $(hostname)" >> /var/log/ssl-cert-sync.log

#script END