#!/bin/bash
# /root/radio-platform/scripts/deploy-libretime.sh
# LibreTime deployment with unified framework

# Source common functions
source "$(dirname "$0")/common-functions.sh"

# Default configuration
DEFAULT_CORES=4
DEFAULT_MEMORY=8192
DEFAULT_MEDIA_QUOTA="300G"
DEFAULT_IP_SUFFIX=150

# Help message
show_help() {
    cat << EOF
LibreTime Container Deployment Script

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
    $0 -i 350 -n station1

    # Custom configuration
    $0 -i 351 -n fm-classic -c 6 -m 12288 -q 500G -p 151

EOF
    exit 0
}

# Parse arguments (same pattern as AzuraCast)
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

# Validate
if [[ -z "$CTID" ]] || [[ -z "$STATION_NAME" ]]; then
    log_error "Container ID and station name are required"
    show_help
fi

# Derived variables
HOSTNAME="libretime-${STATION_NAME}"
IP_ADDRESS="192.168.2.${IP_SUFFIX}"
LIBRETIME_DIR="/opt/libretime"
MEDIA_DATASET="hdd-pool/container-data/libretime-media/${STATION_NAME}"

# Main execution
main() {
    check_root
    check_ctid_available "$CTID" || exit 1
    
    echo "========================================"
    echo "LibreTime Container Deployment"
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
        "LibreTime radio station - $STATION_NAME"
    
    # Step 3: Attach media storage
    attach_mount_point "$CTID" "0" "/$MEDIA_DATASET" "/srv/libretime"
    
    # Step 4: Start container
    log_info "Starting container..."
    pct start "$CTID"
    wait_for_container "$CTID"
    
    # Step 5: System setup
    setup_container_system "$CTID"
    
    # Step 6: Install Docker and LibreTime
    log_info "Installing Docker..."
    pct exec "$CTID" -- bash -c "
        # Install Docker
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
        
        # Install Docker Compose
        curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    "
    
    log_info "Setting up LibreTime..."
    pct exec "$CTID" -- bash -c "
        mkdir -p $LIBRETIME_DIR
        cd $LIBRETIME_DIR
        
        # Set LibreTime version
        echo 'LIBRETIME_VERSION=stable' > .env
        source .env
        
        # Download LibreTime files
        wget \"https://raw.githubusercontent.com/libretime/libretime/\$LIBRETIME_VERSION/docker-compose.yml\"
        wget \"https://raw.githubusercontent.com/libretime/libretime/\$LIBRETIME_VERSION/docker/config.template.yml\"
        
        # Generate passwords
        echo \"# Postgres\" >> .env
        echo \"POSTGRES_PASSWORD=\$(openssl rand -hex 16)\" >> .env
        echo \"# RabbitMQ\" >> .env
        echo \"RABBITMQ_DEFAULT_PASS=\$(openssl rand -hex 16)\" >> .env
        echo \"# Icecast\" >> .env
        echo \"ICECAST_SOURCE_PASSWORD=\$(openssl rand -hex 16)\" >> .env
        echo \"ICECAST_ADMIN_PASSWORD=\$(openssl rand -hex 16)\" >> .env
        echo \"ICECAST_RELAY_PASSWORD=\$(openssl rand -hex 16)\" >> .env
        
        # Generate config
        bash -a -c 'source .env; envsubst < config.template.yml > config.yml'
        
        # Update config for external media path
        sed -i 's|storage_path:.*|storage_path: /srv/libretime|g' config.yml
        
        # Start LibreTime
        docker-compose up -d
        
        # Wait for services to start
        sleep 30
        
        # Initialize database
        docker-compose exec -T libretime bash -c 'cd /var/www/libretime && php artisan migrate --force'
    "
    
    # Step 7: Add to inventory
    add_to_inventory "$CTID" "libretime" "$HOSTNAME" "$IP_ADDRESS" "Station: $STATION_NAME"
    
    # Success message
    echo ""
    echo "========================================"
    echo "✅ LibreTime Deployment Complete!"
    echo "========================================"
    echo ""
    echo "Access Information:"
    echo "  Internal: http://$IP_ADDRESS"
    echo "  Container: pct enter $CTID"
    echo ""
    echo "Default Credentials:"
    echo "  Username: admin"
    echo "  Password: admin"
    echo "  (Change immediately!)"
    echo ""
    echo "Management Commands:"
    echo "  Enter:   pct enter $CTID"
    echo "  Logs:    pct exec $CTID -- docker-compose -f $LIBRETIME_DIR/docker-compose.yml logs"
    echo "  Restart: pct exec $CTID -- docker-compose -f $LIBRETIME_DIR/docker-compose.yml restart"
    echo "========================================"
}

# Run main function
main