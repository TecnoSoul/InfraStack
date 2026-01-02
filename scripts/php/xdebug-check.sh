#!/bin/bash
#=============================================================================
# InfraStack - Xdebug Status Checker
# Part of InfraStack sysadmin infrastructure toolkit
#
# Description: Check Xdebug status across all installed PHP versions
# Usage: infrastack php xdebug-check [version]
# Author: TecnoSoul
#=============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

#=============================================================================
# FUNCTIONS
#=============================================================================

# Check Xdebug for a specific PHP version
check_php_version() {
    local version=$1
    local php_bin="/usr/bin/php${version}"
    local xdebug_installed=false
    local xdebug_enabled=false
    local xdebug_mode=""
    local xdebug_version=""

    echo ""
    log_step "PHP $version"

    # Check if PHP is installed
    if [[ ! -x "$php_bin" ]]; then
        log_warn "PHP $version not installed"
        return 1
    fi

    # Check if Xdebug is installed
    if $php_bin -m 2>/dev/null | grep -q "xdebug"; then
        xdebug_installed=true
        xdebug_enabled=true

        # Get Xdebug version
        xdebug_version=$($php_bin -v | grep -oP 'Xdebug v\K[0-9.]+' || echo "unknown")

        # Get Xdebug mode
        xdebug_mode=$($php_bin -i 2>/dev/null | grep "xdebug.mode" | head -1 | awk '{print $3}' || echo "not set")

        log_info "Xdebug $xdebug_version - ENABLED"
        echo "       Mode: $xdebug_mode"

        # Check CLI configuration
        local cli_ini="/etc/php/${version}/cli/conf.d/20-xdebug.ini"
        if [[ -f "$cli_ini" ]]; then
            echo "       CLI:  $cli_ini"
        fi

        # Check FPM configuration
        local fpm_ini="/etc/php/${version}/fpm/conf.d/20-xdebug.ini"
        if [[ -f "$fpm_ini" ]]; then
            echo "       FPM:  $fpm_ini"
        fi
    else
        # Check if Xdebug is installed but disabled
        local cli_ini="/etc/php/${version}/cli/conf.d/20-xdebug.ini"
        local fpm_ini="/etc/php/${version}/fpm/conf.d/20-xdebug.ini"

        if [[ -f "$cli_ini" ]] || [[ -f "$fpm_ini" ]]; then
            log_warn "Xdebug installed but DISABLED"
        else
            log_warn "Xdebug not installed"
        fi
    fi

    return 0
}

# Show summary header
show_header() {
    cat << 'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Xdebug Status Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# Show summary footer
show_footer() {
    cat << 'EOF'

Common Xdebug modes:
  • develop  - Development helpers
  • debug    - Step debugging
  • profile  - Profiling
  • trace    - Function trace
  • coverage - Code coverage

Manage Xdebug:
  • Toggle profiler: infrastack php xdebug-profile <on|off> [version]
  • Full audit:      infrastack php xdebug-audit [version]

EOF
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    local specific_version="${1:-}"

    show_header

    if [[ -n "$specific_version" ]]; then
        # Check specific version
        check_php_version "$specific_version"
    else
        # Detect and check all PHP versions
        local php_versions
        php_versions=($(detect_php_versions))

        if [[ ${#php_versions[@]} -eq 0 ]]; then
            log_error "No PHP installations detected"
            exit 1
        fi

        log_info "Detected PHP versions: ${php_versions[*]}"

        for version in "${php_versions[@]}"; do
            check_php_version "$version"
        done
    fi

    show_footer
}

# Execute main function
main "$@"
