#!/bin/bash
#=============================================================================
# InfraStack - Vaultwarden Container Deployment
# Part of InfraStack sysadmin infrastructure toolkit
#
# Description: Deploy Vaultwarden (Bitwarden-compatible) via Docker
#              Stack: Vaultwarden + SQLite (single container)
#              Data stored on hdd-pool (ZFS)
#              SSL/proxy via NPM (CT200)
#
# Usage: ./scripts/containers/vaultwarden.sh -i <ctid> -n <name> [OPTIONS]
# Example: ./scripts/containers/vaultwarden.sh -i 211 -n vault
#
# Author: TecnoSoul
#=============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$INFRASTACK_ROOT/scripts/lib/common.sh"
source "$INFRASTACK_ROOT/scripts/lib/container.sh"

#=============================================================================
# CONFIGURATION DEFAULTS
#=============================================================================

DEFAULT_CORES=2
DEFAULT_MEMORY=512
DEFAULT_ROOTFS_SIZE=8
DEFAULT_NETWORK="192.168.2"
DEFAULT_GATEWAY="192.168.2.1"
DEFAULT_BRIDGE="vmbr1"

HDD_POOL_BASE="/hdd-pool/container-data"
VW_DATASET="vaultwarden"
VW_DATA_PATH="${HDD_POOL_BASE}/${VW_DATASET}"

VW_APP_PATH="/opt/vaultwarden"
VW_DOMAIN="vault.tecnosoul.com.ar"

# Vaultwarden listens on this port inside the container
VW_PORT=8080

#=============================================================================
# ZFS DATASET SETUP
#=============================================================================

create_zfs_dataset() {
    log_step "Setting up ZFS dataset on hdd-pool"

    if ! zfs list "hdd-pool/container-data/${VW_DATASET}" &>/dev/null 2>&1; then
        zfs create \
            -o recordsize=16k \
            -o atime=off \
            -o compression=lz4 \
            "hdd-pool/container-data/${VW_DATASET}"
        log_success "ZFS dataset created: hdd-pool/container-data/${VW_DATASET}"
    else
        log_info "ZFS dataset already exists, skipping"
    fi

    mkdir -p "${VW_DATA_PATH}"

    # Vaultwarden runs as uid 65534 (nobody) inside container
    # Unprivileged offset: 100000 + 65534 = 165534
    chown -R 165534:165534 "${VW_DATA_PATH}"

    log_success "ZFS dataset ready at ${VW_DATA_PATH}"
}

#=============================================================================
# INFRASTACK INSTALLATION
#=============================================================================

install_infrastack() {
    local ctid=$1

    pct exec "$ctid" -- bash -c '
        apt-get install -y git
        cd /root
        if [[ -d InfraStack ]]; then
            cd InfraStack && git pull
        else
            git clone https://github.com/TecnoSoul/InfraStack.git
            cd InfraStack
        fi
        ./install.sh
    '
}

#=============================================================================
# CONTAINER CREATION
#=============================================================================

create_vaultwarden_container() {
    local ctid=$1
    local name=$2
    local cores=${3:-$DEFAULT_CORES}
    local memory=${4:-$DEFAULT_MEMORY}
    local ip_suffix=${5:-$ctid}

    local hostname="${name}.tecnosoul.com.ar"
    local ip_address="${DEFAULT_NETWORK}.${ip_suffix}"
    local swap=$((memory / 2))

    log_info "Deploying Vaultwarden Container"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Container ID:    $ctid"
    echo "Hostname:        $hostname"
    echo "IP Address:      $ip_address"
    echo "CPU Cores:       $cores"
    echo "Memory:          ${memory}MB  (Vaultwarden is very lightweight)"
    echo "Root disk:       ${DEFAULT_ROOTFS_SIZE}GB on NVMe (data pool)"
    echo "Data path:       ${VW_DATA_PATH} (hdd-pool ZFS)"
    echo "Domain:          ${VW_DOMAIN}"
    echo "Stack:           Vaultwarden (single container, SQLite)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if ! confirm_action "Proceed with Vaultwarden deployment?" "y"; then
        log_info "Deployment cancelled"
        return 1
    fi

    if pct status "$ctid" &>/dev/null; then
        log_error "Container $ctid already exists"
        return 1
    fi

    # Step 1: ZFS dataset
    create_zfs_dataset

    # Step 2: Create LXC container
    log_step "Creating LXC container"
    pct create "$ctid" local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
        --hostname "$hostname" \
        --description "Vaultwarden - vault.tecnosoul.com.ar" \
        --cores "$cores" \
        --memory "$memory" \
        --swap "$swap" \
        --rootfs "data:${DEFAULT_ROOTFS_SIZE}" \
        --unprivileged 1 \
        --features "nesting=1,keyctl=1" \
        --net0 "name=eth0,bridge=${DEFAULT_BRIDGE},ip=${ip_address}/24,gw=${DEFAULT_GATEWAY}" \
        --nameserver 8.8.8.8 \
        --searchdomain tecnosoul.com.ar \
        --ostype debian \
        --start 0

    # Step 3: Mount hdd-pool dataset
    log_step "Mounting hdd-pool dataset into container"
    pct set "$ctid" --mp0 "${VW_DATA_PATH},mp=/mnt/vaultwarden-data"

    # Step 4: Start container
    log_step "Starting container"
    pct start "$ctid"
    wait_for_container "$ctid"

    # Step 5: System setup
    log_step "Updating system packages"
    pct exec "$ctid" -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get dist-upgrade -y -qq
    "

    # Step 6: InfraStack
    log_step "Installing InfraStack"
    install_infrastack "$ctid"

    log_step "Installing base packages"
    pct exec "$ctid" -- infrastack setup base

    log_step "Configuring Zsh"
    pct exec "$ctid" -- infrastack setup zsh root

    # Step 7: Timezone
    log_step "Configuring timezone"
    pct exec "$ctid" -- timedatectl set-timezone America/Argentina/Buenos_Aires

    # Step 8: Docker
    install_docker "$ctid"

    # Step 9: Deploy Vaultwarden
    deploy_vaultwarden "$ctid"

    # Step 10: Summary
    display_vaultwarden_summary "$ctid" "$hostname" "$ip_address"

    return 0
}

#=============================================================================
# DOCKER INSTALLATION
#=============================================================================

install_docker() {
    local ctid=$1

    log_step "Installing Docker"

    pct exec "$ctid" -- bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y -qq ca-certificates curl gnupg lsb-release

        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg \
            -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
            https://download.docker.com/linux/debian \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update -qq
        apt-get install -y -qq \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin

        systemctl enable docker
        systemctl start docker
        echo "Docker: $(docker --version)"
    '

    log_success "Docker installed"
}

#=============================================================================
# VAULTWARDEN DEPLOYMENT
#=============================================================================

deploy_vaultwarden() {
    local ctid=$1

    log_step "Deploying Vaultwarden"

    # Generate admin token (argon2 hash via openssl fallback)
    local admin_token
    admin_token=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48)

    # Save credentials on Proxmox host
    local creds_file="/root/vaultwarden-credentials-ct${ctid}.txt"
    cat > "$creds_file" << EOF
# Vaultwarden Credentials - CT${ctid}
# Generated: $(date)
# KEEP THIS FILE SECURE

VAULTWARDEN_URL=https://${VW_DOMAIN}
ADMIN_PANEL=https://${VW_DOMAIN}/admin
ADMIN_TOKEN=${admin_token}

# First user registration:
# 1. Open https://${VW_DOMAIN}
# 2. Create your account
# 3. Then DISABLE registration (already set in config)
# 4. Admin panel: https://${VW_DOMAIN}/admin

CONTAINER_APP_PATH=${VW_APP_PATH}
DATA_PATH_HOST=${VW_DATA_PATH}
DATA_PATH_CONTAINER=/mnt/vaultwarden-data
EOF
    chmod 600 "$creds_file"
    log_info "Credentials saved to: $creds_file (on Proxmox host)"

    # Create app directory inside container
    pct exec "$ctid" -- bash -c "mkdir -p ${VW_APP_PATH}"

    # Write docker-compose.yml
    pct exec "$ctid" -- bash -c "cat > ${VW_APP_PATH}/docker-compose.yml << 'COMPOSE_EOF'
services:

  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    ports:
      - \"${VW_PORT}:80\"
    environment:
      # Domain (required for WebAuthn, attachments, etc.)
      DOMAIN: https://${VW_DOMAIN}

      # Admin panel - access at /admin
      # IMPORTANT: disable after initial setup if not needed regularly
      ADMIN_TOKEN: ${admin_token}

      # Registration: only allow first setup, then disable
      # Set to true temporarily to create your account, then set to false
      SIGNUPS_ALLOWED: \"true\"

      # Email notifications (configure after setup if needed)
      # SMTP_HOST: mail.tecnosoul.com.ar
      # SMTP_PORT: 587
      # SMTP_SECURITY: starttls
      # SMTP_USERNAME: noreply@tecnosoul.com.ar
      # SMTP_PASSWORD: your_smtp_password
      # SMTP_FROM: noreply@tecnosoul.com.ar

      # Invitations (for adding org members without open registration)
      INVITATIONS_ALLOWED: \"true\"

      # Websocket for live sync between clients
      WEBSOCKET_ENABLED: \"true\"

      # Logging
      LOG_LEVEL: warn
      EXTENDED_LOGGING: \"true\"

      # Timezone
      TZ: America/Argentina/Buenos_Aires

    volumes:
      - /mnt/vaultwarden-data:/data

COMPOSE_EOF"

    # Start Vaultwarden
    pct exec "$ctid" -- bash -c "cd ${VW_APP_PATH} && docker compose up -d"

    log_success "Vaultwarden deployed"
}

#=============================================================================
# SUMMARY
#=============================================================================

display_vaultwarden_summary() {
    local ctid=$1
    local hostname=$2
    local ip_address=$3

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Vaultwarden Deployed! CT${ctid}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Container:   CT${ctid} | ${hostname}"
    echo "  IP:          ${ip_address}"
    echo "  Internal:    http://${ip_address}:${VW_PORT}"
    echo "  Public:      https://${VW_DOMAIN}  (after NPM setup)"
    echo "  Admin panel: https://${VW_DOMAIN}/admin"
    echo ""
    echo "  Credentials: /root/vaultwarden-credentials-ct${ctid}.txt"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "NEXT STEPS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. DNS Record:"
    echo "   ${VW_DOMAIN}.  A  15.235.57.208"
    echo ""
    echo "2. NPM (CT200) - Add Proxy Host:"
    echo "   Domain:        ${VW_DOMAIN}"
    echo "   Scheme:        http"
    echo "   Forward IP:    ${ip_address}"
    echo "   Forward Port:  ${VW_PORT}"
    echo "   Websockets:    ✅ (required for live sync)"
    echo "   SSL:           Let's Encrypt + Force HTTPS"
    echo ""
    echo "3. Crear tu cuenta en https://${VW_DOMAIN}"
    echo "   (registration está abierta solo para el primer setup)"
    echo ""
    echo "4. DESPUÉS de crear tu cuenta, deshabilitar registro:"
    echo "   pct exec ${ctid} -- docker exec vaultwarden \\"
    echo "     sh -c \"echo 'SIGNUPS_ALLOWED=false' >> /data/.env\""
    echo "   pct exec ${ctid} -- bash -c \\"
    echo "     'cd ${VW_APP_PATH} && docker compose restart'"
    echo ""
    echo "5. Verificar en admin panel: https://${VW_DOMAIN}/admin"
    echo "   (token en /root/vaultwarden-credentials-ct${ctid}.txt)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

#=============================================================================
# HELP
#=============================================================================

show_help() {
    cat << EOF
InfraStack - Vaultwarden Container Deployment

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Container ID (required)
    -n, --name NAME         Container name, e.g. "vault" (required)
    -c, --cores NUM         CPU cores (default: ${DEFAULT_CORES})
    -m, --memory MB         Memory in MB (default: ${DEFAULT_MEMORY})
    -p, --ip-suffix NUM     Last octet of IP (default: same as CTID)
    -h, --help              Show this help

Examples:
    $0 -i 211 -n vault

What Gets Deployed:
    • Unprivileged LXC (nesting=1 for Docker)
    • Root disk: ${DEFAULT_ROOTFS_SIZE}GB on NVMe
    • Data: hdd-pool/container-data/vaultwarden → /mnt/vaultwarden-data
    • InfraStack + base packages + Zsh
    • Docker CE
    • Vaultwarden (single container, SQLite)

Resource footprint:
    • RAM: ~50-100MB (very lightweight)
    • Disk data: minimal (SQLite DB + attachments)

EOF
    exit 0
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    CTID=""
    NAME=""
    CORES=$DEFAULT_CORES
    MEMORY=$DEFAULT_MEMORY
    IP_SUFFIX=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--ctid)      CTID="$2";   shift 2 ;;
            -n|--name)      NAME="$2";   shift 2 ;;
            -c|--cores)     CORES="$2";  shift 2 ;;
            -m|--memory)    MEMORY="$2"; shift 2 ;;
            -p|--ip-suffix) IP_SUFFIX="$2"; shift 2 ;;
            -h|--help)      show_help ;;
            *) log_error "Unknown option: $1"; show_help ;;
        esac
    done

    if [[ -z "$CTID" ]] || [[ -z "$NAME" ]]; then
        log_error "Container ID and name are required"
        show_help
    fi

    check_root
    create_vaultwarden_container "$CTID" "$NAME" "$CORES" "$MEMORY" "$IP_SUFFIX"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
