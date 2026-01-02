#!/bin/bash
# /root/radio-platform/scripts/bulk-operations.sh
# Bulk operations on multiple containers

source "$(dirname "$0")/common-functions.sh"

INVENTORY="/root/radio-platform/configs/container-inventory.csv"

# List all radio platform containers
list_containers() {
    log_info "Radio Platform Container Inventory"
    echo ""
    
    if [[ ! -f "$INVENTORY" ]]; then
        log_warn "No inventory file found"
        return 1
    fi
    
    column -t -s ',' "$INVENTORY"
}

# Update all AzuraCast containers
update_all_azuracast() {
    log_info "Updating all AzuraCast containers..."
    
    grep "azuracast" "$INVENTORY" | tail -n +2 | while IFS=',' read -r ctid type hostname rest; do
        log_info "Updating $hostname ($ctid)..."
        pct exec "$ctid" -- bash -c "cd /var/azuracast && ./docker.sh update-self && ./docker.sh update" || log_error "Failed to update $hostname"
    done
    
    log_info "All AzuraCast containers updated"
}

# Update all LibreTime containers
update_all_libretime() {
    log_info "Updating all LibreTime containers..."
    
    grep "libretime" "$INVENTORY" | tail -n +2 | while IFS=',' read -r ctid type hostname rest; do
        log_info "Updating $hostname ($ctid)..."
        pct exec "$ctid" -- bash -c "cd /opt/libretime && docker-compose pull && docker-compose up -d" || log_error "Failed to update $hostname"
    done
    
    log_info "All LibreTime containers updated"
}

# Backup all containers
backup_all() {
    local backup_dir="/hdd-pool/backups-zfs/radio-platform"
    local date_str=$(date +%Y%m%d)
    
    mkdir -p "$backup_dir"
    
    log_info "Backing up all containers to $backup_dir..."
    
    tail -n +2 "$INVENTORY" | while IFS=',' read -r ctid type hostname rest; do
        local backup_file="$backup_dir/${hostname}-${date_str}.tar.gz"
        log_info "Backing up $hostname ($ctid)..."
        
        vzdump "$ctid" --storage hdd-backups --compress zstd --mode snapshot || log_error "Failed to backup $hostname"
    done
    
    log_info "All backups completed"
}

# Check status of all containers
check_all_status() {
    log_info "Checking status of all radio platform containers..."
    echo ""
    
    tail -n +2 "$INVENTORY" | while IFS=',' read -r ctid type hostname ip rest; do
        status=$(pct status "$ctid" 2>/dev/null | awk '{print $2}')
        if [[ "$status" == "running" ]]; then
            echo -e "${GREEN}✓${NC} $hostname ($ctid) - $ip - Running"
        else
            echo -e "${RED}✗${NC} $hostname ($ctid) - $ip - $status"
        fi
    done
}

# Main menu
show_menu() {
    echo ""
    echo "========================================"
    echo "Radio Platform Bulk Operations"
    echo "========================================"
    echo "1. List all containers"
    echo "2. Update all AzuraCast"
    echo "3. Update all LibreTime"
    echo "4. Backup all containers"
    echo "5. Check all container status"
    echo "6. Exit"
    echo "========================================"
    read -p "Select option: " choice
    
    case $choice in
        1) list_containers ;;
        2) update_all_azuracast ;;
        3) update_all_libretime ;;
        4) backup_all ;;
        5) check_all_status ;;
        6) exit 0 ;;
        *) log_error "Invalid option"; show_menu ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    show_menu
}

check_root
show_menu