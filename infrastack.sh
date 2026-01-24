#!/bin/bash
#=============================================================================
# InfraStack CLI - Main entry point
# Part of InfraStack sysadmin infrastructure toolkit
# https://github.com/TecnoSoul/InfraStack
#
# Description: Command-line interface for InfraStack tools
# Usage: infrastack <category> <command> [options]
# Author: TecnoSoul
# Version: 2.0.0
#
# History:
#   v1.0.0 - Initial release (setup, php, health modules)
#   v2.0.0 - Integrated RadioStack as radio module
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

# Export for use in submodules
export INFRASTACK_ROOT

# Configuration file location
INFRASTACK_CONFIG="${INFRASTACK_CONFIG:-/etc/infrastack/infrastack.conf}"

# Load configuration if exists
[[ -f "$INFRASTACK_CONFIG" ]] && source "$INFRASTACK_CONFIG"

# Source common library
source "$INFRASTACK_ROOT/scripts/lib/common.sh"

VERSION="2.0.0"

#=============================================================================
# COMMAND FUNCTIONS
#=============================================================================

# Show version
cmd_version() {
    echo "InfraStack v$VERSION"
    echo "Sysadmin Infrastructure Toolkit"
    echo "Includes: Radio Module (formerly RadioStack)"
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

  radio                         Radio platform deployment (formerly RadioStack)
    deploy <platform>           Deploy radio platform (azuracast/libretime)
    status                      Check status of radio stations
    update                      Update radio platforms
    backup                      Backup radio station
    logs                        View station logs
    info                        Show detailed information
    remove                      Remove radio station

  Other Commands:
    version                     Show version information
    help                        Show this help message

Examples:
  infrastack setup base
  infrastack setup zsh
  infrastack php xdebug-check
  infrastack php xdebug-profile on 8.2
  infrastack health check

  # Radio Module (formerly RadioStack)
  infrastack radio deploy azuracast -i 340 -n main-station
  infrastack radio deploy libretime -i 350 -n station1
  infrastack radio status
  infrastack radio status --platform azuracast
  infrastack radio update --ctid 340
  infrastack radio backup --ctid 340
  infrastack radio logs --ctid 340 --follow
  infrastack radio info --ctid 340
  infrastack radio remove --ctid 340

Documentation: /opt/infrastack/docs/
Radio Module Docs: /opt/infrastack/docs/radio/

EOF
}

# Show radio help
cmd_radio_help() {
    cat << 'EOF'
InfraStack Radio Module - Radio Platform Deployment

Usage: infrastack radio <command> [options]

Commands:
  deploy <platform>     Deploy radio platform (azuracast/libretime)
  status               Check status of radio stations
  update               Update radio platforms
  backup               Backup radio station
  logs                 View station logs
  info                 Show detailed information
  remove               Remove radio station

Deploy Options:
  -i, --ctid ID        Container ID (required)
  -n, --name NAME      Station name (required)
  -c, --cores NUM      CPU cores
  -m, --memory MB      Memory in MB
  -q, --quota SIZE     Storage quota (e.g., 500G)
  -p, --ip-suffix NUM  IP address suffix

Status Options:
  -a, --all            Show all containers (default)
  -p, --platform TYPE  Filter by platform (azuracast/libretime)
  -i, --ctid ID        Show specific container

Update Options:
  -i, --ctid ID        Update specific container
  -p, --platform TYPE  Update all of platform type
  -a, --all            Update all containers

Backup Options:
  -i, --ctid ID        Backup specific container
  -a, --all            Backup all containers
  -t, --type TYPE      Backup type: container/application/full
  -l, --list           List available backups

Logs Options:
  -i, --ctid ID        Container ID (required)
  -t, --type TYPE      Log type: container/application/both
  -n, --lines NUM      Number of lines (default: 50)
  -f, --follow         Follow logs in real-time

Info Options:
  -i, --ctid ID        Show container details
  -s, --summary        Show system summary (default)

Remove Options:
  -i, --ctid ID        Container to remove (required)
  -d, --data           Also remove ZFS dataset

Examples:
  infrastack radio deploy azuracast -i 340 -n main
  infrastack radio deploy libretime -i 350 -n station1 -c 4 -m 8192
  infrastack radio status --platform azuracast
  infrastack radio update --ctid 340
  infrastack radio backup --ctid 340 --type full
  infrastack radio logs --ctid 340 --follow
  infrastack radio remove --ctid 340 --data

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

        radio)
            # Radio module (formerly RadioStack)
            if [[ $# -eq 0 ]]; then
                cmd_radio_help
                exit 0
            fi

            local radio_cmd="$1"
            shift

            case "$radio_cmd" in
                deploy)
                    if [[ $# -eq 0 ]]; then
                        log_error "Missing platform for deploy"
                        echo "Usage: infrastack radio deploy <azuracast|libretime> [options]"
                        exit 1
                    fi
                    bash "$INFRASTACK_ROOT/scripts/radio/platforms/deploy.sh" "$@"
                    ;;
                status)
                    bash "$INFRASTACK_ROOT/scripts/radio/tools/status.sh" "$@"
                    ;;
                update)
                    bash "$INFRASTACK_ROOT/scripts/radio/tools/update.sh" "$@"
                    ;;
                backup)
                    bash "$INFRASTACK_ROOT/scripts/radio/tools/backup.sh" "$@"
                    ;;
                logs)
                    bash "$INFRASTACK_ROOT/scripts/radio/tools/logs.sh" "$@"
                    ;;
                info)
                    bash "$INFRASTACK_ROOT/scripts/radio/tools/info.sh" "$@"
                    ;;
                remove)
                    bash "$INFRASTACK_ROOT/scripts/radio/tools/remove.sh" "$@"
                    ;;
                help|--help|-h)
                    cmd_radio_help
                    ;;
                *)
                    log_error "Unknown radio command: $radio_cmd"
                    echo ""
                    echo "Available commands: deploy, status, update, backup, logs, info, remove"
                    echo "Run 'infrastack radio help' for more information"
                    exit 1
                    ;;
            esac
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
            echo "Available categories: setup, php, health, radio"
            echo "Run 'infrastack help' for more information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
