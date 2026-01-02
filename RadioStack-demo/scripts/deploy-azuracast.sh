#!/bin/bash
# /root/radio-platform/scripts/deploy-azuracast.sh
# Enhanced AzuraCast deployment with unified framework

# Source common functions
source "$(dirname "$0")/common-functions.sh"

# Default configuration
DEFAULT_CORES=6
DEFAULT_MEMORY=12288
DEFAULT_MEDIA_QUOTA="500G"
DEFAULT_IP_SUFFIX=140

# Help message
show_help() {
    cat << EOF
AzuraCast Container Deployment Script

Usage: $0 [OPTIONS]

Options:
    -i, --ctid ID           Container ID (required)
    -n, --name NAME         Station name (required)
    -c, --cores NUM         CPU cores (default: $DEFAULT_CORES)
    -m, --memory MB         Memory in MB (default: $DEFAULT_MEMORY)
    -q, --quota SIZE        Media storage quota (default: $DEFAULT_MEDIA_QUOTA)
    -p, --ip-suffix NUM     Last octet of IP (default: $DEFAULT_IP_SUFFIX)
    -h, --help              Show this help message

Examples:
    # Basic deployment
    $0 -i 340 -n main

    # Custom configuration
    $0 -i 341 -n fm-rock -c 8 -m 16384 -q 1T -p 141

EOF
    exit 0
}

# Parse arguments
CTID=""
STATION_NAME=""
CORES=$DEFAULT_CORES
MEMORY=$DEFAULT_MEMORY
MEDIA_QUOTA=$DEFAULT_MEDIA_QUOTA
IP_SUFFIX=$DEFAULT_IP_SUFFIX

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ctid) CTID="$2"; shift 2 ;;
        -n|--name) STATION_NAME="$2"; shift 2 ;;
        -c|--cores) CORES="$2"; shift 2 ;;
        -m|--memory) MEMORY="$2"; shift 2 ;;
        -q|--quota) MEDIA_QUOTA="$2"; shift 2 ;;
        -p|--ip-suffix) IP_SUFFIX="$2"; shift 2 ;;
        -h|--help) show_help ;;
        *) log_error "Unknown option: $1"; show_help ;;
    esac
done

# Validate required parameters
if [[ -z "$CTID" ]] || [[ -z "$STATION_NAME" ]]; then
    log_error "Container ID and station name are required"
    show_help
fi

# Derived variables
HOSTNAME="azuracast-${STATION_NAME}"
IP_ADDRESS="192.168.2.${IP_SUFFIX}"
MEDIA_DATASET="hdd-pool/container-data/azuracast-media/${STATION_NAME}"
MEDIA_MOUNT="/var/azuracast"

# Main execution
main() {
    check_root
    check_ctid_available "$CTID" || exit 1
    
    echo "========================================"
    echo "AzuraCast Container Deployment"
    echo "========================================"
    echo "Container ID: $CTID"
    echo "Hostname: $HOSTNAME"
    echo "IP Address: $IP_ADDRESS"
    echo "Cores: $CORES | Memory: ${MEMORY}MB"
    echo "Media: $MEDIA_DATASET ($MEDIA_QUOTA)"
    echo "========================================"
    echo ""
    
    # Step 1: Create media dataset
    create_media_dataset "$MEDIA_DATASET" "$MEDIA_QUOTA" "128k"
    
    # Step 2: Create container
    create_base_container "$CTID" "$HOSTNAME" "$CORES" "$MEMORY" "$IP_ADDRESS" \
        "AzuraCast radio station - $STATION_NAME"
    
    # Step 3: Attach media storage
    attach_mount_point "$CTID" "0" "/$MEDIA_DATASET" "$MEDIA_MOUNT"
    
    # Step 4: Start container
    log_info "Starting container..."
    pct start "$CTID"
    wait_for_container "$CTID"
    
    # Step 5: System setup
    setup_container_system "$CTID"
    
    # Step 6: Install AzuraCast
    log_info "Installing AzuraCast..."
    pct exec "$CTID" -- bash -c "
        mkdir -p $MEDIA_MOUNT
        cd $MEDIA_MOUNT
        curl -fsSL https://raw.githubusercontent.com/AzuraCast/AzuraCast/main/docker.sh > docker.sh
        chmod a+x docker.sh
        
        # Use stable release and auto-accept prompts
        yes 'Y' | ./docker.sh setup-release
        yes '' | ./docker.sh install
    "
    
    # Step 7: Add to inventory
    add_to_inventory "$CTID" "azuracast" "$HOSTNAME" "$IP_ADDRESS" "Station: $STATION_NAME"
    
    # Success message
    echo ""
    echo "========================================"
    echo "✅ AzuraCast Deployment Complete!"
    echo "========================================"
    echo ""
    echo "Access Information:"
    echo "  Internal: http://$IP_ADDRESS"
    echo "  Container: pct enter $CTID"
    echo ""
    echo "Next Steps:"
    echo "  1. Wait 2-3 minutes for AzuraCast to finish starting"
    echo "  2. Configure NPM proxy for public access"
    echo "  3. Create admin account via web interface"
    echo ""
    echo "Management Commands:"
    echo "  Update:  pct exec $CTID -- $MEDIA_MOUNT/docker.sh update"
    echo "  Backup:  pct exec $CTID -- $MEDIA_MOUNT/docker.sh backup"
    echo "  Logs:    pct exec $CTID -- $MEDIA_MOUNT/docker.sh logs"
    echo "========================================"
}

# Run main function
main