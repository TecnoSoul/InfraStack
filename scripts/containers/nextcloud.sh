#!/bin/bash
#=============================================================================
# InfraStack - Nextcloud Container Deployment
# Part of InfraStack sysadmin infrastructure toolkit
#
# Description: Deploy Nextcloud via Docker inside a Debian LXC container
#              Stack: Nextcloud (apache) + MariaDB + Redis
#              Data stored on hdd-pool (ZFS)
#              SSL/proxy via NPM (CT200)
#
# Usage: ./scripts/containers/nextcloud.sh -i <ctid> -n <name> [OPTIONS]
# Example: ./scripts/containers/nextcloud.sh -i 210 -n nube
#
# Author: TecnoSoul
#=============================================================================

set -euo pipefail

# Get script directory and InfraStack root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common library
source "$INFRASTACK_ROOT/scripts/lib/common.sh"
source "$INFRASTACK_ROOT/scripts/lib/container.sh"

#=============================================================================
# CONFIGURATION DEFAULTS
#=============================================================================

DEFAULT_CORES=4
DEFAULT_MEMORY=4096
DEFAULT_ROOTFS_SIZE=20
DEFAULT_NETWORK="192.168.2"
DEFAULT_GATEWAY="192.168.2.1"
DEFAULT_BRIDGE="vmbr1"

# ZFS dataset for Nextcloud data on hdd-pool
HDD_POOL_BASE="/hdd-pool/container-data"
NC_DATASET="nextcloud"
NC_DATA_PATH="${HDD_POOL_BASE}/${NC_DATASET}"

# App install path inside container
NC_APP_PATH="/opt/nextcloud"

# Nextcloud URL (used in docker-compose trusted_domains)
NC_DOMAIN="nube.tecnosoul.com.ar"

#=============================================================================
# ZFS DATASET SETUP (on Proxmox host)
#=============================================================================

create_zfs_dataset() {
    local ctid=$1

    log_step "Setting up ZFS dataset on hdd-pool"

    # Create dataset if it doesn't exist
    if ! zfs list "${HDD_POOL_BASE/\/hdd-pool\//hdd-pool/}/${NC_DATASET}" &>/dev/null 2>&1; then
        zfs create \
            -o recordsize=128k \
            -o atime=off \
            -o compression=lz4 \
            "hdd-pool/container-data/${NC_DATASET}"
        log_success "ZFS dataset created: hdd-pool/container-data/${NC_DATASET}"
    else
        log_info "ZFS dataset already exists, skipping creation"
    fi

    # Create subdirectory structure
    mkdir -p "${NC_DATA_PATH}/data"
    mkdir -p "${NC_DATA_PATH}/config"
    mkdir -p "${NC_DATA_PATH}/db"
    mkdir -p "${NC_DATA_PATH}/redis"

    # Fix permissions for unprivileged container (uid/gid offset = 100000)
    # www-data in container = uid 33, offset → 100033 on host
    # mysql in container    = uid 999, offset → 100999 on host
    # redis in container    = uid 999, offset → 100999 on host
    log_step "Setting ZFS dataset permissions for unprivileged container"
    chown -R 100033:100033 "${NC_DATA_PATH}/data"
    chown -R 100033:100033 "${NC_DATA_PATH}/config"
    chown -R 100999:100999 "${NC_DATA_PATH}/db"
    chown -R 100999:100999 "${NC_DATA_PATH}/redis"

    log_success "ZFS dataset ready at ${NC_DATA_PATH}"
}

#=============================================================================
# INFRASTACK INSTALL (inside container)
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

create_nextcloud_container() {
    local ctid=$1
    local name=$2
    local cores=${3:-$DEFAULT_CORES}
    local memory=${4:-$DEFAULT_MEMORY}
    local ip_suffix=${5:-$ctid}

    local hostname="${name}.tecnosoul.com.ar"
    local ip_address="${DEFAULT_NETWORK}.${ip_suffix}"
    local swap=$((memory / 2))

    log_info "Deploying Nextcloud Container"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Container ID:    $ctid"
    echo "Hostname:        $hostname"
    echo "IP Address:      $ip_address"
    echo "CPU Cores:       $cores"
    echo "Memory:          ${memory}MB"
    echo "Root disk:       ${DEFAULT_ROOTFS_SIZE}GB on NVMe (data pool)"
    echo "Data path:       ${NC_DATA_PATH} (hdd-pool ZFS)"
    echo "Domain:          ${NC_DOMAIN}"
    echo "Stack:           Nextcloud (apache) + MariaDB + Redis"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if ! confirm_action "Proceed with Nextcloud deployment?" "y"; then
        log_info "Deployment cancelled"
        return 1
    fi

    # Check if container exists
    if pct status "$ctid" &>/dev/null; then
        log_error "Container $ctid already exists"
        return 1
    fi

    # Step 1: ZFS dataset
    create_zfs_dataset "$ctid"

    # Step 2: Create LXC container (unprivileged, nesting for Docker)
    log_step "Creating LXC container"
    pct create "$ctid" local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
        --hostname "$hostname" \
        --description "Nextcloud - nube.tecnosoul.com.ar" \
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

    # Step 3: Mount hdd-pool dataset inside container
    log_step "Mounting hdd-pool dataset into container"
    pct set "$ctid" \
        --mp0 "${NC_DATA_PATH},mp=/mnt/nextcloud-data"

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

    # Step 6: Install InfraStack
    log_step "Installing InfraStack"
    install_infrastack "$ctid"

    # Step 7: Base packages + Zsh
    log_step "Installing base packages"
    pct exec "$ctid" -- infrastack setup base

    log_step "Configuring Zsh"
    pct exec "$ctid" -- infrastack setup zsh root

    # Step 8: Timezone
    log_step "Configuring timezone"
    pct exec "$ctid" -- timedatectl set-timezone America/Argentina/Buenos_Aires

    # Step 9: Install Docker
    install_docker "$ctid"

    # Step 10: Deploy Nextcloud stack
    deploy_nextcloud_stack "$ctid"

    # Step 11: Display summary
    display_nextcloud_summary "$ctid" "$hostname" "$ip_address"

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

        # Install dependencies
        apt-get install -y -qq \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        # Add Docker GPG key
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg \
            -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        # Add Docker repository
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
            https://download.docker.com/linux/debian \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker
        apt-get update -qq
        apt-get install -y -qq \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin

        # Enable and start Docker
        systemctl enable docker
        systemctl start docker

        echo "Docker version: $(docker --version)"
        echo "Docker Compose version: $(docker compose version)"
    '

    log_success "Docker installed successfully"
}

#=============================================================================
# NEXTCLOUD STACK DEPLOYMENT
#=============================================================================

deploy_nextcloud_stack() {
    local ctid=$1

    log_step "Deploying Nextcloud Docker stack"

    # Generate secure passwords
    local db_root_pass
    local db_pass
    local nc_admin_pass
    db_root_pass=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)
    db_pass=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)
    nc_admin_pass=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)

    # Save credentials to host for reference
    local creds_file="/root/nextcloud-credentials-ct${ctid}.txt"
    cat > "$creds_file" << EOF
# Nextcloud Credentials - CT${ctid}
# Generated: $(date)
# KEEP THIS FILE SECURE

NEXTCLOUD_URL=https://${NC_DOMAIN}
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=${nc_admin_pass}

DB_NAME=nextcloud
DB_USER=nextcloud
DB_PASSWORD=${db_pass}
DB_ROOT_PASSWORD=${db_root_pass}

CONTAINER_APP_PATH=${NC_APP_PATH}
DATA_PATH_HOST=${NC_DATA_PATH}
DATA_PATH_CONTAINER=/mnt/nextcloud-data
EOF
    chmod 600 "$creds_file"
    log_info "Credentials saved to: $creds_file (on Proxmox host)"

    # Create app directory and deploy inside container
    pct exec "$ctid" -- bash -c "mkdir -p ${NC_APP_PATH}"

    # Write docker-compose.yml into container
    pct exec "$ctid" -- bash -c "cat > ${NC_APP_PATH}/docker-compose.yml << 'COMPOSE_EOF'
services:

  # ─── Database ───────────────────────────────────────────────
  db:
    image: mariadb:11
    container_name: nextcloud-db
    restart: unless-stopped
    command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
    environment:
      MYSQL_ROOT_PASSWORD: ${db_root_pass}
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: ${db_pass}
    volumes:
      - /mnt/nextcloud-data/db:/var/lib/mysql
    networks:
      - nextcloud-net
    healthcheck:
      test: [\"CMD\", \"healthcheck.sh\", \"--connect\", \"--innodb_initialized\"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  # ─── Redis Cache ─────────────────────────────────────────────
  redis:
    image: redis:alpine
    container_name: nextcloud-redis
    restart: unless-stopped
    command: redis-server --save 60 1 --loglevel warning
    volumes:
      - /mnt/nextcloud-data/redis:/data
    networks:
      - nextcloud-net
    healthcheck:
      test: [\"CMD\", \"redis-cli\", \"ping\"]
      interval: 30s
      timeout: 5s
      retries: 3

  # ─── Nextcloud App ───────────────────────────────────────────
  nextcloud:
    image: nextcloud:apache
    container_name: nextcloud-app
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - \"127.0.0.1:8080:80\"
    environment:
      # Database
      MYSQL_HOST: db
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: ${db_pass}
      # Admin account
      NEXTCLOUD_ADMIN_USER: admin
      NEXTCLOUD_ADMIN_PASSWORD: ${nc_admin_pass}
      # Domain
      NEXTCLOUD_TRUSTED_DOMAINS: ${NC_DOMAIN} 192.168.2.210
      OVERWRITEPROTOCOL: https
      OVERWRITECLIURL: https://${NC_DOMAIN}
      OVERWRITEHOST: ${NC_DOMAIN}
      # Redis
      REDIS_HOST: redis
      REDIS_HOST_PORT: 6379
      # PHP tuning
      PHP_MEMORY_LIMIT: 1024M
      PHP_UPLOAD_LIMIT: 10G
    volumes:
      - /mnt/nextcloud-data/data:/var/www/html/data
      - /mnt/nextcloud-data/config:/var/www/html/config
      - nextcloud-html:/var/www/html
    networks:
      - nextcloud-net

  # ─── Cron (background jobs) ──────────────────────────────────
  cron:
    image: nextcloud:apache
    container_name: nextcloud-cron
    restart: unless-stopped
    depends_on:
      - nextcloud
    entrypoint: /cron.sh
    environment:
      MYSQL_HOST: db
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: ${db_pass}
      REDIS_HOST: redis
    volumes:
      - /mnt/nextcloud-data/data:/var/www/html/data
      - /mnt/nextcloud-data/config:/var/www/html/config
      - nextcloud-html:/var/www/html
    networks:
      - nextcloud-net

volumes:
  nextcloud-html:
    driver: local

networks:
  nextcloud-net:
    driver: bridge
COMPOSE_EOF"

    # Start the stack
    log_step "Starting Nextcloud stack (first run may take a few minutes)"
    pct exec "$ctid" -- bash -c "cd ${NC_APP_PATH} && docker compose up -d"

    log_success "Nextcloud stack deployed"
    log_info "Nextcloud is initializing... wait ~2 minutes before accessing"
}

#=============================================================================
# SUMMARY
#=============================================================================

display_nextcloud_summary() {
    local ctid=$1
    local hostname=$2
    local ip_address=$3

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Nextcloud Container Deployed! CT${ctid}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Container:   CT${ctid} | ${hostname}"
    echo "  IP:          ${ip_address}"
    echo "  App path:    ${NC_APP_PATH}  (inside container)"
    echo "  Data path:   ${NC_DATA_PATH} (on hdd-pool, ZFS)"
    echo ""
    echo "  Nextcloud:   http://${ip_address}:8080  (internal only)"
    echo "  Public URL:  https://${NC_DOMAIN}  (after NPM setup)"
    echo ""
    echo "  Credentials: /root/nextcloud-credentials-ct${ctid}.txt"
    echo "               (on Proxmox host, chmod 600)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "NEXT STEPS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Wait ~2 min for Nextcloud first-run initialization:"
    echo "   pct exec ${ctid} -- docker compose -f ${NC_APP_PATH}/docker-compose.yml logs -f nextcloud"
    echo ""
    echo "2. Configure NPM (CT200) - Add Proxy Host:"
    echo "   Domain:        ${NC_DOMAIN}"
    echo "   Scheme:        http"
    echo "   Forward IP:    ${ip_address}"
    echo "   Forward Port:  8080"
    echo "   Websockets:    ✅ enabled"
    echo "   SSL:           Let's Encrypt (force HTTPS)"
    echo ""
    echo "3. DNS Record:"
    echo "   ${NC_DOMAIN}.  A  15.235.57.208"
    echo ""
    echo "4. After NPM SSL is working, verify Nextcloud config:"
    echo "   pct exec ${ctid} -- docker exec nextcloud-app php occ config:system:get overwriteprotocol"
    echo ""
    echo "5. (Optional) Enable maintenance/preview cron via occ:"
    echo "   pct exec ${ctid} -- docker exec -u www-data nextcloud-app php occ background:cron"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

#=============================================================================
# HELP
#=============================================================================

show_help() {
    cat << EOF
InfraStack - Nextcloud Container Deployment

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Container ID (required)
    -n, --name NAME         Container name, e.g. "nube" (required)
    -c, --cores NUM         CPU cores (default: ${DEFAULT_CORES})
    -m, --memory MB         Memory in MB (default: ${DEFAULT_MEMORY})
    -p, --ip-suffix NUM     Last octet of IP (default: same as CTID)
    -h, --help              Show this help

Examples:
    # Standard deployment
    $0 -i 210 -n nube

    # Custom resources
    $0 -i 210 -n nube -c 6 -m 8192

What Gets Deployed:
    • Unprivileged LXC container (nesting=1 for Docker)
    • Root disk: ${DEFAULT_ROOTFS_SIZE}GB on NVMe (data pool)
    • Data mount: hdd-pool/container-data/nextcloud → /mnt/nextcloud-data
    • ZFS dataset created automatically with proper permissions
    • InfraStack + base packages + Zsh
    • Docker CE + Docker Compose plugin
    • Nextcloud (apache) + MariaDB 11 + Redis

Network:
    • Internal IP: 192.168.2.<ctid>
    • Nextcloud port 8080 bound to 127.0.0.1 only (proxy via NPM)
    • Public access via NPM CT200 → https://${NC_DOMAIN}

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

    create_nextcloud_container "$CTID" "$NAME" "$CORES" "$MEMORY" "$IP_SUFFIX"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi