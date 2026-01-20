#!/bin/bash
#=============================================================================
# InfraStack - Debian Base Container Deployment
# Part of InfraStack sysadmin infrastructure toolkit
#
# Description: Deploy Debian containers with InfraStack pre-installed
# Usage: infrastack containers debian-base -i <ctid> -n <name>
# Author: TecnoSoul
#=============================================================================

set -euo pipefail

# Get script directory and InfraStack root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common library
source "$INFRASTACK_ROOT/scripts/lib/common.sh"

#=============================================================================
# CONFIGURATION
#=============================================================================

# Default configuration
DEFAULT_CORES=2
DEFAULT_MEMORY=2048
DEFAULT_ROOTFS_SIZE=16
DEFAULT_NETWORK="192.168.2"
DEFAULT_GATEWAY="192.168.2.1"
DEFAULT_BRIDGE="vmbr1"

#=============================================================================
# CONTAINER MANAGEMENT
#=============================================================================

# Function: create_debian_base_container
# Purpose: Create Debian container with InfraStack pre-installed
# Parameters:
#   $1 - ctid
#   $2 - name
#   $3 - cores (optional)
#   $4 - memory (optional)
#   $5 - ip_suffix (optional)
#   $6 - privileged (optional, 0=unprivileged, 1=privileged)
create_debian_base_container() {
    local ctid=$1
    local name=$2
    local cores=${3:-$DEFAULT_CORES}
    local memory=${4:-$DEFAULT_MEMORY}
    local ip_suffix=${5:-$ctid}
    local privileged=${6:-0}

    local hostname="${name}.tecnosoul.com.ar"
    local ip_address="${DEFAULT_NETWORK}.${ip_suffix}"
    local swap=$((memory / 2))
    local unprivileged=1

    if [[ $privileged -eq 1 ]]; then
        unprivileged=0
    fi

    log_info "Creating Debian Base Container"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Container ID:    $ctid"
    echo "Name:            $name"
    echo "Hostname:        $hostname"
    echo "IP Address:      $ip_address"
    echo "CPU Cores:       $cores"
    echo "Memory:          ${memory}MB"
    echo "Privileged:      $([ $privileged -eq 1 ] && echo 'Yes' || echo 'No')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Confirm creation
    if ! confirm_action "Proceed with container creation?" "y"; then
        log_info "Container creation cancelled"
        return 1
    fi

    # Check if container exists
    if pct status "$ctid" &>/dev/null; then
        log_error "Container $ctid already exists"
        return 1
    fi

    # Create container
    log_step "Creating LXC container"
    pct create "$ctid" local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
        --hostname "$hostname" \
        --description "InfraStack Debian Base - $name" \
        --cores "$cores" \
        --memory "$memory" \
        --swap "$swap" \
        --rootfs data:$DEFAULT_ROOTFS_SIZE \
        --unprivileged $unprivileged \
        --features nesting=1 \
        --net0 name=eth0,bridge=$DEFAULT_BRIDGE,ip="${ip_address}/24",gw=$DEFAULT_GATEWAY \
        --nameserver 8.8.8.8 \
        --searchdomain tecnosoul.com.ar \
        --ostype debian \
        --start 0

    # Start container
    log_step "Starting container"
    pct start "$ctid"
    wait_for_container "$ctid"

    # Basic system setup
    log_step "Updating system packages"
    pct exec "$ctid" -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get dist-upgrade -y
    "

    # Install InfraStack
    log_step "Installing InfraStack"
    install_infrastack "$ctid"

    # Install base packages
    log_step "Installing base sysadmin packages"
    pct exec "$ctid" -- infrastack setup base

    # Setup Zsh for root
    log_step "Configuring Zsh with Oh My Zsh"
    pct exec "$ctid" -- infrastack setup zsh root

    # Set timezone
    log_step "Configuring timezone"
    pct exec "$ctid" -- timedatectl set-timezone America/Argentina/Buenos_Aires

    # Display success
    display_success "$ctid" "$hostname" "$ip_address"
    return 0
}

# Function: install_infrastack
# Purpose: Install InfraStack inside container
# Parameters:
#   $1 - ctid
install_infrastack() {
    local ctid=$1

    pct exec "$ctid" -- bash -c '
        # Install git if not present
        apt-get install -y git

        # Clone InfraStack
        cd /root
        if [[ -d InfraStack ]]; then
            cd InfraStack
            git pull
        else
            git clone https://github.com/TecnoSoul/InfraStack.git
            cd InfraStack
        fi

        # Run installer
        ./install.sh
    '
}

# Function: wait_for_container
# Purpose: Wait for container to be ready
# Parameters:
#   $1 - ctid
wait_for_container() {
    local ctid=$1
    local max_wait=60
    local count=0

    log_info "Waiting for container to be ready..."

    while [[ $count -lt $max_wait ]]; do
        if pct exec "$ctid" -- systemctl is-system-running --wait &>/dev/null; then
            log_success "Container is ready"
            return 0
        fi

        if pct exec "$ctid" -- systemctl is-system-running 2>/dev/null | grep -qE "running|degraded"; then
            log_success "Container is ready"
            return 0
        fi

        sleep 2
        ((count+=2))
        echo -n "."
    done

    echo ""
    log_warn "Container may not be fully ready, but continuing"
    return 0
}

# Function: display_success
# Purpose: Show success message
# Parameters:
#   $1 - ctid
#   $2 - hostname
#   $3 - ip_address
display_success() {
    local ctid=$1
    local hostname=$2
    local ip_address=$3

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Debian Base Container Created Successfully!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Container Information:"
    echo "  CTID:           $ctid"
    echo "  Hostname:       $hostname"
    echo "  IP Address:     $ip_address"
    echo ""
    echo "Access:"
    echo "  SSH:            ssh root@$ip_address"
    echo "  Console:        pct enter $ctid"
    echo ""
    echo "Installed Components:"
    echo "  ✓ InfraStack toolkit"
    echo "  ✓ Base sysadmin packages"
    echo "  ✓ Zsh with Oh My Zsh"
    echo "  ✓ System updates applied"
    echo ""
    echo "Quick Start:"
    echo "  pct enter $ctid"
    echo "  infrastack help"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

#=============================================================================
# HELP AND USAGE
#=============================================================================

show_help() {
    cat << EOF
InfraStack - Debian Base Container Deployment

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Container ID (required)
    -n, --name NAME         Container name (required)
    -c, --cores NUM         CPU cores (default: $DEFAULT_CORES)
    -m, --memory MB         Memory in MB (default: $DEFAULT_MEMORY)
    -p, --ip-suffix NUM     Last octet of IP (default: same as CTID)
    --privileged            Create privileged container (default: unprivileged)
    -h, --help              Show this help message

Examples:
    # Basic deployment
    $0 -i 100 -n utility

    # Custom resources
    $0 -i 101 -n monitoring -c 4 -m 4096

    # Privileged container (for Virtualmin)
    $0 -i 103 -n hosting3 -c 4 -m 4096 --privileged

What Gets Installed:
    • InfraStack toolkit (with all scripts and tools)
    • Base packages: vim, htop, curl, wget, git, tmux, etc.
    • Zsh with Oh My Zsh (Agnoster theme)
    • System updates
    • Proper timezone configuration

EOF
    exit 0
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    # Parse arguments
    CTID=""
    NAME=""
    CORES=$DEFAULT_CORES
    MEMORY=$DEFAULT_MEMORY
    IP_SUFFIX=""
    PRIVILEGED=0

    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--ctid) CTID="$2"; shift 2 ;;
            -n|--name) NAME="$2"; shift 2 ;;
            -c|--cores) CORES="$2"; shift 2 ;;
            -m|--memory) MEMORY="$2"; shift 2 ;;
            -p|--ip-suffix) IP_SUFFIX="$2"; shift 2 ;;
            --privileged) PRIVILEGED=1; shift ;;
            -h|--help) show_help ;;
            *) log_error "Unknown option: $1"; show_help ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$CTID" ]] || [[ -z "$NAME" ]]; then
        log_error "Container ID and name are required"
        show_help
    fi

    # Check root
    check_root

    # Create container
    create_debian_base_container "$CTID" "$NAME" "$CORES" "$MEMORY" "$IP_SUFFIX" "$PRIVILEGED"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Export functions
export -f create_debian_base_container install_infrastack