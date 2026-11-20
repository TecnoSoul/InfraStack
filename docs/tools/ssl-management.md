# SSL Certificate Management

InfraStack provides tools for managing SSL certificates across your infrastructure.

## Proxmox SSL Certificate Sync

Automatically pulls wildcard SSL certificates from a central Virtualmin server and deploys them to Proxmox hosts.

### Architecture
```
web1 (Certificate Source)
   └── /home/certuser/ssl.*
        ↑ Wildcard cert managed by Virtualmin
        ↑ Auto-renewed by Let's Encrypt
        ↑
        ├─── rsync ← pve1 (Proxmox host 1)
        │              └── restart pveproxy
        │
        └─── rsync ← pve2 (Proxmox host 2)
                       └── restart pveproxy
```

### Setup

#### 1. On Certificate Source (web1)

Ensure wildcard certificate exists at:
```bash
/home/certuser/ssl.cert
/home/certuser/ssl.key
```

#### 2. On Each Proxmox Host
```bash
cd /root/InfraStack
git pull

# Set the certificate source in the InfraStack config
nano /etc/infrastack/infrastack.conf
```

```bash
SSL_REMOTE_HOST="web1.example.com"   # certificate source
SSL_REMOTE_PORT=2200                 # SSH port (default 22)
SSL_REMOTE_USER="certuser"
SSL_CERT_DIR="/home/certuser"        # directory with ssl.cert / ssl.key
```

If the certificate source is a local VM on this host, use its internal IP and port 22.

The script stops with an error if these settings are missing. A legacy
`scripts/ssl-management/.rsync-certs-proxmox.conf` (`REMOTEHOST`, `REMOTEPORT`,
`REMOTEUSER`, `REMOTEDIR`) is still read and overrides the values above.

#### 3. Setup SSH Key Authentication
```bash
ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ""
ssh-copy-id -p <PORT> certuser@<HOST>
```

#### 4. Test the Script
```bash
./scripts/ssl-management/rsync-certs-proxmox.sh
```

#### 5. Add to Cron
```bash
crontab -e
```

Add:
```cron
# Pull SSL certificates - Mondays at 4:00 AM
0 4 * * 1 /root/InfraStack/scripts/ssl-management/rsync-certs-proxmox.sh --yes >> /var/log/ssl-cert-sync-cron.log 2>&1
```

### Usage

#### Interactive Mode
```bash
./scripts/ssl-management/rsync-certs-proxmox.sh
```

Shows configuration summary and prompts for confirmation.

#### Automated Mode (for cron)
```bash
./scripts/ssl-management/rsync-certs-proxmox.sh --yes
```

Skips confirmation prompt.

#### Help
```bash
./scripts/ssl-management/rsync-certs-proxmox.sh --help
```

### Configuration Options

Set in `/etc/infrastack/infrastack.conf` (or the legacy names in `.rsync-certs-proxmox.conf`):

| Option | Legacy name | Default | Description |
|--------|-------------|---------|-------------|
| `SSL_REMOTE_HOST` | `REMOTEHOST` | — (required) | Certificate source hostname |
| `SSL_REMOTE_PORT` | `REMOTEPORT` | 22 | SSH port |
| `SSL_REMOTE_USER` | `REMOTEUSER` | — (required) | SSH user |
| `SSL_CERT_DIR` | `REMOTEDIR` | — (required) | Certificate directory on source |

Legacy-file-only options:

| Option | Default | Description |
|--------|---------|-------------|
| `LOCALDIR` | /tmp/ssl-staging/ | Temporary staging directory |
| `PROXMOX_CERT_DIR` | /etc/pve/local | Proxmox certificate directory |
| `LOG_FILE` | /var/log/ssl-cert-sync.log | Log file location |

### Verification

Check deployed certificate:
```bash
openssl x509 -in /etc/pve/local/pve-ssl.pem -noout -subject -dates -issuer
```

Expected output:
```
subject=CN=*.example.com
notBefore=...
notAfter=...
issuer=C=US, O=Let's Encrypt, CN=R3
```

Access Proxmox web interface:
```
https://your-proxmox-host.domain.com:8006
```

Browser should show valid Let's Encrypt certificate.

### Logs

View sync logs:
```bash
# Main log
tail -f /var/log/ssl-cert-sync.log

# Cron log
tail -f /var/log/ssl-cert-sync-cron.log
```

### Troubleshooting

#### SSH Connection Failed

Test connectivity:
```bash
ssh -p <PORT> certuser@<HOST> "ls -la /home/certuser/ssl.*"
```

Re-copy SSH key if needed:
```bash
ssh-copy-id -p <PORT> certuser@<HOST>
```

#### Certificate Not Updating

Check certificate on source:
```bash
ssh -p <PORT> certuser@<HOST> "openssl x509 -in /home/certuser/ssl.cert -noout -dates"
```

Manually run sync:
```bash
./scripts/ssl-management/rsync-certs-proxmox.sh
```

Check pveproxy status:
```bash
systemctl status pveproxy
```

#### Permission Issues

Ensure staging directory is writable:
```bash
ls -la /tmp/ssl-staging/
```

Check Proxmox cert directory:
```bash
ls -la /etc/pve/local/pve-ssl.*
```

### Best Practices

1. **Weekly Sync**: Run at least weekly to catch certificate renewals
2. **Monitor Logs**: Check logs regularly for sync failures
3. **Test After Setup**: Always test manually before relying on cron
4. **Backup Certificates**: Script automatically backs up old certificates
5. **Multiple Hosts**: Each Proxmox host pulls independently

### Future Enhancements

Similar scripts can be created for:
- Nginx SSL sync
- Apache SSL sync
- Icecast SSL sync
- Nextcloud SSL sync

All following the same pull-based pattern with local configuration files.