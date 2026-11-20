# SSL Certificate Management

Tools for managing SSL certificates across Proxmox hosts.

## deploy-proxmox-ssl.sh

Deploys wildcard SSL certificates from Virtualmin to Proxmox hosts.

### Prerequisites

- Wildcard SSL certificate managed by Virtualmin
- SSH key-based authentication to Proxmox hosts
- Root access on certificate source server

### Configuration

Set the certificate directory and target hosts in `/etc/infrastack/infrastack.conf`
(see `configs/infrastack.conf.example`):
```bash
SSL_CERT_DIR="/home/certuser"
PROXMOX_HOSTS=(
    "pve1.example.com:203.0.113.30"
    "pve2.example.com:203.0.113.10"
)
```
The script exits with an error if either is missing.

### Usage
```bash
# Manual deployment
./deploy-proxmox-ssl.sh

# Automated deployment (cron)
0 4 * * 1 /root/deploy-proxmox-ssl.sh
```

### Certificate Source

Certificates should be located at `${SSL_CERT_DIR}/ssl.*`:
- `ssl.cert` - Certificate file
- `ssl.key` - Private key
- `ssl.ca` - CA certificate

### Log File

Deployment logs are written to `/var/log/proxmox-cert-deploy.log`

### Adding New Hosts

Add entries to the `PROXMOX_HOSTS` array in `/etc/infrastack/infrastack.conf`.

### Troubleshooting

**SSH Connection Failed:**
```bash
# Test SSH connectivity
ssh -o BatchMode=yes root@hostname "exit"

# Copy SSH key if needed
ssh-copy-id root@hostname
```

**Certificate Not Updated:**
```bash
# Manually verify certificate on Proxmox
ssh root@hostname "openssl x509 -in /etc/pve/local/pveproxy-ssl.pem -noout -dates"

# Check pveproxy service
ssh root@hostname "systemctl status pveproxy"
```

**Certificate Expiry Warning:**
- Certificates are automatically renewed by Virtualmin
- This script should run weekly to deploy renewed certificates
- Manual renewal: Virtualmin UI → SSL Certificate → Request Certificate

