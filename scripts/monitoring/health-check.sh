#!/bin/bash
#=============================================================================
# InfraStack - Server Health Check
# Part of InfraStack sysadmin infrastructure toolkit
#
# Description: Basic server health monitoring and reporting
# Usage: infrastack health check
# Author: TecnoSoul
#
# Exit codes:
#   0 - Healthy (all checks passed)
#   1 - Warnings (some issues detected)
#   2 - Critical (serious issues detected)
#=============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

#=============================================================================
# CONFIGURATION
#=============================================================================

# Thresholds
DISK_WARNING_THRESHOLD=80
DISK_CRITICAL_THRESHOLD=90
MEMORY_WARNING_THRESHOLD=80
LOAD_WARNING_MULTIPLIER=1.5

# Critical services to check
CRITICAL_SERVICES=("ssh")

# Optional services (won't affect exit code if not installed)
OPTIONAL_SERVICES=("nginx" "apache2" "mysql" "mariadb" "postgresql")

#=============================================================================
# GLOBAL STATE
#=============================================================================

HAS_WARNINGS=0
HAS_CRITICAL=0

#=============================================================================
# FUNCTIONS
#=============================================================================

# Check disk usage
check_disk() {
    log_step "Disk Usage"

    # Get all mounted filesystems (excluding tmpfs, devtmpfs)
    df -h -x tmpfs -x devtmpfs | tail -n +2 | while read -r filesystem size used avail use_percent mountpoint; do
        # Remove % from use_percent
        local use_num="${use_percent%\%}"

        # Display filesystem info
        echo "  $mountpoint: $used / $size ($use_percent)"

        # Check thresholds
        if [[ $use_num -ge $DISK_CRITICAL_THRESHOLD ]]; then
            log_error "  CRITICAL: Disk usage at ${use_percent} on $mountpoint"
            HAS_CRITICAL=1
        elif [[ $use_num -ge $DISK_WARNING_THRESHOLD ]]; then
            log_warn "  WARNING: Disk usage at ${use_percent} on $mountpoint"
            HAS_WARNINGS=1
        fi
    done

    echo ""
}

# Check memory usage
check_memory() {
    log_step "Memory Usage"

    # Get memory info
    local mem_total mem_available mem_used mem_percent

    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_used=$((mem_total - mem_available))
    mem_percent=$((mem_used * 100 / mem_total))

    # Convert to human readable
    local mem_total_mb=$((mem_total / 1024))
    local mem_used_mb=$((mem_used / 1024))
    local mem_available_mb=$((mem_available / 1024))

    echo "  Total: ${mem_total_mb} MB"
    echo "  Used:  ${mem_used_mb} MB (${mem_percent}%)"
    echo "  Free:  ${mem_available_mb} MB"

    # Check threshold
    if [[ $mem_percent -ge $MEMORY_WARNING_THRESHOLD ]]; then
        log_warn "  WARNING: High memory usage (${mem_percent}%)"
        HAS_WARNINGS=1
    fi

    echo ""
}

# Check load average
check_load() {
    log_step "Load Average"

    # Get number of CPU cores
    local cpu_cores
    cpu_cores=$(nproc)

    # Get load averages
    local load_1min load_5min load_15min
    read -r load_1min load_5min load_15min _ < /proc/loadavg

    echo "  CPUs: $cpu_cores"
    echo "  Load: $load_1min (1m), $load_5min (5m), $load_15min (15m)"

    # Check if 1-minute load is high
    local load_threshold
    load_threshold=$(echo "$cpu_cores * $LOAD_WARNING_MULTIPLIER" | bc)

    if (( $(echo "$load_1min > $load_threshold" | bc -l) )); then
        log_warn "  WARNING: High load average ($load_1min > $load_threshold)"
        HAS_WARNINGS=1
    fi

    echo ""
}

# Check service status
check_service() {
    local service=$1
    local is_critical=${2:-false}

    if systemctl list-unit-files | grep -q "^${service}.service"; then
        if systemctl is-active --quiet "$service"; then
            echo -e "  ${GREEN}✓${NC} $service - running"
        else
            if [[ "$is_critical" == "true" ]]; then
                echo -e "  ${RED}✗${NC} $service - ${RED}NOT RUNNING${NC}"
                HAS_CRITICAL=1
            else
                echo -e "  ${YELLOW}!${NC} $service - ${YELLOW}not running${NC}"
                HAS_WARNINGS=1
            fi
        fi
    else
        if [[ "$is_critical" == "true" ]]; then
            echo -e "  ${RED}✗${NC} $service - ${RED}not installed${NC}"
            HAS_CRITICAL=1
        fi
    fi
}

# Check services
check_services() {
    log_step "Service Status"

    # Check critical services
    for service in "${CRITICAL_SERVICES[@]}"; do
        check_service "$service" "true"
    done

    # Check optional services
    for service in "${OPTIONAL_SERVICES[@]}"; do
        check_service "$service" "false"
    done

    echo ""
}

# Check uptime
check_uptime() {
    log_step "System Uptime"

    local uptime_seconds
    uptime_seconds=$(awk '{print int($1)}' /proc/uptime)

    local days=$((uptime_seconds / 86400))
    local hours=$(((uptime_seconds % 86400) / 3600))
    local minutes=$(((uptime_seconds % 3600) / 60))

    echo "  ${days}d ${hours}h ${minutes}m"
    echo ""
}

# Show header
show_header() {
    local hostname
    hostname=$(hostname -f 2>/dev/null || hostname)

    cat << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
InfraStack - Server Health Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Hostname: $hostname
Date:     $(date '+%Y-%m-%d %H:%M:%S %Z')

EOF
}

# Show summary
show_summary() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ $HAS_CRITICAL -eq 1 ]]; then
        log_error "CRITICAL: Server has critical issues"
        return 2
    elif [[ $HAS_WARNINGS -eq 1 ]]; then
        log_warn "WARNING: Server has warnings"
        return 1
    else
        log_success "HEALTHY: All checks passed"
        return 0
    fi
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    show_header

    # Run checks
    check_uptime
    check_disk
    check_memory
    check_load
    check_services

    # Show summary and exit with appropriate code
    show_summary
    local exit_code=$?

    exit $exit_code
}

# Execute main function
main "$@"
