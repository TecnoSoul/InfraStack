# SSL Certificate Management

InfraStack provides tools for managing SSL certificates across your infrastructure.

## Proxmox SSL Certificate Sync

Automatically pulls wildcard SSL certificates from a central Virtualmin server and deploys them to Proxmox hosts.

### Architecture
```
hosting1.ts (Certificate Source)
   └── /home/tecno/ssl.*
        ↑ Wildcard cert managed by Virtualmin
        ↑ Auto-renewed by Let's Encrypt
        ↑
        ├─── rsync ← marte.ts (Proxmox host 1)
        │              └── restart pveproxy
        │
        └─── rsync ← venus.ts (Proxmox host 2)
                       └── restart pveproxy
```

### Setup

#### 1. On Certificate Source (hosting1.ts)

Ensure wildcard certificate exists at:
```bash
/home/tecno/ssl.cert
/home/tecno/ssl.key
```

#### 2. On Each Proxmox Host
```bash
cd /root/InfraStack
git pull

# Create local configuration
cp scripts/ssl-management/rsync-certs-proxmox.conf.example \
   scripts/ssl-management/.rsync-certs-proxmox.conf

# Edit configuration
nano scripts/ssl-management/.rsync-certs-proxmox.conf
```

**For external Proxmox hosts:**
```bash
REMOTEHOST=hosting1.tecnosoul.com.ar
REMOTEPORT=2200
```

**For Proxmox host where certificate source is a local VM:**
```bash
REMOTEHOST=192.168.1.100
REMOTEPORT=22
```

#### 3. Setup SSH Key Authentication
```bash
ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ""
ssh-copy-id -p <PORT> tecno@<HOST>
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

All options can be overridden in `.rsync-certs-proxmox.conf`:

| Option | Default | Description |
|--------|---------|-------------|
| `REMOTEHOST` | hosting1.tecnosoul.com.ar | Certificate source hostname |
| `REMOTEPORT` | 2200 | SSH port |
| `REMOTEUSER` | tecno | SSH user |
| `REMOTEDIR` | /home/tecno/ | Certificate directory on source |
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
subject=CN=*.tecnosoul.com.ar
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
ssh -p <PORT> tecno@<HOST> "ls -la /home/tecno/ssl.*"
```

Re-copy SSH key if needed:
```bash
ssh-copy-id -p <PORT> tecno@<HOST>
```

#### Certificate Not Updating

Check certificate on source:
```bash
ssh -p <PORT> tecno@<HOST> "openssl x509 -in /home/tecno/ssl.cert -noout -dates"
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