#!/bin/bash
#=============================================================================
# InfraStack - Common Library
# Part of InfraStack sysadmin infrastructure toolkit
# https://github.com/TecnoSoul/InfraStack
#
# This library provides:
#   - Logging functions with color-coded output
#   - Error handling and trap management
#   - Validation functions for system, Proxmox, and network
#   - Configuration management utilities
#   - General utility functions
#
# History:
#   - Originally from InfraStack (general sysadmin utilities)
#   - Enhanced with RadioStack functions (container/Proxmox utilities)
#   - Merged during RadioStack integration (2025)
#=============================================================================

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
# VALIDATION FUNCTIONS - General System
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
# VALIDATION FUNCTIONS - Proxmox/Container (from RadioStack)
#=============================================================================

# Function: check_proxmox_version
# Purpose: Verify Proxmox VE is installed and get version
# Parameters: None
# Returns: 0 if Proxmox is installed, 1 if not
# Example: check_proxmox_version || die "Not running on Proxmox VE"
check_proxmox_version() {
    if [[ ! -f /etc/pve/.version ]]; then
        log_error "Proxmox VE not detected"
        return 1
    fi

    local pve_version
    pve_version=$(pveversion | cut -d'/' -f2 | cut -d'-' -f1)
    log_info "Detected Proxmox VE version: $pve_version"
    return 0
}

# Function: validate_ctid
# Purpose: Validate container ID format and availability
# Parameters:
#   $1 - Container ID to validate
# Returns: 0 if valid and available, 1 if invalid or in use
# Example: validate_ctid "340" || die "Invalid container ID"
validate_ctid() {
    local ctid=$1

    # Check if CTID is a number
    if ! [[ "$ctid" =~ ^[0-9]+$ ]]; then
        log_error "Container ID must be numeric: $ctid"
        return 1
    fi

    # Check if CTID is in valid range (100-999999)
    if [[ $ctid -lt 100 ]] || [[ $ctid -gt 999999 ]]; then
        log_error "Container ID must be between 100 and 999999"
        return 1
    fi

    # Check if container already exists
    if pct status "$ctid" &>/dev/null; then
        log_error "Container $ctid already exists"
        return 1
    fi

    return 0
}

# Function: validate_ip
# Purpose: Validate IPv4 address format
# Parameters:
#   $1 - IP address to validate
# Returns: 0 if valid, 1 if invalid
# Example: validate_ip "192.168.1.10" || die "Invalid IP address"
validate_ip() {
    local ip=$1
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ ! $ip =~ $valid_ip_regex ]]; then
        log_error "Invalid IP address format: $ip"
        return 1
    fi

    # Check each octet is between 0-255
    local IFS='.'
    read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [[ $octet -gt 255 ]]; then
            log_error "Invalid IP address (octet > 255): $ip"
            return 1
        fi
    done

    return 0
}

#=============================================================================
# CONFIGURATION MANAGEMENT (from RadioStack)
#=============================================================================

# Default configuration file location
INFRASTACK_CONF="${INFRASTACK_CONF:-/etc/infrastack/infrastack.conf}"

# Function: load_config
# Purpose: Load InfraStack configuration file
# Parameters:
#   $1 - Config file path (optional, uses default if not provided)
# Returns: 0 on success, 1 if file doesn't exist (non-fatal)
# Example: load_config "/etc/infrastack/infrastack.conf"
load_config() {
    local config_file=${1:-$INFRASTACK_CONF}

    if [[ -f "$config_file" ]]; then
        log_info "Loading configuration from $config_file"
        # shellcheck disable=SC1090
        source "$config_file"
        return 0
    else
        log_warn "Configuration file not found: $config_file (using defaults)"
        return 1
    fi
}

# Function: get_config_value
# Purpose: Get specific configuration value with fallback default
# Parameters:
#   $1 - Variable name to get
#   $2 - Default value if not set
# Returns: Echoes the value (either from config or default)
# Example: CORES=$(get_config_value "DEFAULT_AZURACAST_CORES" "6")
get_config_value() {
    local var_name=$1
    local default_value=$2

    # Use indirect expansion to get variable value
    local value="${!var_name:-$default_value}"
    echo "$value"
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

# Function: wait_with_progress
# Purpose: Wait for specified seconds with progress indicator
# Parameters:
#   $1 - Seconds to wait
#   $2 - Message to display (optional)
# Returns: 0 when complete
# Example: wait_with_progress 30 "Waiting for service to start"
wait_with_progress() {
    local seconds=$1
    local message=${2:-"Waiting"}

    log_info "$message ($seconds seconds)..."
    for ((i=seconds; i>0; i--)); do
        echo -ne "\rTime remaining: ${i}s  "
        sleep 1
    done
    echo -e "\n"
}

#=============================================================================
# EXPORT ALL FUNCTIONS
#=============================================================================

# Logging
export -f log_info log_warn log_error log_step log_success

# Error handling
export -f die trap_error

# Validation - General
export -f check_root check_command check_debian

# Validation - Proxmox/Container
export -f check_proxmox_version validate_ctid validate_ip

# Configuration
export -f load_config get_config_value

# Utilities
export -f confirm_action detect_php_versions wait_with_progress
