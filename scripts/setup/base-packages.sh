#!/bin/bash
#=============================================================================
# InfraStack - Base Packages Installer
# Part of InfraStack sysadmin infrastructure toolkit
#
# Description: Installs essential sysadmin packages on Debian/Ubuntu systems
# Usage: infrastack setup base
# Author: TecnoSoul
#=============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

#=============================================================================
# CONFIGURATION
#=============================================================================

# Essential packages for system administration
BASE_PACKAGES=(
    "nano"           # Simple text editor
    "vim"            # Advanced text editor
    "htop"           # Interactive process viewer
    "iotop"          # I/O monitoring
    "iftop"          # Network bandwidth monitoring
    "ncdu"           # NCurses disk usage analyzer
    "tmux"           # Terminal multiplexer
    "curl"           # Transfer data from URLs
    "wget"           # Network downloader
    "rsync"          # File synchronization
    "net-tools"      # Network utilities (ifconfig, netstat, etc.)
    "dnsutils"       # DNS utilities (dig, nslookup)
    "nmap"           # Network scanner
    "mc"             # Midnight Commander file manager
    "locate"        # File indexing (locate command)
    "git"            # Version control
    "zsh"            # Advanced shell
)

#=============================================================================
# FUNCTIONS
#=============================================================================

# Check if package is installed
is_package_installed() {
    local package=$1
    dpkg -l "$package" 2>/dev/null | grep -q "^ii"
}

# Install packages
install_packages() {
    local to_install=()
    local already_installed=()

    log_step "Checking package status"
    for package in "${BASE_PACKAGES[@]}"; do
        if is_package_installed "$package"; then
            already_installed+=("$package")
        else
            to_install+=("$package")
        fi
    done

    # Report status
    if [[ ${#already_installed[@]} -gt 0 ]]; then
        log_info "Already installed (${#already_installed[@]}): ${already_installed[*]}"
    fi

    if [[ ${#to_install[@]} -eq 0 ]]; then
        log_success "All base packages are already installed!"
        return 0
    fi

    log_info "Packages to install (${#to_install[@]}): ${to_install[*]}"
    echo ""

    # Confirm installation
    if ! confirm_action "Install ${#to_install[@]} packages?" "y"; then
        log_info "Installation cancelled"
        exit 0
    fi

    # Update package index
    log_step "Updating package index"
    apt-get update -qq

    # Install packages
    log_step "Installing packages"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${to_install[@]}"

    # Update locate database if mlocate was installed
    if [[ " ${to_install[*]} " =~ " mlocate " ]]; then
        log_step "Updating locate database"
        updatedb &
        log_info "Locate database updating in background"
    fi

    log_success "Successfully installed ${#to_install[@]} packages"
}

# Show summary
show_summary() {
    cat << 'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Base Packages Installation Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Essential tools installed:
  • Text editors: nano, vim
  • Monitoring: htop, iotop, iftop, ncdu
  • Network: curl, wget, net-tools, dnsutils, nmap
  • Utilities: tmux, rsync, mc, git, zsh

Next steps:
  • Configure Zsh: infrastack setup zsh
  • Check system health: infrastack health check

EOF
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    log_info "InfraStack - Base Packages Installer"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Validate environment
    check_root
    check_debian || die "This script requires a Debian/Ubuntu system"

    # Check if apt is available
    check_command "apt-get" || die "apt-get command not found"

    # Install packages
    install_packages

    # Show summary
    show_summary
}

# Execute main function
main "$@"
