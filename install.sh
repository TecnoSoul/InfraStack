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

# Use /usr/bin for symlink (always in PATH, unlike /usr/local/bin)
BIN_LINK="/usr/bin/infrastack"

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
log_info "Source directory: $SCRIPT_DIR"
echo ""

# Check if this is a git repository
if [[ -d "$SCRIPT_DIR/.git" ]]; then
    log_info "Git repository detected - will create symlink to source"
else
    log_info "Not a git repository - will create symlink to source anyway"
    log_info "For updates via git pull, clone from: https://github.com/TecnoSoul/InfraStack.git"
fi
echo ""

# Make all scripts executable
log_step "Setting permissions"
find "$SCRIPT_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} \;
chmod +x "$SCRIPT_DIR/infrastack.sh"

# Create/update symlink
log_step "Creating symlink: $BIN_LINK -> $SCRIPT_DIR/infrastack.sh"
if [[ -L "$BIN_LINK" ]] || [[ -e "$BIN_LINK" ]]; then
    rm -f "$BIN_LINK"
fi
ln -s "$SCRIPT_DIR/infrastack.sh" "$BIN_LINK"

# Create config directory (optional)
if [[ ! -d "/etc/infrastack" ]]; then
    log_step "Creating configuration directory"
    mkdir -p /etc/infrastack

    if [[ -f "$SCRIPT_DIR/configs/infrastack.conf.example" ]]; then
        cp "$SCRIPT_DIR/configs/infrastack.conf.example" /etc/infrastack/infrastack.conf.example
    fi
fi

echo ""
log_success "InfraStack installed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Installation:"
echo "  Source:   $SCRIPT_DIR"
echo "  Command:  $BIN_LINK"
echo ""
echo "Next steps:"
echo "  1. Run: infrastack --help"
echo "  2. Configure: /etc/infrastack/infrastack.conf"
echo "  3. Example: infrastack setup base"
echo ""
echo "To update InfraStack:"
echo "  cd $SCRIPT_DIR && git pull"
echo ""
log_info "Documentation: $SCRIPT_DIR/docs/"
echo ""
