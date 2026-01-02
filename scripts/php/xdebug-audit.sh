#!/bin/bash
#=============================================================================
# InfraStack - Xdebug Configuration Auditor
# Part of InfraStack sysadmin infrastructure toolkit
#
# Description: Detailed audit of Xdebug configuration across PHP versions
# Usage: infrastack php xdebug-audit [version]
# Author: TecnoSoul
#=============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

#=============================================================================
# FUNCTIONS
#=============================================================================

# Audit Xdebug for a specific PHP version
audit_php_version() {
    local version=$1
    local php_bin="/usr/bin/php${version}"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_step "PHP $version - Xdebug Audit"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check if PHP is installed
    if [[ ! -x "$php_bin" ]]; then
        log_error "PHP $version not installed"
        return 1
    fi

    # Check if Xdebug is loaded
    if ! $php_bin -m 2>/dev/null | grep -q "xdebug"; then
        log_warn "Xdebug not loaded for PHP $version"
        echo ""

        # Check for configuration files
        for sapi in cli fpm; do
            local ini_file="/etc/php/${version}/${sapi}/conf.d/20-xdebug.ini"
            if [[ -f "$ini_file" ]]; then
                log_info "Config found but Xdebug not loaded: $ini_file"
            fi
        done

        return 1
    fi

    # Get Xdebug version
    local xdebug_version
    xdebug_version=$($php_bin -v | grep -oP 'Xdebug v\K[0-9.]+' || echo "unknown")
    log_success "Xdebug $xdebug_version is loaded"
    echo ""

    # Audit CLI configuration
    echo "┌─ CLI Configuration ─────────────────────────────────────┐"
    local cli_ini="/etc/php/${version}/cli/conf.d/20-xdebug.ini"
    if [[ -f "$cli_ini" ]]; then
        echo "  File: $cli_ini"
        echo ""
        # Show key Xdebug settings
        local xdebug_settings
        xdebug_settings=$($php_bin -i 2>/dev/null | grep "^xdebug\." | head -20)
        if [[ -n "$xdebug_settings" ]]; then
            echo "$xdebug_settings" | while IFS= read -r line; do
                # Highlight mode setting
                if [[ "$line" =~ xdebug.mode ]]; then
                    echo -e "  ${GREEN}$line${NC}"
                else
                    echo "  $line"
                fi
            done
        fi
    else
        log_warn "CLI config not found: $cli_ini"
    fi
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # Audit FPM configuration
    echo "┌─ FPM Configuration ─────────────────────────────────────┐"
    local fpm_ini="/etc/php/${version}/fpm/conf.d/20-xdebug.ini"
    if [[ -f "$fpm_ini" ]]; then
        echo "  File: $fpm_ini"
        echo "  Content:"
        cat "$fpm_ini" | sed 's/^/    /'

        # Check FPM service status
        echo ""
        if systemctl is-active --quiet "php${version}-fpm" 2>/dev/null; then
            log_success "php${version}-fpm service is running"
        else
            log_warn "php${version}-fpm service is not running"
        fi
    else
        log_warn "FPM config not found: $fpm_ini"
    fi
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # Check output directory
    local output_dir
    output_dir=$($php_bin -i 2>/dev/null | grep "xdebug.output_dir" | head -1 | awk '{print $3}' || echo "")
    if [[ -n "$output_dir" && "$output_dir" != "no value" ]]; then
        echo "┌─ Output Directory ──────────────────────────────────────┐"
        echo "  Path: $output_dir"

        if [[ -d "$output_dir" ]]; then
            log_success "Directory exists"
            local file_count
            file_count=$(find "$output_dir" -type f 2>/dev/null | wc -l)
            echo "  Files: $file_count"

            # Show disk usage
            local du_output
            du_output=$(du -sh "$output_dir" 2>/dev/null | awk '{print $1}')
            echo "  Size: $du_output"
        else
            log_warn "Directory does not exist"
        fi
        echo "└─────────────────────────────────────────────────────────┘"
    fi

    return 0
}

# Show header
show_header() {
    cat << 'EOF'
InfraStack - Xdebug Configuration Audit
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This audit provides detailed Xdebug configuration information
for all installed PHP versions.

EOF
}

# Show footer
show_footer() {
    cat << 'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Audit Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Xdebug Documentation:
  https://xdebug.org/docs/

InfraStack Commands:
  • Quick check:     infrastack php xdebug-check
  • Toggle profiler: infrastack php xdebug-profile <on|off>

EOF
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    local specific_version="${1:-}"

    show_header

    if [[ -n "$specific_version" ]]; then
        # Audit specific version
        audit_php_version "$specific_version"
    else
        # Detect and audit all PHP versions
        local php_versions
        php_versions=($(detect_php_versions))

        if [[ ${#php_versions[@]} -eq 0 ]]; then
            log_error "No PHP installations detected"
            exit 1
        fi

        log_info "Detected PHP versions: ${php_versions[*]}"

        for version in "${php_versions[@]}"; do
            audit_php_version "$version"
        done
    fi

    show_footer
}

# Execute main function
main "$@"
