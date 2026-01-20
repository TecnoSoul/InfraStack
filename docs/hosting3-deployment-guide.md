# Deploying hosting3.ts on venus.ts - Complete Guide

Complete step-by-step guide for deploying hosting3 Virtualmin server on venus.ts using InfraStack.

## Overview

**What we're deploying**:
- Container: CT103 on venus.ts
- Purpose: Virtualmin hosting server (ns3.tecnosoul.com.ar)
- Replaces: Old hosting3 on jupiter.ts
- Role: Part of 3-server Virtualmin cluster (hosting1, hosting2, hosting3)

**Network Configuration**:
- Internal IP: 192.168.2.103
- Public Access: Via venus.ts public IP (51.79.77.238) with port forwarding
- Gateway: 192.168.2.1 (venus.ts host)

## Prerequisites

### 1. Venus.ts Host Ready

Verify venus.ts is properly configured:

```bash
# SSH to venus
ssh root@51.79.77.238

# Check IP forwarding
sysctl net.ipv4.ip_forward
# Should return: net.ipv4.ip_forward = 1

# Check NAT is configured
iptables -t nat -L POSTROUTING -n -v | grep MASQUERADE
# Should show rule for 192.168.2.0/24

# Check InfraStack is installed
infrastack version
```

### 2. DNS Records Prepared

Configure DNS **before** Virtualmin installation:

```
hosting3.tecnosoul.com.ar.    A    51.79.77.238
ns3.tecnosoul.com.ar.         A    51.79.77.238
```

Or use your domain provider's DNS management.

### 3. InfraStack Updated

```bash
# On venus.ts
cd /root/InfraStack
git pull
```

## Phase 1: Deploy Container with InfraStack

### Step 1: Create hosting3 Container

```bash
# On venus.ts
cd /root/InfraStack

# Deploy Virtualmin-ready container
sudo ./scripts/containers/virtualmin-host.sh -i 103 -n hosting3 -c 4 -m 4096
```

**What this does**:
✅ Creates privileged container (CT103)  
✅ Installs InfraStack toolkit  
✅ Installs base sysadmin packages  
✅ Configures Zsh with Oh My Zsh  
✅ Installs Virtualmin prerequisites  
✅ Downloads Virtualmin installer  
✅ Configures hostname properly  
✅ Sets up timezone  

**Wait for completion**: ~5-10 minutes

### Step 2: Verify Container

```bash
# Check container is running
pct status 103

# Check connectivity
pct exec 103 -- ping -c 4 8.8.8.8
pct exec 103 -- ping -c 4 google.com

# Both should work (NAT is configured)

# Check InfraStack is available
pct exec 103 -- infrastack version
```

## Phase 2: Configure Network

### Step 3: Generate Port Forwarding Script

```bash
# On venus.ts host (NOT inside container)
cd /root/InfraStack

# Generate port forwarding configuration
sudo ./scripts/network/generate-config.sh generate-forwarding \
    --ctid 103 \
    --type virtualmin \
    --public-ip 51.79.77.238
```

**Output**: `/root/port-forward-ct103.sh`

### Step 4: Review Generated Script

**IMPORTANT**: Always review before executing!

```bash
cat /root/port-forward-ct103.sh
```

**The script should configure forwarding for**:
- SSH: Port 2303 → 192.168.2.103:22
- HTTP/HTTPS: 80, 443 → 192.168.2.103:80, 443
- DNS: 53 (TCP/UDP) → 192.168.2.103:53
- Mail: 25, 587, 993, 995, 143, 110 → 192.168.2.103
- Webmin: 10000 → 192.168.2.103:10000
- Webmin RPC: 10001-10010 → 192.168.2.103

### Step 5: Apply Port Forwarding

```bash
# Execute the script
/root/port-forward-ct103.sh

# Make permanent
netfilter-persistent save

# Verify rules are applied
iptables -t nat -L PREROUTING -n -v | grep 192.168.2.103
```

### Step 6: Test External Access

```bash
# From external machine (your workstation)
# Test SSH access (should connect to container)
ssh -p 2303 root@51.79.77.238

# Test web access
curl -I http://51.79.77.238
# Should get response from container (or 404 if nothing listening yet)
```

## Phase 3: Install Virtualmin

### Step 7: Enter Container

```bash
# On venus.ts
pct enter 103
```

### Step 8: Run Virtualmin Installer

```bash
# Inside CT103
cd /root

# Run installer
./virtualmin-install.sh --hostname hosting3.tecnosoul.com.ar
```

**Installer prompts**:

1. **"Continue with installation?"** → Yes
2. **"Web stack?"** → LAMP (default)
3. **"Enable BIND?"** → Yes (for DNS)
4. **"Enable Postfix?"** → Yes (for mail)
5. **"Database?"** → MariaDB (or MySQL, your choice)

**Installation time**: 15-30 minutes

### Step 9: Wait for Installation

The installer will:
- Configure Apache/Nginx
- Set up BIND DNS
- Configure Postfix mail server
- Install and configure database
- Set up firewall rules
- Configure SSL

**Monitor progress**. If errors occur, check:
```bash
tail -f /root/virtualmin-install.log
```

### Step 10: Complete Web Setup

```bash
# Exit container
exit

# Access Webmin from your browser
https://51.79.77.238:10000
```

**Initial login**:
- Username: `root`
- Password: Your root password for CT103

**Complete the post-installation wizard**:
1. **Primary hostname**: hosting3.tecnosoul.com.ar
2. **Primary IP**: 192.168.2.103 (internal) or 51.79.77.238 (public)
3. **DNS server**: Use as secondary nameserver (ns3)
4. **MySQL/MariaDB password**: Set a strong password
5. **Skip**: Virus scanning (optional)
6. **Skip**: Spam filtering (optional for now)

## Phase 4: Configure as ns3.tecnosoul.com.ar

### Step 11: Configure DNS Settings

In Webmin/Virtualmin:

1. **Webmin → Servers → BIND DNS Server**
2. **Configure**:
   - Zone Files Location: `/var/cache/bind`
   - Check configuration
3. **Create/Verify Zones** for tecnosoul.com.ar
4. **Set as NS3**: Add NS record pointing to ns3.tecnosoul.com.ar

### Step 12: Join Virtualmin Cluster

**On hosting1 (or hosting2)**:

1. **Webmin → Servers → Webmin Servers Index**
2. **Add**: hosting3.tecnosoul.com.ar
3. **Configure**: Port 10000, SSL, root login
4. **Test connection**

**Configure cluster features**:
- Sync DNS zones
- Sync mail domains (optional)
- Sync virtual servers (optional)

### Step 13: Configure DNS Cluster

**Webmin → Servers → BIND DNS Server → Cluster Servers**:

1. Add hosting1.tecnosoul.com.ar
2. Add hosting2.tecnosoul.com.ar
3. Configure zone synchronization
4. Test cluster sync

## Phase 5: SSL and Security

### Step 14: SSL Certificates

**Option A: Let's Encrypt via Virtualmin**

```bash
# In Virtualmin web interface
Server Configuration → SSL Certificate → Let's Encrypt
```

**Option B: Use Nginx Proxy Manager**

Configure NPM (CT200) to proxy:
- `webmin.hosting3.tecnosoul.com.ar` → `192.168.2.103:10000`

See [SSL Management Guide](ssl-management.md)

### Step 15: Configure Firewall

**Inside CT103**:

```bash
# Check current firewall (Virtualmin sets this up)
iptables -L -n -v

# Or use Webmin: Networking → Linux Firewall
```

**Ensure these ports are allowed**:
- 22 (SSH)
- 53 (DNS)
- 80, 443 (Web)
- 25, 587 (SMTP)
- 993, 995 (IMAP/POP3 SSL)
- 10000 (Webmin)

### Step 16: Security Hardening

**SSH Security**:
```bash
# Inside CT103
# Edit SSH config
nano /etc/ssh/sshd_config

# Recommended settings:
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes

# Restart SSH
systemctl restart sshd
```

**Fail2ban** (optional):
```bash
apt install fail2ban
systemctl enable fail2ban
systemctl start fail2ban
```

## Phase 6: Testing and Verification

### Step 17: Test All Services

**DNS**:
```bash
# From external machine
dig @51.79.77.238 tecnosoul.com.ar
nslookup tecnosoul.com.ar 51.79.77.238
```

**Web**:
```bash
curl -I http://51.79.77.238
```

**Mail** (if configured):
```bash
telnet 51.79.77.238 25
# Should connect to Postfix
```

**Webmin**:
- Access: https://51.79.77.238:10000
- Should load Virtualmin interface

### Step 18: Create Test Virtual Server

In Virtualmin:
1. **Create Virtual Server**
2. **Domain**: test.hosting3.tecnosoul.com.ar
3. **Features**: Web, DNS, Mail
4. **Create**

Test the virtual server:
```bash
curl http://test.hosting3.tecnosoul.com.ar
```

## Phase 7: Migration (Optional)

### Step 19: Migrate Domains from Old hosting3

If migrating from jupiter.ts:

**On old hosting3 (jupiter.ts)**:
```bash
# Create backup
cd /root
virtualmin backup-domain --all-domains --dest /root/backup-all-domains.tar.gz
```

**Transfer to new hosting3**:
```bash
# From venus.ts host
scp -P 22 root@54.39.16.221:/root/backup-all-domains.tar.gz /tmp/

# Copy to container
pct push 103 /tmp/backup-all-domains.tar.gz /root/
```

**On new hosting3 (CT103)**:
```bash
# Restore
virtualmin restore-domain --all-domains --source /root/backup-all-domains.tar.gz
```

### Step 20: Update DNS Records

For each migrated domain:
1. Update NS records to include ns3.tecnosoul.com.ar
2. Update DNS cluster configuration
3. Test domain resolution

## Troubleshooting

### Container Can't Reach Internet

```bash
# On venus.ts host
# Check IP forwarding
sysctl net.ipv4.ip_forward

# Check NAT rule
iptables -t nat -L POSTROUTING -n -v | grep MASQUERADE

# Inside container
pct exec 103 -- ip route show
# Should show: default via 192.168.2.1
```

### Port Forwarding Not Working

```bash
# On venus.ts host
# Verify rules exist
iptables -t nat -L PREROUTING -n -v | grep 192.168.2.103

# Test from external
nmap -Pn 51.79.77.238 -p 80,443,10000

# Check Proxmox firewall
pve-firewall status
```

### Virtualmin Installation Fails

```bash
# Inside CT103
# Check logs
tail -f /root/virtualmin-install.log

# Common issues:
# - Hostname not resolving: Update /etc/hosts
# - Repository errors: Check internet connectivity
# - Port conflicts: Check for running services
```

### Can't Access Webmin

```bash
# Inside CT103
# Check Apache/Webmin status
systemctl status apache2
systemctl status webmin

# Check if listening
netstat -tlnp | grep 10000

# Check firewall
iptables -L -n | grep 10000
```

## Post-Deployment Checklist

- [ ] Container created and running
- [ ] Internet connectivity working (NAT)
- [ ] Port forwarding configured and saved
- [ ] Virtualmin installed successfully
- [ ] Web setup wizard completed
- [ ] DNS configured as ns3.tecnosoul.com.ar
- [ ] Joined Virtualmin cluster
- [ ] DNS cluster configured
- [ ] SSL certificates installed
- [ ] Firewall configured
- [ ] SSH hardened
- [ ] Test virtual server created
- [ ] All services tested externally
- [ ] Domains migrated (if applicable)
- [ ] DNS records updated

## Maintenance

### Regular Tasks

**Weekly**:
```bash
pct enter 103
apt update && apt upgrade -y
```

**Monthly**:
- Review Virtualmin logs
- Check disk space
- Verify backups
- Update SSL certificates (if manual)

### Backups

**Proxmox Container Backup**:
```bash
# On venus.ts
vzdump 103 --compress zstd --mode snapshot --storage hdd-backups
```

**Virtualmin Backup**:
```bash
# Inside CT103 or via Webmin
virtualmin backup-domain --all-domains --dest /backup/
```

### Monitoring

Use InfraStack health checks:
```bash
# Inside CT103
infrastack health check
```

## References

- [InfraStack Network Configuration Guide](network-guide.md)
- [SSL Certificate Management](ssl-management.md)
- [Virtualmin Documentation](https://www.virtualmin.com/docs)
- [BIND DNS Configuration](https://bind9.readthedocs.io/)

---

**Document Version**: 1.0  
**Last Updated**: 2025-01-20  
**Author**: TecnoSoul Infrastructure Team