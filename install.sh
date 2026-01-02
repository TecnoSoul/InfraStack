#!/bin/bash
#=============================================================================
# InfraStack - Installation Script
# Part of InfraStack sysadmin infrastructure toolkit
# https://github.com/TecnoSoul/InfraStack
#
# Description: Installs InfraStack to /opt/infrastack and creates PATH symlink
# Usage: sudo ./install.sh
# Author: TecnoSoul
#=============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/infrastack"
BIN_LINK="/usr/local/bin/infrastack"

# Simple logging functions (before common.sh is available)
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
die() { log_error "$1"; exit "${2:-1}"; }

# Check root
[[ $EUID -eq 0 ]] || die "This script must be run as root (use sudo)"

# Determine script directory (where we're running from)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info "InfraStack Installation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Installation directory: $INSTALL_DIR"
log_info "Source directory: $SCRIPT_DIR"
echo ""

# Check if already installed
if [[ -d "$INSTALL_DIR" ]]; then
    log_info "InfraStack is already installed at $INSTALL_DIR"
    read -rp "Reinstall/update? [y/N]: " response
    if [[ ! "$response" =~ ^[yY]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    log_step "Removing existing installation"
    rm -rf "$INSTALL_DIR"
fi

# Create installation directory
log_step "Creating installation directory"
mkdir -p "$INSTALL_DIR"

# Copy files
log_step "Copying InfraStack files"
cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"

# Remove install.sh from installed location (avoid recursion)
rm -f "$INSTALL_DIR/install.sh"

# Make all scripts executable
log_step "Setting permissions"
find "$INSTALL_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} \;
chmod +x "$INSTALL_DIR/infrastack.sh"

# Create symlink
log_step "Creating symlink in /usr/local/bin"
if [[ -L "$BIN_LINK" ]]; then
    rm -f "$BIN_LINK"
fi
ln -s "$INSTALL_DIR/infrastack.sh" "$BIN_LINK"

# Create config directory (optional)
if [[ ! -d "/etc/infrastack" ]]; then
    log_step "Creating configuration directory"
    mkdir -p /etc/infrastack

    if [[ -f "$INSTALL_DIR/configs/infrastack.conf.example" ]]; then
        cp "$INSTALL_DIR/configs/infrastack.conf.example" /etc/infrastack/infrastack.conf.example
    fi
fi

echo ""
log_success "InfraStack installed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  1. Run: infrastack --help"
echo "  2. Configure: /etc/infrastack/infrastack.conf"
echo "  3. Example: infrastack setup base"
echo ""
log_info "Documentation: $INSTALL_DIR/docs/"
echo ""
