#!/bin/bash
#=============================================================================
# InfraStack - Zsh Setup Script
# Part of InfraStack sysadmin infrastructure toolkit
#
# Description: Installs and configures Zsh with Oh My Zsh and Agnoster theme
# Usage: infrastack setup zsh [username]
# Author: TecnoSoul
#=============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

#=============================================================================
# CONFIGURATION
#=============================================================================

OH_MY_ZSH_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

#=============================================================================
# FUNCTIONS
#=============================================================================

# Install Zsh if not already installed
install_zsh() {
    if check_command "zsh"; then
        local zsh_version
        zsh_version=$(zsh --version | cut -d' ' -f2)
        log_info "Zsh already installed (version: $zsh_version)"
        return 0
    fi

    log_step "Installing Zsh"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zsh
    log_success "Zsh installed"
}

# Install Oh My Zsh for a specific user
install_oh_my_zsh() {
    local target_user=$1
    local target_home

    # Get user's home directory
    target_home=$(eval echo "~$target_user")

    if [[ ! -d "$target_home" ]]; then
        log_error "Home directory not found for user: $target_user"
        return 1
    fi

    # Check if Oh My Zsh is already installed
    if [[ -d "$target_home/.oh-my-zsh" ]]; then
        log_info "Oh My Zsh already installed for $target_user"
        return 0
    fi

    log_step "Installing Oh My Zsh for user: $target_user"

    # Download and run Oh My Zsh installer as target user
    if [[ "$target_user" == "root" ]]; then
        # Run as root
        sh -c "$(curl -fsSL $OH_MY_ZSH_INSTALL_URL)" "" --unattended
    else
        # Run as specific user
        su - "$target_user" -c "sh -c \"\$(curl -fsSL $OH_MY_ZSH_INSTALL_URL)\" \"\" --unattended"
    fi

    log_success "Oh My Zsh installed for $target_user"
}

# Configure Agnoster theme
configure_theme() {
    local target_user=$1
    local target_home
    local zshrc_file

    target_home=$(eval echo "~$target_user")
    zshrc_file="$target_home/.zshrc"

    if [[ ! -f "$zshrc_file" ]]; then
        log_error ".zshrc file not found for user: $target_user"
        return 1
    fi

    log_step "Configuring Agnoster theme for $target_user"

    # Backup original .zshrc
    cp "$zshrc_file" "$zshrc_file.backup.$(date +%Y%m%d_%H%M%S)"

    # Update theme to agnoster
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' "$zshrc_file"

    log_success "Agnoster theme configured"
}

# Optionally set Zsh as default shell
set_default_shell() {
    local target_user=$1
    local current_shell

    current_shell=$(getent passwd "$target_user" | cut -d: -f7)

    if [[ "$current_shell" == *"zsh"* ]]; then
        log_info "Zsh is already the default shell for $target_user"
        return 0
    fi

    echo ""
    if confirm_action "Set Zsh as default shell for $target_user?" "y"; then
        log_step "Setting Zsh as default shell"
        chsh -s "$(which zsh)" "$target_user"
        log_success "Zsh set as default shell for $target_user"
        log_warn "User needs to log out and back in for changes to take effect"
    else
        log_info "Keeping current shell ($current_shell)"
    fi
}

# Show summary
show_summary() {
    local target_user=$1
    local target_home
    target_home=$(eval echo "~$target_user")

    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Zsh Setup Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Configuration:
  • User: $target_user
  • Home: $target_home
  • Theme: Agnoster
  • Config: $target_home/.zshrc

Next steps:
  1. Log out and back in (if shell was changed)
  2. Install Powerline fonts for best theme appearance:
     apt-get install fonts-powerline
  3. Customize: $target_home/.zshrc

Additional plugins available at:
  https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins

EOF
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    local target_user="${1:-}"

    log_info "InfraStack - Zsh Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Validate environment
    check_root
    check_debian || die "This script requires a Debian/Ubuntu system"

    # Determine target user
    if [[ -z "$target_user" ]]; then
        # If no user specified, try to detect the original user (before sudo)
        if [[ -n "${SUDO_USER:-}" ]]; then
            target_user="$SUDO_USER"
            log_info "Installing for user: $target_user (detected from SUDO_USER)"
        else
            target_user="root"
            log_info "Installing for user: root"
        fi
    else
        # Validate specified user exists
        if ! id "$target_user" &>/dev/null; then
            die "User does not exist: $target_user"
        fi
        log_info "Installing for user: $target_user"
    fi

    echo ""

    # Install Zsh
    install_zsh

    # Install Oh My Zsh
    install_oh_my_zsh "$target_user"

    # Configure Agnoster theme
    configure_theme "$target_user"

    # Set as default shell
    set_default_shell "$target_user"

    # Show summary
    show_summary "$target_user"
}

# Execute main function
main "$@"
