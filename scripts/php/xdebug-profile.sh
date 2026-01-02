#!/bin/bash
#=============================================================================
# InfraStack - Xdebug Profiler Toggle
# Part of InfraStack sysadmin infrastructure toolkit
#
# Description: Toggle Xdebug profiler mode on/off for PHP versions
# Usage: infrastack php xdebug-profile <on|off> [version]
# Author: TecnoSoul
#=============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

#=============================================================================
# FUNCTIONS
#=============================================================================

# Toggle Xdebug profiler for a specific PHP version
toggle_profiler() {
    local action=$1
    local version=$2
    local php_bin="/usr/bin/php${version}"

    log_step "PHP $version"

    # Check if PHP is installed
    if [[ ! -x "$php_bin" ]]; then
        log_warn "PHP $version not installed - skipping"
        return 1
    fi

    # Check if Xdebug is installed
    if ! $php_bin -m 2>/dev/null | grep -q "xdebug"; then
        log_warn "Xdebug not installed for PHP $version - skipping"
        return 1
    fi

    # Process CLI and FPM configurations
    local configs_updated=0

    for sapi in cli fpm; do
        local ini_file="/etc/php/${version}/${sapi}/conf.d/20-xdebug.ini"

        if [[ ! -f "$ini_file" ]]; then
            continue
        fi

        # Backup configuration
        cp "$ini_file" "${ini_file}.backup.$(date +%Y%m%d_%H%M%S)"

        if [[ "$action" == "on" ]]; then
            # Enable profiler mode
            if grep -q "^xdebug.mode" "$ini_file"; then
                # Update existing mode setting
                if ! grep "^xdebug.mode" "$ini_file" | grep -q "profile"; then
                    # Add profile to existing modes
                    sed -i 's/^xdebug.mode=\(.*\)/xdebug.mode=\1,profile/' "$ini_file"
                fi
            else
                # Add mode setting
                echo "xdebug.mode=develop,profile" >> "$ini_file"
            fi

            # Ensure output directory is set
            if ! grep -q "^xdebug.output_dir" "$ini_file"; then
                echo "xdebug.output_dir=/tmp/xdebug" >> "$ini_file"
                mkdir -p /tmp/xdebug
                chmod 777 /tmp/xdebug
            fi

            log_info "Enabled profiler for ${sapi^^}"
            configs_updated=$((configs_updated + 1))
        else
            # Disable profiler mode
            if grep -q "^xdebug.mode.*profile" "$ini_file"; then
                # Remove profile from mode
                sed -i 's/,profile//g; s/profile,//g; s/^xdebug.mode=profile$/xdebug.mode=develop/' "$ini_file"
                log_info "Disabled profiler for ${sapi^^}"
                configs_updated=$((configs_updated + 1))
            else
                log_info "Profiler already disabled for ${sapi^^}"
            fi
        fi
    done

    # Restart PHP-FPM if configuration was updated
    if [[ $configs_updated -gt 0 ]]; then
        if systemctl is-active --quiet "php${version}-fpm" 2>/dev/null; then
            log_step "Restarting PHP ${version} FPM"
            systemctl restart "php${version}-fpm"
            log_success "PHP $version FPM restarted"
        fi
    fi

    return 0
}

# Show usage
show_usage() {
    cat << 'EOF'
Usage: infrastack php xdebug-profile <on|off> [version]

Toggle Xdebug profiler mode for PHP installations.

Arguments:
  <on|off>   Enable or disable profiler mode
  [version]  Specific PHP version (e.g., 8.2) - optional

Examples:
  infrastack php xdebug-profile on          # Enable for all versions
  infrastack php xdebug-profile off         # Disable for all versions
  infrastack php xdebug-profile on 8.2      # Enable for PHP 8.2 only

Notes:
  • Profile files are stored in /tmp/xdebug/
  • FPM service is automatically restarted
  • Original configs are backed up before modification

EOF
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    local action="${1:-}"
    local specific_version="${2:-}"

    # Validate action
    if [[ -z "$action" ]] || [[ ! "$action" =~ ^(on|off)$ ]]; then
        log_error "Invalid action. Must be 'on' or 'off'"
        echo ""
        show_usage
        exit 1
    fi

    log_info "InfraStack - Xdebug Profiler Toggle"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Action: $(echo "$action" | tr '[:lower:]' '[:upper:]')"
    echo ""

    # Require root
    check_root

    if [[ -n "$specific_version" ]]; then
        # Toggle for specific version
        toggle_profiler "$action" "$specific_version"
    else
        # Detect and toggle for all PHP versions
        local php_versions
        php_versions=($(detect_php_versions))

        if [[ ${#php_versions[@]} -eq 0 ]]; then
            log_error "No PHP installations detected"
            exit 1
        fi

        log_info "Processing PHP versions: ${php_versions[*]}"
        echo ""

        for version in "${php_versions[@]}"; do
            toggle_profiler "$action" "$version"
            echo ""
        done
    fi

    log_success "Xdebug profiler toggle completed"

    if [[ "$action" == "on" ]]; then
        echo ""
        log_info "Profile files will be saved to: /tmp/xdebug/"
        log_info "Analyze with: kcachegrind /tmp/xdebug/cachegrind.out.*"
    fi
}

# Execute main function
main "$@"
