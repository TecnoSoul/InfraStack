#!/bin/bash
#=============================================================================
# InfraStack Radio Module - Logs Tool
# Part of InfraStack sysadmin infrastructure toolkit
# https://github.com/TecnoSoul/InfraStack
#
# Originally from RadioStack - migrated during integration
#
# This script displays logs for radio containers
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

# Source platform scripts
# shellcheck disable=SC1091
source "$INFRASTACK_ROOT/scripts/radio/platforms/azuracast.sh"
# shellcheck disable=SC1091
source "$INFRASTACK_ROOT/scripts/radio/platforms/libretime.sh"

#=============================================================================
# LOGS FUNCTIONS
#=============================================================================

# Function: show_container_logs
# Purpose: Display logs for a container
show_container_logs() {
    local ctid=$1
    local log_type=${2:-application}
    local lines=${3:-50}

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    init_inventory
    local platform_type
    if [[ -f "$INVENTORY_FILE" ]]; then
        platform_type=$(grep "^${ctid}," "$INVENTORY_FILE" | cut -d',' -f2)
    fi

    case "$log_type" in
        container)
            show_lxc_logs "$ctid" "$lines"
            ;;
        application)
            if [[ -z "$platform_type" ]]; then
                log_error "Platform type unknown, cannot show application logs"
                return 1
            fi
            show_application_logs "$ctid" "$platform_type" "$lines"
            ;;
        both)
            show_lxc_logs "$ctid" "$lines"
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            show_application_logs "$ctid" "$platform_type" "$lines"
            ;;
        *)
            log_error "Unknown log type: $log_type"
            return 1
            ;;
    esac

    return 0
}

# Function: show_lxc_logs
# Purpose: Display LXC container logs
show_lxc_logs() {
    local ctid=$1
    local lines=${2:-50}

    log_info "Container logs for $ctid (last $lines lines):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if pct exec "$ctid" -- journalctl -n "$lines" --no-pager 2>/dev/null; then
        :
    else
        log_warn "Unable to retrieve container logs"
    fi

    return 0
}

# Function: show_application_logs
# Purpose: Display application-specific logs
show_application_logs() {
    local ctid=$1
    local platform_type=$2
    local lines=${3:-50}

    log_info "$platform_type application logs:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    case "$platform_type" in
        azuracast)
            get_azuracast_logs "$ctid"
            ;;
        libretime)
            get_libretime_logs "$ctid"
            ;;
        *)
            log_warn "No log viewer available for platform: $platform_type"
            ;;
    esac

    return 0
}

# Function: follow_logs
# Purpose: Follow logs in real-time
follow_logs() {
    local ctid=$1
    local log_type=${2:-application}

    if [[ -z "$ctid" ]]; then
        log_error "Container ID is required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    log_info "Following logs for container $ctid (press Ctrl+C to stop)..."
    echo ""

    case "$log_type" in
        container)
            pct exec "$ctid" -- journalctl -f --no-pager
            ;;
        application)
            init_inventory
            local platform_type
            if [[ -f "$INVENTORY_FILE" ]]; then
                platform_type=$(grep "^${ctid}," "$INVENTORY_FILE" | cut -d',' -f2)
            fi

            case "$platform_type" in
                azuracast)
                    pct exec "$ctid" -- bash -c 'cd /var/azuracast && ./docker.sh logs -f'
                    ;;
                libretime)
                    pct exec "$ctid" -- docker-compose -f /opt/libretime/docker-compose.yml logs -f
                    ;;
                *)
                    log_error "Unknown platform: $platform_type"
                    return 1
                    ;;
            esac
            ;;
        *)
            log_error "Unknown log type: $log_type"
            return 1
            ;;
    esac

    return 0
}

# Function: show_service_logs
# Purpose: Display logs for specific service within container
show_service_logs() {
    local ctid=$1
    local service_name=$2
    local lines=${3:-50}

    if [[ -z "$ctid" ]] || [[ -z "$service_name" ]]; then
        log_error "Container ID and service name are required"
        return 1
    fi

    if ! container_exists "$ctid"; then
        log_error "Container $ctid does not exist"
        return 1
    fi

    log_info "Logs for service '$service_name' in container $ctid:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    init_inventory
    local platform_type
    if [[ -f "$INVENTORY_FILE" ]]; then
        platform_type=$(grep "^${ctid}," "$INVENTORY_FILE" | cut -d',' -f2)
    fi

    case "$platform_type" in
        azuracast)
            pct exec "$ctid" -- bash -c "cd /var/azuracast && docker-compose logs --tail=$lines $service_name"
            ;;
        libretime)
            pct exec "$ctid" -- docker-compose -f /opt/libretime/docker-compose.yml logs --tail="$lines" "$service_name"
            ;;
        *)
            pct exec "$ctid" -- journalctl -u "$service_name" -n "$lines" --no-pager
            ;;
    esac

    return 0
}

#=============================================================================
# SCRIPT EXECUTION
#=============================================================================

show_help() {
    cat << EOF
InfraStack Radio Module - Logs Tool

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Container ID (required)
    -t, --type TYPE         Log type: container/application/both (default: application)
    -n, --lines NUM         Number of lines to show (default: 50)
    -f, --follow            Follow logs in real-time
    -s, --service NAME      Show logs for specific service
    -h, --help              Show this help message

Log Types:
    container               LXC container system logs
    application             Platform application logs (AzuraCast/LibreTime)
    both                    Both container and application logs

Examples:
    # Show application logs
    $0 --ctid 340

    # Show last 100 lines of container logs
    $0 --ctid 340 --type container --lines 100

    # Show both container and application logs
    $0 --ctid 340 --type both

    # Follow application logs in real-time
    $0 --ctid 340 --follow

    # Show logs for specific service
    $0 --ctid 350 --service libretime

    # Via InfraStack CLI
    infrastack radio logs --ctid 340
    infrastack radio logs --ctid 340 --follow

EOF
    exit 0
}

if [[ $# -eq 0 ]]; then
    show_help
fi

CTID=""
LOG_TYPE="application"
LINES=50
FOLLOW=false
SERVICE_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ctid)
            CTID="$2"
            shift 2
            ;;
        -t|--type)
            LOG_TYPE="$2"
            shift 2
            ;;
        -n|--lines)
            LINES="$2"
            shift 2
            ;;
        -f|--follow)
            FOLLOW=true
            shift
            ;;
        -s|--service)
            SERVICE_NAME="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

if [[ -z "$CTID" ]]; then
    log_error "Container ID is required"
    show_help
fi

if [[ -n "$SERVICE_NAME" ]]; then
    show_service_logs "$CTID" "$SERVICE_NAME" "$LINES"
elif [[ "$FOLLOW" == true ]]; then
    follow_logs "$CTID" "$LOG_TYPE"
else
    show_container_logs "$CTID" "$LOG_TYPE" "$LINES"
fi
