#!/bin/bash
#=============================================================================
# InfraStack - Node.js Web App Container Deployment
# Part of InfraStack sysadmin infrastructure toolkit
#
# Description: Deploy a Node.js web application stack inside a Debian LXC.
#              Stack: DB in Docker (MariaDB or PostgreSQL) +
#                     Node/PM2 native + optional nginx for SPA frontend.
#              SSL/proxy via NPM (CT200).
#
# Usage: infrastack containers node-webapp -i <ctid> -n <name> [OPTIONS]
#
# Examples:
#   # SwissHub production — MariaDB, custom hostname, port 4001
#   infrastack containers node-webapp -i 150 -n swisshub-prod \
#     --hostname hub.swiss-net.com.ar \
#     --db-type mariadb --db-name swissnet_hub --app-port 4001
#
#   # NovaCast staging — PostgreSQL, default port
#   infrastack containers node-webapp -i 151 -n novacast-staging \
#     --hostname novacast-staging.tecnosoul.com.ar \
#     --db-type postgres --db-name novacast_staging
#
#   # API-only backend (no nginx)
#   infrastack containers node-webapp -i 152 -n myapi --no-nginx --app-port 8080
#
# Author: TecnoSoul
#=============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$INFRASTACK_ROOT/scripts/lib/common.sh"

#=============================================================================
# DEFAULTS
#=============================================================================

DEFAULT_CORES=2
DEFAULT_MEMORY=2048
DEFAULT_ROOTFS_SIZE=20
DEFAULT_NETWORK="192.168.2"
DEFAULT_GATEWAY="192.168.2.1"
DEFAULT_BRIDGE="vmbr1"

DEFAULT_NODE_VERSION=22
DEFAULT_DB_TYPE=mariadb
DEFAULT_APP_PORT=3000
DEFAULT_WITH_NGINX=true

MARIADB_IMAGE="mariadb:11"
POSTGRES_IMAGE="postgres:16"

DEBIAN_TEMPLATE="local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
NVM_VERSION="v0.40.3"

#=============================================================================
# MAIN DEPLOYMENT
#=============================================================================

create_node_webapp_container() {
    local ctid=$1
    local name=$2
    local cores=${3:-$DEFAULT_CORES}
    local memory=${4:-$DEFAULT_MEMORY}
    local ip_suffix=${5:-$ctid}
    local hostname=${6:-"${name}.tecnosoul.com.ar"}
    local db_type=${7:-$DEFAULT_DB_TYPE}
    local db_name=${8:-$name}
    local node_version=${9:-$DEFAULT_NODE_VERSION}
    local app_port=${10:-$DEFAULT_APP_PORT}
    local with_nginx=${11:-$DEFAULT_WITH_NGINX}

    local ip_address="${DEFAULT_NETWORK}.${ip_suffix}"
    local swap=$((memory / 2))
    local app_path="/opt/${name}"

    log_info "Deploying Node.js Web App Container"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Container ID:    $ctid"
    echo "Name:            $name"
    echo "Hostname:        $hostname"
    echo "IP Address:      $ip_address"
    echo "CPU Cores:       $cores"
    echo "Memory:          ${memory}MB  (swap: ${swap}MB)"
    echo "Root disk:       ${DEFAULT_ROOTFS_SIZE}GB"
    echo "Stack:           Node ${node_version} LTS + PM2 (native)"
    echo "Database:        ${db_type} (Docker)"
    echo "DB name:         $db_name"
    echo "App port:        $app_port"
    echo "nginx (SPA):     $with_nginx"
    echo "App path:        $app_path"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if ! confirm_action "Proceed with container creation?" "y"; then
        log_info "Cancelled"
        return 1
    fi

    validate_ctid "$ctid"
    check_proxmox_version

    _create_lxc       "$ctid" "$name" "$hostname" "$ip_address" "$cores" "$memory" "$swap"
    _update_packages  "$ctid"
    _install_infrastack "$ctid"
    _set_timezone     "$ctid"
    _install_docker   "$ctid"
    _install_node     "$ctid" "$node_version"
    _install_pm2      "$ctid"

    if [[ "$with_nginx" == "true" ]]; then
        _install_nginx "$ctid" "$name" "$app_port"
    fi

    _setup_directories "$ctid" "$app_path"
    _write_db_compose  "$ctid" "$app_path" "$db_type" "$db_name"

    _display_success "$ctid" "$hostname" "$ip_address" "$app_path" \
                     "$db_type" "$db_name" "$node_version" "$app_port" "$with_nginx"
}

#=============================================================================
# STEP: CREATE LXC
#=============================================================================

_create_lxc() {
    local ctid=$1 name=$2 hostname=$3 ip_address=$4 cores=$5 memory=$6 swap=$7

    log_step "Creating LXC container"
    pct create "$ctid" "$DEBIAN_TEMPLATE" \
        --hostname "$hostname" \
        --description "Node.js Web App — $name" \
        --cores "$cores" \
        --memory "$memory" \
        --swap "$swap" \
        --rootfs "data:${DEFAULT_ROOTFS_SIZE}" \
        --unprivileged 1 \
        --features "nesting=1" \
        --net0 "name=eth0,bridge=${DEFAULT_BRIDGE},ip=${ip_address}/24,gw=${DEFAULT_GATEWAY}" \
        --nameserver 8.8.8.8 \
        --searchdomain tecnosoul.com.ar \
        --ostype debian \
        --start 0

    log_step "Starting container"
    pct start "$ctid"
    _wait_for_container "$ctid"
    log_success "Container $ctid is running"
}

#=============================================================================
# STEP: SYSTEM PACKAGES
#=============================================================================

_update_packages() {
    local ctid=$1
    log_step "Updating system packages"
    pct exec "$ctid" -- bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -q
        apt-get dist-upgrade -y -q
    '
    log_success "System packages up to date"
}

#=============================================================================
# STEP: INFRASTACK
#=============================================================================

_install_infrastack() {
    local ctid=$1
    log_step "Installing InfraStack + base packages + Zsh"
    pct exec "$ctid" -- bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y -q git
        cd /root
        git clone --quiet https://github.com/TecnoSoul/InfraStack.git
        cd InfraStack && ./install.sh
    '
    pct exec "$ctid" -- infrastack setup base
    pct exec "$ctid" -- infrastack setup zsh root
    log_success "InfraStack installed"
}

#=============================================================================
# STEP: TIMEZONE
#=============================================================================

_set_timezone() {
    local ctid=$1
    log_step "Configuring timezone"
    pct exec "$ctid" -- timedatectl set-timezone America/Argentina/Buenos_Aires
    log_success "Timezone set to America/Argentina/Buenos_Aires"
}

#=============================================================================
# STEP: DOCKER
#=============================================================================

_install_docker() {
    local ctid=$1
    log_step "Installing Docker CE + Compose plugin"
    pct exec "$ctid" -- bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y -q ca-certificates curl gnupg lsb-release
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg \
            -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
            > /etc/apt/sources.list.d/docker.list
        apt-get update -q
        apt-get install -y -q \
            docker-ce docker-ce-cli containerd.io docker-compose-plugin
        systemctl enable docker
        systemctl start docker
    '
    log_success "Docker CE installed"
}

#=============================================================================
# STEP: nvm + NODE
#=============================================================================

_install_node() {
    local ctid=$1
    local node_version=$2
    log_step "Installing nvm ${NVM_VERSION} + Node ${node_version} LTS"

    pct exec "$ctid" -- bash -c "
        curl -fsSLo /tmp/nvm-install.sh \
            https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh
        bash /tmp/nvm-install.sh
        rm /tmp/nvm-install.sh
        export NVM_DIR=\"/root/.nvm\"
        source \"\$NVM_DIR/nvm.sh\"
        nvm install ${node_version}
        nvm alias default ${node_version}
        nvm use default
        echo \"Node version: \$(node --version)\"
        echo \"npm version:  \$(npm --version)\"
    "

    # Ensure nvm is available in non-interactive shells (CI/PM2 won't source .bashrc)
    pct exec "$ctid" -- bash -c '
        # Add to .profile so non-interactive login shells load it
        cat >> /root/.profile << '"'"'PROFILE'"'"'

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
PROFILE
    '
    log_success "Node ${node_version} LTS installed via nvm"
}

#=============================================================================
# STEP: PM2
#=============================================================================

_install_pm2() {
    local ctid=$1
    log_step "Installing PM2 + systemd startup"

    pct exec "$ctid" -- bash -c '
        export NVM_DIR="/root/.nvm"
        source "$NVM_DIR/nvm.sh"
        npm install -g pm2

        # Register PM2 with systemd so it restarts on reboot
        # pm2 startup prints the command to run; pipe last line to bash
        pm2 startup systemd -u root --hp /root 2>&1 \
            | grep "sudo env" | bash || true
        systemctl enable pm2-root 2>/dev/null || true
    '
    log_success "PM2 installed with systemd startup"
}

#=============================================================================
# STEP: NGINX (optional — for SPA static frontend)
#=============================================================================

_install_nginx() {
    local ctid=$1
    local name=$2
    local app_port=$3
    log_step "Installing nginx for SPA static frontend"

    pct exec "$ctid" -- bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y -q nginx
        rm -f /etc/nginx/sites-enabled/default
        systemctl enable nginx
    '

    # Generate nginx site config on host, push to container
    local tmp_nginx="/tmp/infrastack-${ctid}-nginx.conf"
    cat > "$tmp_nginx" << NGINXCONF
server {
    listen 80;
    server_name _;

    root /opt/${name}/public;
    index index.html;

    # API — reverse proxy to PM2
    location /api/ {
        proxy_pass         http://127.0.0.1:${app_port};
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 60s;
    }

    # SPA fallback — all other routes serve index.html
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
NGINXCONF

    pct push "$ctid" "$tmp_nginx" "/etc/nginx/sites-available/${name}"
    rm -f "$tmp_nginx"

    pct exec "$ctid" -- bash -c "
        ln -sf /etc/nginx/sites-available/${name} /etc/nginx/sites-enabled/${name}
        nginx -t && systemctl start nginx
    "
    log_success "nginx configured (site: ${name})"
}

#=============================================================================
# STEP: DIRECTORY STRUCTURE
#=============================================================================

_setup_directories() {
    local ctid=$1
    local app_path=$2
    log_step "Creating directory structure at ${app_path}"

    pct exec "$ctid" -- bash -c "
        mkdir -p ${app_path}/{app,docker,public,logs}
        chmod 750 ${app_path}
    "
    log_success "Directories created"
}

#=============================================================================
# STEP: DB DOCKER COMPOSE
#=============================================================================

_write_db_compose() {
    local ctid=$1
    local app_path=$2
    local db_type=$3
    local db_name=$4

    log_step "Writing docker-compose.yml for ${db_type}"

    local tmp_compose="/tmp/infrastack-${ctid}-compose.yml"
    local tmp_env="/tmp/infrastack-${ctid}-env.example"

    if [[ "$db_type" == "mariadb" ]]; then
        cat > "$tmp_compose" << COMPOSE
# DB-only compose — application runs natively via PM2
# Start:   docker compose up -d
# Stop:    docker compose down
# Logs:    docker compose logs -f db
services:
  db:
    image: ${MARIADB_IMAGE}
    restart: unless-stopped
    env_file: .env
    environment:
      MARIADB_ROOT_PASSWORD: \${DB_ROOT_PASSWORD}
      MARIADB_DATABASE:      \${DB_NAME}
      MARIADB_USER:          \${DB_USER}
      MARIADB_PASSWORD:      \${DB_PASSWORD}
    volumes:
      - db_data:/var/lib/mysql
    ports:
      - "127.0.0.1:3306:3306"
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  db_data:
COMPOSE

        cat > "$tmp_env" << ENV
DB_ROOT_PASSWORD=change_me_root
DB_NAME=${db_name}
DB_USER=appuser
DB_PASSWORD=change_me_app
ENV

    else
        cat > "$tmp_compose" << COMPOSE
# DB-only compose — application runs natively via PM2
# Start:   docker compose up -d
# Stop:    docker compose down
# Logs:    docker compose logs -f db
services:
  db:
    image: ${POSTGRES_IMAGE}
    restart: unless-stopped
    env_file: .env
    environment:
      POSTGRES_DB:       \${DB_NAME}
      POSTGRES_USER:     \${DB_USER}
      POSTGRES_PASSWORD: \${DB_PASSWORD}
    volumes:
      - db_data:/var/lib/postgresql/data
    ports:
      - "127.0.0.1:5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  db_data:
COMPOSE

        cat > "$tmp_env" << ENV
DB_NAME=${db_name}
DB_USER=appuser
DB_PASSWORD=change_me_app
ENV
    fi

    pct push "$ctid" "$tmp_compose" "${app_path}/docker/docker-compose.yml"
    pct push "$ctid" "$tmp_env"     "${app_path}/docker/.env.example"
    rm -f "$tmp_compose" "$tmp_env"

    log_success "docker-compose.yml written to ${app_path}/docker/"
    log_warn "Don't forget: cp ${app_path}/docker/.env.example ${app_path}/docker/.env and set passwords"
}

#=============================================================================
# WAIT FOR CONTAINER READY
#=============================================================================

_wait_for_container() {
    local ctid=$1
    local max_wait=60
    local count=0

    log_info "Waiting for container to be ready..."
    while [[ $count -lt $max_wait ]]; do
        if pct exec "$ctid" -- systemctl is-system-running 2>/dev/null \
                | grep -qE "running|degraded"; then
            log_success "Container is ready"
            return 0
        fi
        sleep 2
        ((count+=2))
        echo -n "."
    done
    echo ""
    log_warn "Container may not be fully ready — continuing anyway"
}

#=============================================================================
# SUCCESS DISPLAY
#=============================================================================

_display_success() {
    local ctid=$1 hostname=$2 ip=$3 app_path=$4
    local db_type=$5 db_name=$6 node_version=$7 app_port=$8 with_nginx=$9

    local proxy_target
    if [[ "$with_nginx" == "true" ]]; then
        proxy_target="http://${ip}:80  (nginx serves SPA + proxies /api)"
    else
        proxy_target="http://${ip}:${app_port}  (PM2 direct)"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Node.js Web App Container Ready!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Container:   $ctid  ($hostname)"
    echo "  IP:          $ip"
    echo "  Stack:       Node ${node_version} LTS + PM2 + ${db_type} (Docker)"
    echo ""
    echo "Next steps:"
    echo ""
    echo "  1. Set DB credentials:"
    echo "       cp ${app_path}/docker/.env.example ${app_path}/docker/.env"
    echo "       vim ${app_path}/docker/.env"
    echo ""
    echo "  2. Start the database:"
    echo "       cd ${app_path}/docker && docker compose up -d"
    echo "       docker compose logs -f db   # verify healthy"
    echo ""
    echo "  3. Clone your app and configure PM2:"
    echo "       git clone <repo> ${app_path}/app"
    echo "       # write ecosystem.config.js with production env vars"
    echo "       source ~/.nvm/nvm.sh && pm2 start ecosystem.config.js"
    echo "       pm2 save"
    echo ""
    echo "  4. Run DB migrations:"
    echo "       # MariaDB example:"
    echo "       mysql -h 127.0.0.1 -u appuser -p ${db_name} < migrations/0001_*.sql"
    echo ""
    echo "  5. Add NPM proxy host:"
    echo "       ${hostname} → ${proxy_target}"
    echo "       Enable SSL (Let's Encrypt)"
    echo ""
    echo "  6. Add GitHub Actions secrets for this environment:"
    echo "       SSH_HOST=${ip}  SSH_USER=root  SSH_PORT=22"
    echo "       DEPLOY_PATH=${app_path}/app"
    echo "       DB_USER=appuser  DB_PASS=<from .env>"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

#=============================================================================
# HELP
#=============================================================================

show_help() {
    cat << EOF
InfraStack — Node.js Web App Container Deployment

Usage: $0 [OPTIONS]

Required:
    -i, --ctid ID               Container ID (100–999999)
    -n, --name NAME             App name — used for hostname, paths, DB name

Resources:
    -c, --cores NUM             CPU cores             (default: ${DEFAULT_CORES})
    -m, --memory MB             RAM in MB             (default: ${DEFAULT_MEMORY})
    -p, --ip-suffix NUM         Last octet of IP      (default: same as CTID)

Identity:
    --hostname FQDN             Custom hostname        (default: <name>.tecnosoul.com.ar)

Stack:
    --db-type mariadb|postgres  Database engine        (default: ${DEFAULT_DB_TYPE})
    --db-name NAME              Database name          (default: same as --name)
    --node-version NUM          Node.js LTS version    (default: ${DEFAULT_NODE_VERSION})
    --app-port PORT             PM2 listen port        (default: ${DEFAULT_APP_PORT})
    --no-nginx                  Skip nginx install     (for API-only backends)

Other:
    -h, --help                  Show this help

Examples:
    # SwissHub production
    $0 -i 150 -n swisshub-prod \\
        --hostname hub.swiss-net.com.ar \\
        --db-type mariadb --db-name swissnet_hub --app-port 4001

    # NovaCast staging
    $0 -i 151 -n novacast-staging \\
        --db-type postgres --db-name novacast_staging

    # API-only (no static frontend)
    $0 -i 152 -n myapi --no-nginx --app-port 8080

What gets installed:
    • Debian 13 LXC (unprivileged, nesting=1)
    • InfraStack + base sysadmin packages + Zsh
    • Docker CE + Compose plugin
    • nvm ${NVM_VERSION} + Node <version> LTS
    • PM2 (global, systemd startup)
    • nginx with SPA config (skipped with --no-nginx)
    • docker-compose.yml for MariaDB or PostgreSQL
    • /opt/<name>/{app,docker,public,logs} directory structure

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
    CUSTOM_HOSTNAME=""
    DB_TYPE=$DEFAULT_DB_TYPE
    DB_NAME=""
    NODE_VERSION=$DEFAULT_NODE_VERSION
    APP_PORT=$DEFAULT_APP_PORT
    WITH_NGINX="true"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--ctid)          CTID="$2";           shift 2 ;;
            -n|--name)          NAME="$2";            shift 2 ;;
            -c|--cores)         CORES="$2";           shift 2 ;;
            -m|--memory)        MEMORY="$2";          shift 2 ;;
            -p|--ip-suffix)     IP_SUFFIX="$2";       shift 2 ;;
            --hostname)         CUSTOM_HOSTNAME="$2"; shift 2 ;;
            --db-type)          DB_TYPE="$2";         shift 2 ;;
            --db-name)          DB_NAME="$2";         shift 2 ;;
            --node-version)     NODE_VERSION="$2";    shift 2 ;;
            --app-port)         APP_PORT="$2";        shift 2 ;;
            --no-nginx)         WITH_NGINX="false";   shift ;;
            -h|--help)          show_help ;;
            *)                  log_error "Unknown option: $1"; show_help ;;
        esac
    done

    [[ -z "$CTID" || -z "$NAME" ]] && {
        log_error "--ctid and --name are required"
        show_help
    }

    if [[ "$DB_TYPE" != "mariadb" && "$DB_TYPE" != "postgres" ]]; then
        die "Invalid --db-type '${DB_TYPE}': must be mariadb or postgres"
    fi

    DB_NAME="${DB_NAME:-$NAME}"
    IP_SUFFIX="${IP_SUFFIX:-$CTID}"
    CUSTOM_HOSTNAME="${CUSTOM_HOSTNAME:-${NAME}.tecnosoul.com.ar}"

    check_root

    create_node_webapp_container \
        "$CTID" "$NAME" "$CORES" "$MEMORY" "$IP_SUFFIX" \
        "$CUSTOM_HOSTNAME" "$DB_TYPE" "$DB_NAME" \
        "$NODE_VERSION" "$APP_PORT" "$WITH_NGINX"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

export -f create_node_webapp_container