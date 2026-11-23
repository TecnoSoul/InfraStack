#!/bin/bash
#=============================================================================
# InfraStack - n8n-ai Container Deployment
# Part of InfraStack sysadmin infrastructure toolkit
#
# Description: Deploy the n8n-ai stack (stacks/n8n-ai) in an unprivileged LXC
#              Stack: n8n + external task runner + PostgreSQL (pgvector)
#              Data in Docker volumes on the NVMe root disk
#              Access via Cloudflare Tunnel + Access (--tunnel-token-file)
#              or via NPM (default)
#
# Usage: ./scripts/containers/n8n-ai.sh -i <ctid> -n <name> [OPTIONS]
# Example: ./scripts/containers/n8n-ai.sh -i 220 -n n8n
#
# Author: TecnoSoul
#=============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$INFRASTACK_ROOT/scripts/lib/common.sh"
load_container_defaults
source "$INFRASTACK_ROOT/scripts/lib/container.sh"

#=============================================================================
# CONFIGURATION DEFAULTS
#=============================================================================

DEFAULT_CORES=2
DEFAULT_MEMORY=2048
DEFAULT_ROOTFS_SIZE=20
DEFAULT_NETWORK="$CT_NETWORK"
DEFAULT_GATEWAY="$CT_GATEWAY"
DEFAULT_BRIDGE="$CT_BRIDGE"

STACK_SRC="$INFRASTACK_ROOT/stacks/n8n-ai"
# Stack lives outside the git checkout so .env never ends up in the repo
N8N_APP_PATH="/opt/n8n-ai"
N8N_PORT=5678
HEALTH_TIMEOUT=300

# Precedence: --domain, N8N_DOMAIN in infrastack.conf, <name>.<INFRASTACK_DOMAIN>
N8N_DOMAIN="${N8N_DOMAIN:-}"
# Empty = keep the version pinned in stacks/n8n-ai/.env.example
N8N_VERSION_OVERRIDE=""
# File with the Cloudflare Tunnel token; empty = NPM mode
TUNNEL_TOKEN_FILE=""

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

create_n8n_container() {
    local ctid=$1
    local name=$2
    local cores=${3:-$DEFAULT_CORES}
    local memory=${4:-$DEFAULT_MEMORY}
    local ip_suffix=${5:-$ctid}

    local hostname="${name}.${INFRASTACK_DOMAIN}"
    local ip_address="${DEFAULT_NETWORK}.${ip_suffix}"
    local swap=$((memory / 2))

    log_info "Deploying n8n-ai Container"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Container ID:    $ctid"
    echo "Hostname:        $hostname"
    echo "IP Address:      $ip_address"
    echo "CPU Cores:       $cores"
    echo "Memory:          ${memory}MB"
    echo "Root disk:       ${DEFAULT_ROOTFS_SIZE}GB on NVMe (${CT_ROOTFS_STORAGE})"
    echo "Domain:          ${N8N_DOMAIN}"
    echo "Stack:           n8n + task runner + PostgreSQL (pgvector)"
    if [[ -n "$TUNNEL_TOKEN_FILE" ]]; then
        echo "Access:          Cloudflare Tunnel (n8n bound to 127.0.0.1)"
    else
        echo "Access:          NPM reverse proxy (port ${N8N_PORT})"
    fi
    echo "App path:        ${N8N_APP_PATH}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if ! confirm_action "Proceed with n8n-ai deployment?" "y"; then
        log_info "Deployment cancelled"
        return 1
    fi

    if pct status "$ctid" &>/dev/null; then
        log_error "Container $ctid already exists"
        return 1
    fi

    # Step 1: Create LXC container
    log_step "Creating LXC container"
    pct create "$ctid" "$CT_TEMPLATE" \
        --hostname "$hostname" \
        --description "n8n-ai - ${N8N_DOMAIN}" \
        --cores "$cores" \
        --memory "$memory" \
        --swap "$swap" \
        --rootfs "${CT_ROOTFS_STORAGE}:${DEFAULT_ROOTFS_SIZE}" \
        --unprivileged 1 \
        --features "nesting=1,keyctl=1" \
        --net0 "name=eth0,bridge=${DEFAULT_BRIDGE},ip=${ip_address}/24,gw=${DEFAULT_GATEWAY}" \
        --nameserver "$CT_NAMESERVER" \
        --searchdomain "${INFRASTACK_DOMAIN:-${hostname#*.}}" \
        --ostype debian \
        --start 0

    # Step 2: Start container
    log_step "Starting container"
    pct start "$ctid"
    wait_for_container "$ctid"

    # Step 3: System setup
    log_step "Updating system packages"
    pct exec "$ctid" -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get dist-upgrade -y -qq
    "

    # Step 4: InfraStack
    log_step "Installing InfraStack"
    install_infrastack "$ctid"

    log_step "Installing base packages"
    pct exec "$ctid" -- infrastack setup base

    log_step "Configuring Zsh"
    pct exec "$ctid" -- infrastack setup zsh root

    # Step 5: Timezone
    log_step "Configuring timezone"
    pct exec "$ctid" -- timedatectl set-timezone America/Argentina/Buenos_Aires

    # Step 6: Docker
    install_docker "$ctid"

    # Step 7: Deploy the stack
    deploy_n8n_stack "$ctid"

    # Step 8: Save credentials on the Proxmox host
    save_credentials "$ctid"

    # Step 9: Summary
    display_n8n_summary "$ctid" "$hostname" "$ip_address"

    return 0
}

#=============================================================================
# DOCKER INSTALLATION
#=============================================================================

install_docker() {
    local ctid=$1

    log_step "Installing Docker"

    # shellcheck disable=SC2016  # expanded inside the container, not here
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
# STACK DEPLOYMENT
#=============================================================================

deploy_n8n_stack() {
    local ctid=$1

    log_step "Copying stack files to ${N8N_APP_PATH}"
    # Copy from this checkout (not from the clone inside the CT) so the stack
    # always matches the version of this script
    pct exec "$ctid" -- mkdir -p "$N8N_APP_PATH"
    tar -C "$STACK_SRC" --exclude=.env -cf - . | \
        pct exec "$ctid" -- tar -C "$N8N_APP_PATH" -xf -
    pct exec "$ctid" -- chmod +x "${N8N_APP_PATH}/init-data.sh" "${N8N_APP_PATH}/scripts/gen-env.sh"

    log_step "Generating .env with random secrets"
    if [[ -n "$TUNNEL_TOKEN_FILE" ]]; then
        # Token goes through stdin: never as an argument (visible in ps)
        pct exec "$ctid" -- "${N8N_APP_PATH}/scripts/gen-env.sh" \
            --host "$N8N_DOMAIN" --tunnel-token-file - < "$TUNNEL_TOKEN_FILE"
    else
        pct exec "$ctid" -- "${N8N_APP_PATH}/scripts/gen-env.sh" --host "$N8N_DOMAIN"
    fi

    if [[ -n "$N8N_VERSION_OVERRIDE" ]]; then
        pct exec "$ctid" -- sed -i "s|^N8N_VERSION=.*|N8N_VERSION=${N8N_VERSION_OVERRIDE}|" \
            "${N8N_APP_PATH}/.env"
    fi

    log_step "Starting n8n stack (first pull may take a few minutes)"
    pct exec "$ctid" -- bash -c "cd ${N8N_APP_PATH} && docker compose up -d"

    log_step "Waiting for n8n to become healthy (up to ${HEALTH_TIMEOUT}s)"
    local waited=0
    until pct exec "$ctid" -- curl -fsS "http://localhost:${N8N_PORT}/healthz" &>/dev/null; do
        if (( waited >= HEALTH_TIMEOUT )); then
            log_error "n8n did not become healthy in ${HEALTH_TIMEOUT}s"
            log_error "Check: pct exec ${ctid} -- bash -c 'cd ${N8N_APP_PATH} && docker compose logs n8n'"
            return 1
        fi
        sleep 5
        waited=$((waited + 5))
    done

    log_success "n8n stack is up"
}

save_credentials() {
    local ctid=$1
    local creds_file="/root/n8n-ai-credentials-ct${ctid}.txt"

    {
        echo "# n8n-ai Credentials - CT${ctid}"
        echo "# Generated: $(date)"
        echo "# KEEP THIS FILE SECURE — copy N8N_ENCRYPTION_KEY to Vaultwarden"
        echo "# Without N8N_ENCRYPTION_KEY a database backup cannot decrypt the stored credentials"
        echo ""
        echo "N8N_URL=https://${N8N_DOMAIN}"
        echo "N8N_APP_PATH=${N8N_APP_PATH}"
        pct exec "$ctid" -- grep -E '^(N8N_VERSION|N8N_ENCRYPTION_KEY|N8N_RUNNERS_AUTH_TOKEN|POSTGRES_[A-Z_]+|CLOUDFLARE_TUNNEL_TOKEN)=' \
            "${N8N_APP_PATH}/.env"
    } > "$creds_file"
    chmod 600 "$creds_file"

    log_info "Credentials saved to: $creds_file (on Proxmox host)"
}

#=============================================================================
# SUMMARY
#=============================================================================

display_n8n_summary() {
    local ctid=$1
    local hostname=$2
    local ip_address=$3

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "n8n-ai Deployed! CT${ctid}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Container:   CT${ctid} | ${hostname}"
    echo "  IP:          ${ip_address}"
    if [[ -n "$TUNNEL_TOKEN_FILE" ]]; then
        echo "  Internal:    http://127.0.0.1:${N8N_PORT} (solo dentro del CT)"
        echo "  Public:      https://${N8N_DOMAIN}  (after Cloudflare setup)"
    else
        echo "  Internal:    http://${ip_address}:${N8N_PORT}"
        echo "  Public:      https://${N8N_DOMAIN}  (after NPM setup)"
    fi
    echo "  Stack:       ${N8N_APP_PATH}"
    echo ""
    echo "  Credentials: /root/n8n-ai-credentials-ct${ctid}.txt"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "NEXT STEPS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Copiar N8N_ENCRYPTION_KEY del archivo de credenciales a Vaultwarden."
    echo ""
    if [[ -n "$TUNNEL_TOKEN_FILE" ]]; then
        echo "2. Cloudflare Zero Trust → Access → Applications → Add (Self-hosted):"
        echo "   Domain:        ${N8N_DOMAIN}"
        echo "   Policy:        Allow → Emails: los del equipo"
        echo "   Crear la aplicación de Access ANTES del paso 3, así el hostname"
        echo "   nunca queda publicado sin login."
        echo ""
        echo "3. Zero Trust → Networks → Tunnels → (este túnel) → Public hostname:"
        echo "   Hostname:      ${N8N_DOMAIN}"
        echo "   Service:       http://n8n:${N8N_PORT}"
        echo "   (Cloudflare crea el registro DNS solo)"
        echo ""
        echo "4. Abrir https://${N8N_DOMAIN}, pasar el login de Access y crear la"
        echo "   cuenta owner de n8n ENSEGUIDA. Activar 2FA."
        echo ""
        echo "5. Estado del túnel:"
        echo "   pct exec ${ctid} -- bash -c 'cd ${N8N_APP_PATH} && docker compose logs cloudflared'"
        echo ""
    else
        echo "2. DNS Record:"
        echo "   ${N8N_DOMAIN}.  A  ${PROXY_PUBLIC_IP}"
        echo ""
        echo "3. NPM - Add Proxy Host:"
        echo "   Domain:        ${N8N_DOMAIN}"
        echo "   Scheme:        http"
        echo "   Forward IP:    ${ip_address}"
        echo "   Forward Port:  ${N8N_PORT}"
        echo "   Websockets:    ✅ (required by the editor)"
        echo "   SSL:           Let's Encrypt + Force HTTPS"
        echo "   Access List:   solo las IPs del equipo"
        echo "   Advanced:      location /metrics { deny all; return 404; }"
        echo ""
        echo "4. Abrir https://${N8N_DOMAIN} y crear la cuenta owner ENSEGUIDA"
        echo "   (quien llegue primero se queda con la instancia). Activar 2FA."
        echo ""
        echo "5. Firewall: que al puerto ${N8N_PORT} del CT solo llegue ${PROXY_INTERNAL_IP} (NPM)."
        echo ""
    fi
    echo "6. Primer flujo: ver ${N8N_APP_PATH}/README.md (\"Flujo de juguete\")."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

#=============================================================================
# HELP
#=============================================================================

show_help() {
    cat << EOF
InfraStack - n8n-ai Container Deployment

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Container ID (required)
    -n, --name NAME         Container name, e.g. "n8n" (required)
    -c, --cores NUM         CPU cores (default: ${DEFAULT_CORES})
    -m, --memory MB         Memory in MB (default: ${DEFAULT_MEMORY})
    -p, --ip-suffix NUM     Last octet of IP (default: same as CTID)
    --domain FQDN           Public domain (default: N8N_DOMAIN or <name>.<INFRASTACK_DOMAIN>)
    --n8n-version VER       n8n image tag (default: pinned in stacks/n8n-ai/.env.example)
    --tunnel-token-file F   Use Cloudflare Tunnel; F holds the tunnel token (chmod 600).
                            Without it, access is via NPM.
    -h, --help              Show this help

Examples:
    $0 -i 220 -n n8n
    $0 -i 220 -n n8n --domain n8n.example.com --n8n-version 2.48.8
    $0 -i 220 -n n8n --domain n8n.example.com --tunnel-token-file /root/n8n-tunnel.token

What Gets Deployed:
    • Unprivileged LXC (nesting=1,keyctl=1 for Docker)
    • Root disk: ${DEFAULT_ROOTFS_SIZE}GB on NVMe
    • InfraStack + base packages + Zsh
    • Docker CE
    • stacks/n8n-ai → ${N8N_APP_PATH}: n8n + task runner + PostgreSQL (pgvector)
    • .env with random secrets; copy saved on the Proxmox host
    • With --tunnel-token-file: cloudflared container, n8n bound to 127.0.0.1

Resource footprint:
    • RAM: ~1-1.5GB idle (n8n + runner + Postgres)
    • Disk: grows with execution history (pruned after 14 days)

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
            --domain)       N8N_DOMAIN="$2"; shift 2 ;;
            --n8n-version)  N8N_VERSION_OVERRIDE="$2"; shift 2 ;;
            --tunnel-token-file) TUNNEL_TOKEN_FILE="$2"; shift 2 ;;
            -h|--help)      show_help ;;
            *) log_error "Unknown option: $1"; show_help ;;
        esac
    done

    if [[ -z "$CTID" ]] || [[ -z "$NAME" ]]; then
        log_error "Container ID and name are required"
        show_help
    fi

    check_root

    if [[ ! -f "$STACK_SRC/compose.yml" ]]; then
        die "Stack not found at $STACK_SRC"
    fi

    if [[ -n "$TUNNEL_TOKEN_FILE" && ! -s "$TUNNEL_TOKEN_FILE" ]]; then
        die "Tunnel token file not found or empty: $TUNNEL_TOKEN_FILE"
    fi

    require_config INFRASTACK_DOMAIN "used for the container hostname"
    N8N_DOMAIN="${N8N_DOMAIN:-${NAME}.${INFRASTACK_DOMAIN}}"

    create_n8n_container "$CTID" "$NAME" "$CORES" "$MEMORY" "$IP_SUFFIX"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
