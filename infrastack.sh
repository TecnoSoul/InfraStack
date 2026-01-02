#!/bin/bash
#=============================================================================
# InfraStack CLI - Main entry point
# Part of InfraStack sysadmin infrastructure toolkit
# https://github.com/TecnoSoul/InfraStack
#
# Description: Command-line interface for InfraStack tools
# Usage: infrastack <category> <command> [options]
# Author: TecnoSoul
# Version: 1.0.0
#=============================================================================

set -euo pipefail

# Determine InfraStack root directory
if [[ -L "${BASH_SOURCE[0]}" ]]; then
    # Running from symlink
    INFRASTACK_ROOT="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
else
    # Running from installation directory
    INFRASTACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Configuration file location
INFRASTACK_CONFIG="${INFRASTACK_CONFIG:-/etc/infrastack/infrastack.conf}"

# Load configuration if exists
[[ -f "$INFRASTACK_CONFIG" ]] && source "$INFRASTACK_CONFIG"

# Source common library
source "$INFRASTACK_ROOT/scripts/lib/common.sh"

VERSION="1.0.0"

#=============================================================================
# COMMAND FUNCTIONS
#=============================================================================

# Show version
cmd_version() {
    echo "InfraStack v$VERSION"
    echo "Sysadmin Infrastructure Toolkit"
    echo "https://github.com/TecnoSoul/InfraStack"
}

# Show main help
cmd_help() {
    cat << 'EOF'
InfraStack - Sysadmin Infrastructure Toolkit

Usage: infrastack <category> <command> [options]

Categories & Commands:

  setup                         System setup and configuration
    base                        Install base sysadmin packages
    zsh [username]              Install and configure Zsh with Oh My Zsh

  php                           PHP development tools
    xdebug-check [version]      Check Xdebug status
    xdebug-profile <on|off>     Toggle Xdebug profiler
    xdebug-audit [version]      Audit Xdebug configuration

  health                        Server monitoring
    check                       Run server health check

  Other Commands:
    version                     Show version information
    help                        Show this help message

Examples:
  infrastack setup base
  infrastack setup zsh
  infrastack php xdebug-check
  infrastack php xdebug-profile on 8.2
  infrastack health check
  infrastack version

Documentation: /opt/infrastack/docs/
Sister Project: RadioStack (https://github.com/TecnoSoul/RadioStack)

EOF
}

#=============================================================================
# COMMAND ROUTING
#=============================================================================

# Main command router
main() {
    # Handle no arguments
    if [[ $# -eq 0 ]]; then
        cmd_help
        exit 0
    fi

    local category="$1"
    shift

    case "$category" in
        setup)
            if [[ $# -eq 0 ]]; then
                log_error "Missing setup command"
                echo "Usage: infrastack setup <base|zsh>"
                exit 1
            fi
            local setup_cmd="$1"
            shift
            case "$setup_cmd" in
                base)
                    source "$INFRASTACK_ROOT/scripts/setup/base-packages.sh"
                    ;;
                zsh)
                    source "$INFRASTACK_ROOT/scripts/setup/zsh-setup.sh"
                    ;;
                *)
                    log_error "Unknown setup command: $setup_cmd"
                    echo "Available: base, zsh"
                    exit 1
                    ;;
            esac
            ;;

        php)
            if [[ $# -eq 0 ]]; then
                log_error "Missing PHP command"
                echo "Usage: infrastack php <xdebug-check|xdebug-profile|xdebug-audit>"
                exit 1
            fi
            local php_cmd="$1"
            shift
            case "$php_cmd" in
                xdebug-check)
                    source "$INFRASTACK_ROOT/scripts/php/xdebug-check.sh"
                    ;;
                xdebug-profile)
                    source "$INFRASTACK_ROOT/scripts/php/xdebug-profile.sh"
                    ;;
                xdebug-audit)
                    source "$INFRASTACK_ROOT/scripts/php/xdebug-audit.sh"
                    ;;
                *)
                    log_error "Unknown PHP command: $php_cmd"
                    echo "Available: xdebug-check, xdebug-profile, xdebug-audit"
                    exit 1
                    ;;
            esac
            ;;

        health|monitor|monitoring)
            if [[ $# -eq 0 || "$1" == "check" ]]; then
                source "$INFRASTACK_ROOT/scripts/monitoring/health-check.sh"
            else
                log_error "Unknown monitoring command: $1"
                echo "Available: check"
                exit 1
            fi
            ;;

        version|--version|-v)
            cmd_version
            ;;

        help|--help|-h)
            cmd_help
            ;;

        *)
            log_error "Unknown category: $category"
            echo ""
            echo "Available categories: setup, php, health"
            echo "Run 'infrastack help' for more information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
