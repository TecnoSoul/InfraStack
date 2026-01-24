#!/bin/bash
#=============================================================================
# InfraStack Radio Module - Status Tool
# Part of InfraStack sysadmin infrastructure toolkit
# https://github.com/TecnoSoul/InfraStack
#
# Originally from RadioStack - migrated during integration
#
# This script displays status information for radio containers
#=============================================================================

set -euo pipefail

# Get script directory and InfraStack root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTACK_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source library modules
# shellcheck disable=SC1091
source "$INFRASTACK_ROOT/scripts/lib/common.sh"
# shellcheck disable=SC1091
source "$INFRASTACK_ROOT/scripts/lib/container.sh"
# shellcheck disable=SC1091
source "$INFRASTACK_ROOT/scripts/lib/inventory.sh"

#=============================================================================
# STATUS FUNCTIONS
#=============================================================================

# Function: show_all_status
# Purpose: Display status of all radio containers
show_all_status() {
    init_inventory

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_warn "No inventory file found"
        return 0
    fi

    local total_count
    total_count=$(count_stations)

    if [[ $total_count -eq 0 ]]; then
        log_info "No stations found in inventory"
        return 0
    fi

    echo ""
    log_info "Radio Station Status ($total_count stations)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-6s %-12s %-20s %-17s %-10s\n" "CTID" "TYPE" "HOSTNAME" "IP" "STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    tail -n +2 "$INVENTORY_FILE" | while IFS=',' read -r ctid type hostname ip description created inv_status; do
        local status
        status=$(get_container_status "$ctid" 2>/dev/null || echo "unknown")

        # Color code status
        local status_display
        case "$status" in
            running)
                status_display="${GREEN}*${NC} running"
                ;;
            stopped)
                status_display="${YELLOW}*${NC} stopped"
                ;;
            not-found)
                status_display="${RED}*${NC} not-found"
                ;;
            *)
                status_display="${RED}*${NC} $status"
                ;;
        esac

        printf "%-6s %-12s %-20s %-17s %b\n" "$ctid" "$type" "$hostname" "$ip" "$status_display"
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

# Function: show_platform_status
# Purpose: Display status for specific platform type
show_platform_status() {
    local platform=$1

    if [[ -z "$platform" ]]; then
        log_error "Platform type is required"
        return 1
    fi

    init_inventory

    local count
    count=$(count_by_platform "$platform")

    if [[ $count -eq 0 ]]; then
        log_info "No $platform stations found"
        return 0
    fi

    echo ""
    log_info "$platform Container Status ($count stations)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-6s %-20s %-17s %-10s\n" "CTID" "HOSTNAME" "IP" "STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    grep -i "^[0-9]*,$platform," "$INVENTORY_FILE" 2>/dev/null | while IFS=',' read -r ctid type hostname ip rest; do
        local status
        status=$(get_container_status "$ctid" 2>/dev/null || echo "unknown")

        local status_display
        case "$status" in
            running)
                status_display="${GREEN}*${NC} running"
                ;;
            stopped)
                status_display="${YELLOW}*${NC} stopped"
                ;;
            not-found)
                status_display="${RED}*${NC} not-found"
                ;;
            *)
                status_display="${RED}*${NC} $status"
                ;;
        esac

        printf "%-6s %-20s %-17s %b\n" "$ctid" "$hostname" "$ip" "$status_display"
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

# Function: show_single_status
# Purpose: Display detailed status for a single container
show_single_status() {
    local ctid=$1

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    echo ""
    log_info "Detailed Status for Container $ctid"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local status
    status=$(get_container_status "$ctid")

    local ip
    ip=$(get_container_ip "$ctid" 2>/dev/null || echo "N/A")

    local hostname cores memory
    hostname=$(pct config "$ctid" | grep "^hostname:" | awk '{print $2}' || echo "N/A")
    cores=$(pct config "$ctid" | grep "^cores:" | awk '{print $2}' || echo "N/A")
    memory=$(pct config "$ctid" | grep "^memory:" | awk '{print $2}' || echo "N/A")

    echo "Container ID:   $ctid"
    echo "Hostname:       $hostname"
    echo "Status:         $status"
    echo "IP Address:     $ip"
    echo "CPU Cores:      $cores"
    echo "Memory:         ${memory}MB"
    echo ""

    if [[ -f "$INVENTORY_FILE" ]]; then
        get_station_info "$ctid" 2>/dev/null || true
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    return 0
}

#=============================================================================
# SCRIPT EXECUTION
#=============================================================================

show_help() {
    cat << EOF
InfraStack Radio Module - Status Tool

Usage: $0 [OPTIONS]

Options:
    -a, --all               Show status of all containers (default)
    -p, --platform TYPE     Show status for specific platform (azuracast/libretime)
    -i, --ctid ID           Show detailed status for specific container
    -h, --help              Show this help message

Examples:
    # Show all containers
    $0
    $0 --all

    # Show only AzuraCast containers
    $0 --platform azuracast

    # Show detailed info for specific container
    $0 --ctid 340

    # Via InfraStack CLI
    infrastack radio status
    infrastack radio status --platform azuracast
    infrastack radio status --ctid 340

EOF
    exit 0
}

MODE="all"
PLATFORM=""
CTID=""

if [[ $# -eq 0 ]]; then
    MODE="all"
else
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all) MODE="all"; shift ;;
            -p|--platform) MODE="platform"; PLATFORM="$2"; shift 2 ;;
            -i|--ctid) MODE="single"; CTID="$2"; shift 2 ;;
            -h|--help) show_help ;;
            *) log_error "Unknown option: $1"; show_help ;;
        esac
    done
fi

case "$MODE" in
    all)
        show_all_status
        ;;
    platform)
        if [[ -z "$PLATFORM" ]]; then
            log_error "Platform type is required"
            exit 1
        fi
        show_platform_status "$PLATFORM"
        ;;
    single)
        if [[ -z "$CTID" ]]; then
            log_error "Container ID is required"
            exit 1
        fi
        show_single_status "$CTID"
        ;;
esac
