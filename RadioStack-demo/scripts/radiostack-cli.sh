#!/bin/bash
# RadioStack CLI - Main entry point
# Version: 1.0.0

RADIOSTACK_ROOT="/opt/radiostack"
RADIOSTACK_CONFIG="/etc/radiostack/radiostack.conf"

# Source configuration if exists
[[ -f "$RADIOSTACK_CONFIG" ]] && source "$RADIOSTACK_CONFIG"

# Source libraries
source "$RADIOSTACK_ROOT/scripts/lib/common.sh"
source "$RADIOSTACK_ROOT/scripts/lib/container.sh"
source "$RADIOSTACK_ROOT/scripts/lib/storage.sh"
source "$RADIOSTACK_ROOT/scripts/lib/inventory.sh"

VERSION="1.0.0"

# Show version
cmd_version() {
    echo "RadioStack v$VERSION"
    echo "Unified Radio Platform Deployment for Proxmox"
}

# Show help
cmd_help() {
    cat << EOF
RadioStack - Unified Radio Platform Deployment System

Usage: radiostack <command> [options]

Commands:
  deploy <platform>    Deploy a new radio station
  remove <ctid>        Remove a station container
  update <ctid|all>    Update station(s)
  backup <ctid|all>    Backup station(s)
  status [ctid]        Show station status
  list                 List all stations
  info <ctid>          Show detailed station info
  logs <ctid>          View station logs
  check                Check system requirements
  version              Show version information
  help                 Show this help message

Platforms:
  azuracast            AzuraCast web radio management
  libretime            LibreTime broadcast automation

Examples:
  radiostack deploy azuracast --ctid 340 --name main
  radiostack update --ctid 340
  radiostack backup --all
  radiostack status
  radiostack list

For detailed help: radiostack <command> --help
Documentation: https://radiostack.io/docs
EOF
}

# Main command router
main() {
    local command="$1"
    shift
    
    case "$command" in
        deploy)
            source "$RADIOSTACK_ROOT/scripts/platforms/deploy.sh"
            cmd_deploy "$@"
            ;;
        remove|delete)
            source "$RADIOSTACK_ROOT/scripts/tools/remove.sh"
            cmd_remove "$@"
            ;;
        update|upgrade)
            source "$RADIOSTACK_ROOT/scripts/tools/update.sh"
            cmd_update "$@"
            ;;
        backup)
            source "$RADIOSTACK_ROOT/scripts/tools/backup.sh"
            cmd_backup "$@"
            ;;
        status)
            source "$RADIOSTACK_ROOT/scripts/tools/status.sh"
            cmd_status "$@"
            ;;
        list|ls)
            source "$RADIOSTACK_ROOT/scripts/lib/inventory.sh"
            inventory_list
            ;;
        info)
            source "$RADIOSTACK_ROOT/scripts/tools/info.sh"
            cmd_info "$@"
            ;;
        logs)
            source "$RADIOSTACK_ROOT/scripts/tools/logs.sh"
            cmd_logs "$@"
            ;;
        check)
            source "$RADIOSTACK_ROOT/scripts/tools/check.sh"
            cmd_check "$@"
            ;;
        version|--version|-v)
            cmd_version
            ;;
        help|--help|-h|"")
            cmd_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"


