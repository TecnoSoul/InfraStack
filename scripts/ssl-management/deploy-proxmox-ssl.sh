#!/bin/bash
################################################################################
# Script: deploy-proxmox-ssl.sh
# Description: Deploy wildcard SSL certificates to Proxmox hosts
# Author: TecnoSoul Infrastructure Team
# Repository: https://github.com/TecnoSoul/InfraStack
# License: MIT
# 
# Usage: ./deploy-proxmox-ssl.sh
# 
# This script deploys wildcard SSL certificates from Virtualmin to Proxmox hosts
# Certificates are sourced from /home/tecno/ssl.* (managed by Virtualmin)
# and deployed to configured Proxmox hosts
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

################################################################################
# Configuration
################################################################################

CERT_SOURCE="/home/tecno"
LOG_FILE="/var/log/proxmox-cert-deploy.log"
SCRIPT_NAME="$(basename "$0")"
VERSION="1.0.0"

# Proxmox hosts configuration
# Format: "HOSTNAME:IP_ADDRESS"
declare -a PROXMOX_HOSTS=(
    "marte.tecnosoul.com.ar:142.4.216.165"
    "venus.tecnosoul.com.ar:51.79.77.238"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Functions
################################################################################

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $@"
    log "INFO" "$@"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@"
    log "SUCCESS" "$@"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@"
    log "WARNING" "$@"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@"
    log "ERROR" "$@"
}

print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     Proxmox SSL Certificate Deployment Tool v${VERSION}      ║"
    echo "║              TecnoSoul Infrastructure Stack                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check if certificate files exist
    if [[ ! -f "${CERT_SOURCE}/ssl.cert" ]] || [[ ! -f "${CERT_SOURCE}/ssl.key" ]]; then
        log_error "Certificate files not found in ${CERT_SOURCE}"
        log_error "Required files: ssl.cert, ssl.key"
        exit 1
    fi
    
    # Check certificate expiry
    local expiry_date=$(openssl x509 -enddate -noout -in "${CERT_SOURCE}/ssl.cert" | cut -d= -f2)
    local expiry_epoch=$(date -d "${expiry_date}" +%s)
    local current_epoch=$(date +%s)
    local days_remaining=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    log_info "Certificate expires in ${days_remaining} days (${expiry_date})"
    
    if [[ $days_remaining -lt 7 ]]; then
        log_warning "Certificate expires in less than 7 days!"
    fi
    
    # Check SSH connectivity
    for host_entry in "${PROXMOX_HOSTS[@]}"; do
        local hostname="${host_entry%%:*}"
        local ip="${host_entry##*:}"
        
        if ! ssh -o ConnectTimeout=5 -o BatchMode=yes root@"$ip" "exit" 2>/dev/null; then
            log_error "Cannot connect to ${hostname} (${ip}) via SSH"
            log_error "Ensure SSH key authentication is configured"
            exit 1
        fi
    done
    
    log_success "All prerequisites met"
}

prepare_certificates() {
    log_info "Preparing certificate files..."
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    
    # Create Proxmox-compatible certificate format
    # Proxmox needs: fullchain + private key in pem file, and separate key file
    cat "${CERT_SOURCE}/ssl.cert" "${CERT_SOURCE}/ssl.key" > "${temp_dir}/pveproxy-ssl.pem"
    cp "${CERT_SOURCE}/ssl.key" "${temp_dir}/pveproxy-ssl.key"
    
    # Set secure permissions
    chmod 600 "${temp_dir}/pveproxy-ssl.pem"
    chmod 600 "${temp_dir}/pveproxy-ssl.key"
    
    echo "$temp_dir"
}

deploy_to_host() {
    local hostname=$1
    local ip=$2
    local temp_dir=$3
    
    log_info "Deploying certificate to ${hostname} (${ip})..."
    
    # Copy certificate files
    if scp -q "${temp_dir}/pveproxy-ssl.pem" root@"${ip}":/etc/pve/local/ && \
       scp -q "${temp_dir}/pveproxy-ssl.key" root@"${ip}":/etc/pve/local/; then
        log_success "Certificate files copied to ${hostname}"
    else
        log_error "Failed to copy certificate to ${hostname}"
        return 1
    fi
    
    # Restart pveproxy service
    log_info "Restarting pveproxy on ${hostname}..."
    if ssh root@"${ip}" "systemctl restart pveproxy"; then
        log_success "pveproxy restarted on ${hostname}"
    else
        log_error "Failed to restart pveproxy on ${hostname}"
        return 1
    fi
    
    # Verify certificate
    sleep 2  # Give service time to restart
    log_info "Verifying certificate on ${hostname}..."
    
    if ssh root@"${ip}" "openssl x509 -in /etc/pve/local/pveproxy-ssl.pem -noout -subject -dates" 2>/dev/null; then
        log_success "Certificate verified on ${hostname}"
    else
        log_warning "Could not verify certificate on ${hostname}"
    fi
    
    return 0
}

cleanup() {
    local temp_dir=$1
    if [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
        log_info "Temporary files cleaned up"
    fi
}

show_summary() {
    local success_count=$1
    local total_count=$2
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    Deployment Summary                      ║"
    echo "╠════════════════════════════════════════════════════════════╣"
    echo "║  Total hosts: ${total_count}                                         ║"
    echo "║  Successful: ${success_count}                                        ║"
    echo "║  Failed: $((total_count - success_count))                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [[ $success_count -eq $total_count ]]; then
        log_success "All certificates deployed successfully!"
        echo ""
        echo "Access Proxmox web interfaces at:"
        for host_entry in "${PROXMOX_HOSTS[@]}"; do
            local hostname="${host_entry%%:*}"
            echo "  → https://${hostname}:8006"
        done
        echo ""
    else
        log_warning "Some deployments failed. Check log: ${LOG_FILE}"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    print_header
    
    log_info "=== Starting Proxmox SSL certificate deployment ==="
    log_info "Source: ${CERT_SOURCE}"
    log_info "Hosts: ${#PROXMOX_HOSTS[@]}"
    
    # Pre-flight checks
    check_prerequisites
    
    # Prepare certificates
    local temp_dir=$(prepare_certificates)
    
    # Deploy to each host
    local success_count=0
    local total_count=${#PROXMOX_HOSTS[@]}
    
    for host_entry in "${PROXMOX_HOSTS[@]}"; do
        local hostname="${host_entry%%:*}"
        local ip="${host_entry##*:}"
        
        echo ""
        echo "────────────────────────────────────────────────────────────"
        
        if deploy_to_host "$hostname" "$ip" "$temp_dir"; then
            ((success_count++))
        fi
    done
    
    # Cleanup
    cleanup "$temp_dir"
    
    # Show summary
    show_summary "$success_count" "$total_count"
    
    log_info "=== Deployment completed ==="
    
    # Exit with appropriate code
    if [[ $success_count -eq $total_count ]]; then
        exit 0
    else
        exit 1
    fi
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 130' INT TERM

# Run main function
main "$@"