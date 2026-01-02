#!/bin/bash
# InfraStack - Common Library
# Part of InfraStack sysadmin infrastructure toolkit
# https://github.com/TecnoSoul/InfraStack
#
# This library provides: Logging, validation, and error handling for system administration tasks

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Export color codes for use in other scripts
export RED GREEN YELLOW BLUE NC

#=============================================================================
# LOGGING FUNCTIONS
#=============================================================================

# Function: log_info
# Purpose: Log informational messages with green [INFO] prefix
# Parameters:
#   $1 - Message to log
# Returns: None
# Example: log_info "Starting installation"
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Function: log_warn
# Purpose: Log warning messages with yellow [WARN] prefix
# Parameters:
#   $1 - Warning message to log
# Returns: None
# Example: log_warn "Service may require restart"
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Function: log_error
# Purpose: Log error messages with red [ERROR] prefix (does not exit)
# Parameters:
#   $1 - Error message to log
# Returns: None
# Example: log_error "Failed to install package"
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function: log_step
# Purpose: Log installation/process step messages with blue [STEP] prefix
# Parameters:
#   $1 - Step message to log
# Returns: None
# Example: log_step "Installing dependencies"
log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function: log_success
# Purpose: Log success messages with green [SUCCESS] prefix
# Parameters:
#   $1 - Success message to log
# Returns: None
# Example: log_success "Installation completed"
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

#=============================================================================
# ERROR HANDLING
#=============================================================================

# Function: die
# Purpose: Log error message and exit with error code
# Parameters:
#   $1 - Error message to log
#   $2 - Exit code (optional, default: 1)
# Returns: Never returns (exits script)
# Example: die "Configuration file not found" 2
die() {
    local message=$1
    local code=${2:-1}
    log_error "$message"
    exit "$code"
}

# Function: trap_error
# Purpose: Error trap handler for debugging (shows line number of error)
# Parameters: None (uses built-in variables)
# Returns: None
# Example: trap trap_error ERR
trap_error() {
    local line_number=$1
    log_error "Script failed at line $line_number"
}

#=============================================================================
# VALIDATION FUNCTIONS
#=============================================================================

# Function: check_root
# Purpose: Verify script is running as root user
# Parameters: None
# Returns: 0 on success (is root), exits with 1 if not root
# Example: check_root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root"
    fi
}

# Function: check_command
# Purpose: Check if a command exists in PATH
# Parameters:
#   $1 - Command name to check
# Returns: 0 if command exists, 1 if not found
# Example: check_command "git" || die "Git not installed"
check_command() {
    local cmd=$1
    if ! command -v "$cmd" &>/dev/null; then
        return 1
    fi
    return 0
}

# Function: check_debian
# Purpose: Verify script is running on Debian/Ubuntu system
# Parameters: None
# Returns: 0 if Debian-based, 1 if not
# Example: check_debian || die "This script requires Debian/Ubuntu"
check_debian() {
    if [[ ! -f /etc/debian_version ]]; then
        log_error "Not running on a Debian-based system"
        return 1
    fi
    return 0
}

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================

# Function: confirm_action
# Purpose: Prompt user for yes/no confirmation
# Parameters:
#   $1 - Prompt message
#   $2 - Default answer (y/n, optional, default: n)
# Returns: 0 for yes, 1 for no
# Example: confirm_action "Install package?" "n" || exit 0
confirm_action() {
    local prompt=$1
    local default=${2:-n}
    local response

    if [[ "$default" == "y" ]]; then
        read -rp "$prompt [Y/n]: " response
        response=${response:-y}
    else
        read -rp "$prompt [y/N]: " response
        response=${response:-n}
    fi

    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Function: detect_php_versions
# Purpose: Detect all installed PHP versions on the system
# Parameters: None
# Returns: Array of PHP versions (echoed as space-separated string)
# Example: PHP_VERSIONS=($(detect_php_versions))
detect_php_versions() {
    local versions=()

    # Check common PHP version paths
    for version in 7.4 8.0 8.1 8.2 8.3 8.4; do
        if [[ -x "/usr/bin/php${version}" ]]; then
            versions+=("$version")
        fi
    done

    echo "${versions[@]}"
}

# Export all functions
export -f log_info log_warn log_error log_step log_success
export -f die trap_error
export -f check_root check_command check_debian
export -f confirm_action detect_php_versions
