# Network Configuration Guide

Complete guide for configuring Proxmox networking for InfraStack-deployed containers.

## Overview

Network configuration for containers depends on your Proxmox setup and use case. This guide covers common scenarios and provides safe, tested configurations.

**IMPORTANT**: Always backup your network configuration before making changes:
```bash
# Backup current configuration
cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%Y%m%d)
cp /etc/iptables/rules.v4 /etc/iptables/rules.v4.backup.$(date +%Y%m%d)
```

## Architecture Patterns

### Pattern 1: Internal-Only Containers (Default)

**Use case**: Utility containers, development, internal services

**Network**: Internal bridge (vmbr1) with NAT
- Containers: 192.168.2.0/24
- Gateway: 192.168.2.1 (Proxmox host)
- Internet: Via NAT through Proxmox host

**No additional configuration needed** - InfraStack containers use this by default.

**Example containers**:
- Monitoring tools (CT 100)
- Development environments (CT 101-109)
- Internal utilities (CT 110-119)

### Pattern 2: Virtualmin Hosting with Port Forwarding

**Use case**: Virtualmin hosting servers (hosting3, hosting4, etc.)

**Network**: Internal IP + port forwarding from Proxmox public IP

**Required Proxmox host configuration**:

#### On venus.ts (example for hosting3 at CT 103):

```bash
# Create port forwarding script
nano /root/port-forward-hosting3.sh
```

```bash
#!/bin/bash
# Port forwarding for hosting3 (CT 103)
# Internal IP: 192.168.2.103
# Proxmox public IP: 51.79.77.238

# SSH (external port 2203 -> CT103:22)
iptables -t nat -A PREROUTING -d 51.79.77.238 -p tcp --dport 2203 \
    -j DNAT --to-destination 192.168.2.103:22

# Web traffic (80, 443)
iptables -t nat -A PREROUTING -d 51.79.77.238 -p tcp --dport 80 \
    -j DNAT --to-destination 192.168.2.103:80
iptables -t nat -A PREROUTING -d 51.79.77.238 -p tcp --dport 443 \
    -j DNAT --to-destination 192.168.2.103:443

# DNS (53 TCP and UDP)
iptables -t nat -A PREROUTING -d 51.79.77.238 -p udp --dport 53 \
    -j DNAT --to-destination 192.168.2.103:53
iptables -t nat -A PREROUTING -d 51.79.77.238 -p tcp --dport 53 \
    -j DNAT --to-destination 192.168.2.103:53

# Mail ports (SMTP, Submission, IMAP, IMAPS, POP3, POP3S)
iptables -t nat -A PREROUTING -d 51.79.77.238 -p tcp --dport 25 \
    -j DNAT --to-destination 192.168.2.103:25
iptables -t nat -A PREROUTING -d 51.79.77.238 -p tcp --dport 587 \
    -j DNAT --to-destination 192.168.2.103:587
iptables -t nat -A PREROUTING -d 51.79.77.238 -p tcp --dport 993 \
    -j DNAT --to-destination 192.168.2.103:993
iptables -t nat -A PREROUTING -d 51.79.77.238 -p tcp --dport 995 \
    -j DNAT --to-destination 192.168.2.103:995
iptables -t nat -A PREROUTING -d 51.79.77.238 -p tcp --dport 143 \
    -j DNAT --to-destination 192.168.2.103:143
iptables -t nat -A PREROUTING -d 51.79.77.238 -p tcp --dport 110 \
    -j DNAT --to-destination 192.168.2.103:110

# Webmin (10000)
iptables -t nat -A PREROUTING -d 51.79.77.238 -p tcp --dport 10000 \
    -j DNAT --to-destination 192.168.2.103:10000

# Webmin RPC cluster communication (10001-10010)
for port in {10001..10010}; do
    iptables -t nat -A PREROUTING -d 51.79.77.238 -p tcp --dport $port \
        -j DNAT --to-destination 192.168.2.103:$port
done

echo "✓ Port forwarding configured for hosting3 (CT 103)"
```

**Make executable and run**:
```bash
chmod +x /root/port-forward-hosting3.sh
/root/port-forward-hosting3.sh

# Save rules permanently
netfilter-persistent save
```

**Verify**:
```bash
# Check NAT rules
iptables -t nat -L PREROUTING -n -v | grep 192.168.2.103

# Test from external
nmap -p 80,443,10000 51.79.77.238
```

### Pattern 3: Using Nginx Proxy Manager (Recommended for Web Services)

**Use case**: Multiple web services, SSL termination, easier management

**Network**: Internal containers + NPM container with public IP

**Advantages**:
- ✅ No complex iptables rules
- ✅ Easy SSL certificate management
- ✅ Web UI for configuration
- ✅ Multiple domains to different containers
- ✅ Stream forwarding (TCP/UDP)

**Setup**:

1. **NPM container** (CT 200) has both:
   - Public IP: 15.235.57.208 (direct, no NAT)
   - Internal IP: 192.168.2.200

2. **Service containers** (hosting3, etc.) have only internal IPs

3. **NPM handles**:
   - SSL termination
   - Reverse proxy
   - Stream forwarding (for SSH, mail, etc.)

**Example NPM configuration for hosting3**:

**Proxy Host** (Web):
- Domain: `hosting3.tecnosoul.com.ar`
- Scheme: `http`
- Forward Hostname/IP: `192.168.2.103`
- Forward Port: `80`
- Websockets: ✅
- SSL: Let's Encrypt certificate

**Stream** (SSH):
- Incoming Port: `2203`
- Forward Host: `192.168.2.103`
- Forward Port: `22`
- TCP Forwarding: ✅

**See**: [InfraStack SSL Management docs](ssl-management.md) for NPM setup details.

## Port Allocation Strategy

Maintain a consistent port allocation scheme across all Proxmox hosts:

### SSH Forwarding Ports (22XX range)
```
2200 → VM100 (hosting1) - marte only
2203 → CT103 (hosting3)
2204 → CT104 (hosting4)
2210-2219 → Utility containers
2220-2229 → Development containers
```

### Web Services (80, 443)
- Use NPM for web services (easier than direct port forwarding)
- Or forward 80/443 to single hosting server (simple setup)

### Webmin (10000-10010)
```
10000 → Direct to hosting server Webmin
10001-10010 → Webmin RPC cluster communication
```

### Custom Services
```
8000-8099 → Radio streaming (if using RadioStack)
3000-3099 → Development web apps
9000-9099 → Monitoring tools (Prometheus, Grafana, etc.)
```

## Network Configuration Files

### Proxmox Host: /etc/network/interfaces

**venus.ts example**:
```
auto lo
iface lo inet loopback

# Physical interface
iface enp97s0f0 inet manual

# Public bridge (vmbr0)
auto vmbr0
iface vmbr0 inet static
    address 51.79.77.238/24
    gateway 51.79.77.254
    bridge-ports enp97s0f0
    bridge-stp off
    bridge-fd 0
    hwaddress D0:50:99:D4:99:AD

# IPv6 configuration
iface vmbr0 inet6 static
    address 2607:5300:203:5fee::/64
    gateway 2607:5300:203:5fff:ff:ff:ff:ff

# Internal bridge (vmbr1)
auto vmbr1
iface vmbr1 inet static
    address 192.168.2.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0

source /etc/network/interfaces.d/*
```

**Key points**:
- `vmbr0`: Public bridge with physical NIC
- `vmbr1`: Internal software bridge (no physical port)
- Gateway on vmbr1 is the host itself

### Enable IP Forwarding

**File**: `/etc/sysctl.conf`

```bash
# Enable IP forwarding for NAT
net.ipv4.ip_forward=1

# Optional: IPv6 forwarding
net.ipv6.conf.all.forwarding=1
```

Apply:
```bash
sysctl -p
```

### NAT Configuration (iptables)

**Basic NAT for internal network**:

```bash
# NAT rule (allows internal containers to access internet)
iptables -t nat -A POSTROUTING -s 192.168.2.0/24 -o vmbr0 -j MASQUERADE

# Save
netfilter-persistent save
```

**Verify NAT is working**:
```bash
# From inside a container
ping 8.8.8.8
ping google.com

# Should both work if NAT is configured correctly
```

## Troubleshooting

### Container can't reach internet

**Check from Proxmox host**:
```bash
# 1. Verify IP forwarding
sysctl net.ipv4.ip_forward
# Should return: net.ipv4.ip_forward = 1

# 2. Check NAT rule exists
iptables -t nat -L POSTROUTING -n -v | grep MASQUERADE
# Should show rule for 192.168.2.0/24

# 3. Test from host
ping -c 4 192.168.2.103

# 4. Check container's default route
pct exec 103 -- ip route show
# Should show: default via 192.168.2.1
```

**Fix**:
```bash
# If IP forwarding disabled
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# If NAT rule missing
iptables -t nat -A POSTROUTING -s 192.168.2.0/24 -o vmbr0 -j MASQUERADE
netfilter-persistent save
```

### Port forwarding not working

**Check**:
```bash
# 1. Verify rule exists
iptables -t nat -L PREROUTING -n -v | grep 192.168.2.103

# 2. Check Proxmox firewall (if enabled)
pve-firewall status

# 3. Test from external
nmap -Pn <proxmox-public-ip> -p <forwarded-port>
```

**Common issues**:
- Proxmox firewall blocking (disable or configure)
- Container firewall blocking
- Service not listening on correct interface inside container

### NPM not accessible

**Check**:
```bash
# 1. Verify NPM container has both IPs
pct exec 200 -- ip addr show

# 2. Check Docker containers running
pct exec 200 -- docker ps

# 3. Test from Proxmox host
curl -I http://192.168.2.200:81
```

## Security Considerations

### 1. Firewall Rules

Consider using Proxmox's built-in firewall or configure iptables:

```bash
# Example: Allow only specific ports on public interface
iptables -A INPUT -i vmbr0 -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -i vmbr0 -p tcp --dport 8006 -j ACCEPT
iptables -A INPUT -i vmbr0 -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -i vmbr0 -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -i vmbr0 -j DROP
```

### 2. SSH Security

- Use SSH keys only (disable password auth)
- Use non-standard ports for forwarded SSH (2200+)
- Consider fail2ban on both host and containers

### 3. Container Isolation

- Use unprivileged containers when possible
- Limit container capabilities
- Don't expose unnecessary services publicly

## Quick Reference

### Common Commands

```bash
# Show all NAT rules
iptables -t nat -L -n -v

# Show port forwarding rules
iptables -t nat -L PREROUTING -n -v

# Save iptables rules
netfilter-persistent save

# Reload iptables rules
netfilter-persistent reload

# Test container connectivity from host
ping 192.168.2.103

# Test from inside container
pct enter 103
ping 8.8.8.8
ping google.com
```

### Verification Checklist

Before deploying containers:
- [ ] IP forwarding enabled (`sysctl net.ipv4.ip_forward`)
- [ ] NAT rule exists for internal network
- [ ] Internal bridge (vmbr1) configured
- [ ] Gateway IP on vmbr1 set correctly
- [ ] iptables-persistent installed and enabled

After deploying container:
- [ ] Container has correct IP address
- [ ] Container can ping gateway (192.168.2.1)
- [ ] Container can ping internet (8.8.8.8)
- [ ] Container can resolve DNS (ping google.com)
- [ ] Port forwarding works (if configured)

## Examples by Proxmox Host

### marte.ts (142.4.216.165)

**Containers**:
- VM100 (hosting1): Port forwarding for all web/mail services
- CT200 (nginx-proxy): Has secondary public IP (192.99.215.100)

**Network**: Similar to venus, but different IP ranges

### venus.ts (51.79.77.238)

**Containers**:
- CT103 (hosting3): Port forwarding for web/mail
- CT200 (NPM): Has secondary public IP (15.235.57.208)

**Network**: As documented above

## Related Documentation

- [Virtualmin Deployment](virtualmin-deployment.md)
- [SSL Certificate Management](ssl-management.md)
- [Container Deployment](containers.md)

---

**Remember**: Network changes can break connectivity. Always:
1. Backup configurations before changes
2. Test changes incrementally
3. Have console access (not just SSH) when testing
4. Document all custom configurations