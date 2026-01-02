#!/bin/bash
# /root/radio-platform/scripts/common-functions.sh
# Shared functions for all radio platform deployments

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check if container ID is available
check_ctid_available() {
    local ctid=$1
    if pct status "$ctid" &>/dev/null; then
        log_error "Container $ctid already exists"
        return 1
    fi
    return 0
}

# Create ZFS dataset with optimal settings
create_media_dataset() {
    local dataset=$1
    local quota=$2
    local recordsize=${3:-128k}  # Default 128k for media
    
    log_info "Creating ZFS dataset: $dataset"
    
    zfs create -p "$dataset"
    zfs set compression=lz4 "$dataset"
    zfs set recordsize="$recordsize" "$dataset"
    zfs set atime=off "$dataset"
    
    if [[ -n "$quota" ]]; then
        zfs set quota="$quota" "$dataset"
        log_info "Set quota: $quota"
    fi
    
    # Fix permissions for unprivileged containers
    chown -R 100000:100000 "/$dataset"
    chmod -R 755 "/$dataset"
    
    log_info "Dataset created and permissions set"
}

# Create standard container base
create_base_container() {
    local ctid=$1
    local hostname=$2
    local cores=$3
    local memory=$4
    local ip_address=$5
    local description=$6
    
    log_info "Creating container $ctid ($hostname)"
    
    pct create "$ctid" local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
        --hostname "$hostname" \
        --description "$description" \
        --cores "$cores" \
        --memory "$memory" \
        --swap $((memory / 4)) \
        --rootfs data:32 \
        --unprivileged 1 \
        --features nesting=1,keyctl=1 \
        --net0 name=eth0,bridge=vmbr1,ip="$ip_address/24",gw=192.168.2.1 \
        --nameserver 8.8.8.8 \
        --searchdomain tecnosoul.com.ar \
        --ostype debian \
        --start 0
    
    log_info "Container $ctid created successfully"
}

# Attach mount point to container
attach_mount_point() {
    local ctid=$1
    local mp_id=$2
    local host_path=$3
    local container_path=$4
    
    log_info "Attaching mount point mp$mp_id: $host_path -> $container_path"
    
    pct set "$ctid" -mp"$mp_id" "$host_path,mp=$container_path"
    
    log_info "Mount point attached successfully"
}

# Basic system setup inside container
setup_container_system() {
    local ctid=$1
    
    log_info "Updating system and installing essentials in container $ctid"
    
    pct exec "$ctid" -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt update
        apt dist-upgrade -y
        apt install -y curl wget git ca-certificates gnupg sudo htop vim
        timedatectl set-timezone America/Argentina/Buenos_Aires
    "
    
    log_info "System setup completed"
}

# Add entry to inventory
add_to_inventory() {
    local ctid=$1
    local type=$2  # azuracast or libretime
    local hostname=$3
    local ip=$4
    local description=$5
    
    local inventory_file="/root/radio-platform/configs/container-inventory.csv"
    
    # Create inventory file if doesn't exist
    if [[ ! -f "$inventory_file" ]]; then
        echo "CTID,Type,Hostname,IP,Description,Created,Status" > "$inventory_file"
    fi
    
    # Add entry
    echo "$ctid,$type,$hostname,$ip,\"$description\",$(date +%Y-%m-%d),active" >> "$inventory_file"
    
    log_info "Added to inventory: $hostname ($ctid)"
}

# Wait for container to be fully started
wait_for_container() {
    local ctid=$1
    local max_wait=${2:-30}
    local count=0
    
    log_info "Waiting for container $ctid to be ready..."
    
    while [[ $count -lt $max_wait ]]; do
        if pct exec "$ctid" -- systemctl is-system-running &>/dev/null; then
            log_info "Container is ready"
            return 0
        fi
        sleep 2
        ((count+=2))
    done
    
    log_warn "Container may not be fully ready, continuing anyway"
    return 0
}

# Export functions
export -f log_info log_warn log_error
export -f check_root check_ctid_available
export -f create_media_dataset create_base_container
export -f attach_mount_point setup_container_system
export -f add_to_inventory wait_for_container