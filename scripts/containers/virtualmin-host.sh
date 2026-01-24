#!/bin/bash
#=============================================================================
# InfraStack - Virtualmin Hosting Server Deployment
# Part of InfraStack sysadmin infrastructure toolkit
#
# Description: Deploy Virtualmin hosting servers with InfraStack
# Usage: infrastack containers virtualmin -i <ctid> -n <name>
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

# Default configuration for Virtualmin
DEFAULT_CORES=4
DEFAULT_MEMORY=4096
DEFAULT_ROOTFS_SIZE=32
DEFAULT_NETWORK="192.168.2"
DEFAULT_GATEWAY="192.168.2.1"
DEFAULT_BRIDGE="vmbr1"

#=============================================================================
# VIRTUALMIN DEPLOYMENT
#=============================================================================

# Function: deploy_virtualmin_host
# Purpose: Create Virtualmin hosting server
# Parameters:
#   $1 - ctid
#   $2 - name (e.g., "hosting3")
#   $3 - cores (optional)
#   $4 - memory (optional)
#   $5 - ip_suffix (optional)
deploy_virtualmin_host() {
    local ctid=$1
    local name=$2
    local cores=${3:-$DEFAULT_CORES}
    local memory=${4:-$DEFAULT_MEMORY}
    local ip_suffix=${5:-$ctid}

    local hostname="${name}.tecnosoul.com.ar"
    local ip_address="${DEFAULT_NETWORK}.${ip_suffix}"
    local swap=$((memory / 2))

    log_info "Deploying Virtualmin Hosting Server"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Container ID:    $ctid"
    echo "Name:            $name"
    echo "Hostname:        $hostname"
    echo "IP Address:      $ip_address"
    echo "CPU Cores:       $cores"
    echo "Memory:          ${memory}MB"
    echo "Type:            Privileged (required for Virtualmin)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_warn "This will create a PRIVILEGED container (required for Virtualmin)"
    echo ""

    # Confirm creation
    if ! confirm_action "Proceed with Virtualmin deployment?" "y"; then
        log_info "Deployment cancelled"
        return 1
    fi

    # Check if container exists
    if pct status "$ctid" &>/dev/null; then
        log_error "Container $ctid already exists"
        return 1
    fi

    # Create privileged container
    log_step "Creating privileged LXC container"
    pct create "$ctid" local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
        --hostname "$hostname" \
        --description "Virtualmin Hosting Server - $name" \
        --cores "$cores" \
        --memory "$memory" \
        --swap "$swap" \
        --rootfs data:$DEFAULT_ROOTFS_SIZE \
        --unprivileged 0 \
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

    # Setup Zsh
    log_step "Configuring Zsh with Oh My Zsh"
    pct exec "$ctid" -- infrastack setup zsh root

    # Set timezone
    log_step "Configuring timezone"
    pct exec "$ctid" -- timedatectl set-timezone America/Argentina/Buenos_Aires

    # Set proper hostname
    log_step "Configuring hostname"
    configure_hostname "$ctid" "$hostname" "$ip_address"

    # Install Virtualmin prerequisites
    log_step "Installing Virtualmin prerequisites"
    install_virtualmin_prereqs "$ctid"

    # Download Virtualmin installer
    log_step "Downloading Virtualmin installer"
    pct exec "$ctid" -- bash -c "
        cd /root
        wget https://software.virtualmin.com/gpl/scripts/virtualmin-install.sh
        chmod +x virtualmin-install.sh
    "

    # Display next steps
    display_virtualmin_next_steps "$ctid" "$hostname" "$ip_address"
    return 0
}

# Function: install_infrastack
# Purpose: Install InfraStack inside container
# Parameters:
#   $1 - ctid
install_infrastack() {
    local ctid=$1

    pct exec "$ctid" -- bash -c '
        apt-get install -y git

        cd /root
        if [[ -d InfraStack ]]; then
            cd InfraStack
            git pull
        else
            git clone https://github.com/TecnoSoul/InfraStack.git
            cd InfraStack
        fi

        ./install.sh
    '
}

# Function: configure_hostname
# Purpose: Properly configure hostname and /etc/hosts
# Parameters:
#   $1 - ctid
#   $2 - hostname
#   $3 - ip_address
configure_hostname() {
    local ctid=$1
    local hostname=$2
    local ip_address=$3

    pct exec "$ctid" -- bash -c "
        hostnamectl set-hostname $hostname

        cat > /etc/hosts << EOF
127.0.0.1       localhost
$ip_address     $hostname ${hostname%%.*}

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
    "
}

# Function: install_virtualmin_prereqs
# Purpose: Install required packages for Virtualmin
# Parameters:
#   $1 - ctid
install_virtualmin_prereqs() {
    local ctid=$1

    pct exec "$ctid" -- bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y wget curl perl libwww-perl apt-transport-https gnupg2
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

# Function: display_virtualmin_next_steps
# Purpose: Show instructions for completing Virtualmin installation
# Parameters:
#   $1 - ctid
#   $2 - hostname
#   $3 - ip_address
display_virtualmin_next_steps() {
    local ctid=$1
    local hostname=$2
    local ip_address=$3

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Virtualmin Host Container Ready!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Container Information:"
    echo "  CTID:           $ctid"
    echo "  Hostname:       $hostname"
    echo "  IP Address:     $ip_address"
    echo "  Type:           Privileged (Virtualmin requirement)"
    echo ""
    echo "Pre-installed:"
    echo "  ✓ InfraStack toolkit"
    echo "  ✓ Base sysadmin packages"
    echo "  ✓ Zsh with Oh My Zsh"
    echo "  ✓ Virtualmin prerequisites"
    echo "  ✓ Virtualmin installer downloaded"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "NEXT STEPS: Install Virtualmin"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Enter the container:"
    echo "   pct enter $ctid"
    echo ""
    echo "2. Run Virtualmin installer:"
    echo "   cd /root"
    echo "   ./virtualmin-install.sh --hostname $hostname"
    echo ""
    echo "   Important installer options:"
    echo "   - Choose LAMP (not LEMP)"
    echo "   - Enable BIND for DNS"
    echo "   - Enable Postfix for mail"
    echo "   - Choose MariaDB or MySQL"
    echo ""
    echo "3. After installation completes:"
    echo "   - Access: https://$ip_address:10000"
    echo "   - Complete web setup wizard"
    echo "   - Configure as ns3.tecnosoul.com.ar"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "DNS Configuration Required"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Before running Virtualmin installer, configure DNS:"
    echo ""
    echo "  $hostname.     A    $ip_address"
    echo "  ns3.tecnosoul.com.ar.   A    $ip_address"
    echo ""
    echo "Or use Proxmox host's public IP with port forwarding."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Post-Installation Tasks"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "• Join Virtualmin cluster with hosting1 and hosting2"
    echo "• Configure DNS cluster"
    echo "• Set up SSL certificates (Let's Encrypt or via NPM)"
    echo "• Configure mail server (if needed)"
    echo "• Migrate domains from old hosting3 (if applicable)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

#=============================================================================
# HELP AND USAGE
#=============================================================================

show_help() {
    cat << EOF
InfraStack - Virtualmin Hosting Server Deployment

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Container ID (required)
    -n, --name NAME         Server name (required, e.g., "hosting3")
    -c, --cores NUM         CPU cores (default: $DEFAULT_CORES)
    -m, --memory MB         Memory in MB (default: $DEFAULT_MEMORY)
    -p, --ip-suffix NUM     Last octet of IP (default: same as CTID)
    -h, --help              Show this help message

Examples:
    # Deploy hosting3
    $0 -i 103 -n hosting3

    # Custom resources for larger hosting
    $0 -i 103 -n hosting3 -c 8 -m 8192

What Gets Deployed:
    • Privileged LXC container (required for Virtualmin)
    • InfraStack toolkit pre-installed
    • Base sysadmin packages
    • Zsh with Oh My Zsh
    • Virtualmin prerequisites
    • Virtualmin installer ready to run

Why Privileged?
    Virtualmin requires a privileged container to properly manage:
    - System users and groups
    - Network configuration
    - Service management
    - Mail server configuration

Post-Deployment:
    You'll need to manually run the Virtualmin installer and
    complete the web-based setup wizard. Full instructions are
    displayed after container creation.

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

    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--ctid) CTID="$2"; shift 2 ;;
            -n|--name) NAME="$2"; shift 2 ;;
            -c|--cores) CORES="$2"; shift 2 ;;
            -m|--memory) MEMORY="$2"; shift 2 ;;
            -p|--ip-suffix) IP_SUFFIX="$2"; shift 2 ;;
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

    # Deploy container
    deploy_virtualmin_host "$CTID" "$NAME" "$CORES" "$MEMORY" "$IP_SUFFIX"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Export functions
export -f deploy_virtualmin_host install_infrastack configure_hostname