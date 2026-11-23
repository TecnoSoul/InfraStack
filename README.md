# InfraStack

**Sysadmin Infrastructure Toolkit for Debian/Ubuntu Servers**

InfraStack is a collection of battle-tested scripts and tools for managing Debian-based servers, Proxmox hosts, and Virtualmin hosting environments. Born from real-world sysadmin experience, it provides a unified CLI for common infrastructure management tasks.

**Now includes the Radio Module** (formerly [RadioStack](https://github.com/TecnoSoul/RadioStack)) - deploy and manage radio streaming platforms on Proxmox VE.

---

## Features

### System Setup
- **Base Packages**: Install essential sysadmin tools with one command
- **Zsh Configuration**: Automated Zsh + Oh My Zsh + Agnoster theme setup

### PHP Development
- **Xdebug Management**: Multi-version PHP Xdebug control
  - Status checking across all PHP versions
  - Profiler toggle (on/off)
  - Detailed configuration auditing

### Monitoring
- **Health Checks**: Server health monitoring with warnings and alerts
  - Disk usage monitoring
  - Memory and load average tracking
  - Service status verification

### Radio Platform Deployment
- **AzuraCast & LibreTime**: Automated deployment on Proxmox VE
  - LXC container creation with optimal settings
  - ZFS dataset management for media storage
  - Docker-based platform installation
  - Inventory tracking and bulk operations

### Container Deployment (Proxmox VE)
All container scripts create an unprivileged Debian LXC (unless noted) on `vmbr1` (`192.168.2.0/24`), with InfraStack, base packages and Zsh preinstalled. Public SSL is handled by NPM (CT200).

- **debian-base**: Generic Debian container — starting point for any service without its own script. Supports `--hostname` for external FQDNs and `--privileged`.
- **node-webapp**: Node.js (nvm) + PM2 (systemd) + MariaDB/PostgreSQL in Docker + optional nginx for SPA frontends.
- **nextcloud**: Nextcloud (apache) + MariaDB + Redis + Cron on Docker; user files and config on a ZFS dataset in `hdd-pool`, MariaDB/Redis on NVMe Docker volumes.
- **vaultwarden**: Vaultwarden (Bitwarden-compatible) on Docker, data on `hdd-pool`.
- **n8n-ai**: [n8n](https://n8n.io) workflow automation + external task runner + PostgreSQL (pgvector) on Docker, deployed from [`stacks/n8n-ai`](stacks/n8n-ai/README.md). Starting point for automations that call AI models through an API.
- **virtualmin-host**: Virtualmin shared-hosting container (direct script only, not yet wired into the CLI).

---

## Installation

### Quick Install

```bash
git clone https://github.com/TecnoSoul/InfraStack.git
cd InfraStack
sudo ./install.sh
```

This will:
1. Copy InfraStack to `/opt/infrastack`
2. Create a symlink at `/usr/local/bin/infrastack`
3. Set up configuration directory at `/etc/infrastack`

### Manual Installation

```bash
sudo mkdir -p /opt/infrastack
sudo cp -r * /opt/infrastack/
sudo ln -s /opt/infrastack/infrastack.sh /usr/local/bin/infrastack
sudo chmod +x /opt/infrastack/infrastack.sh
sudo find /opt/infrastack/scripts -name "*.sh" -exec chmod +x {} \;
```

---

## Usage

### Command Structure

```
infrastack <category> <command> [options]
```

### Available Commands

#### Setup & Configuration

```bash
# Install base sysadmin packages
infrastack setup base

# Install and configure Zsh with Oh My Zsh
infrastack setup zsh

# Install Zsh for specific user
infrastack setup zsh username
```
#### SSL Management
```bash
# Sync SSL certificates to Proxmox (interactive)
/path/to/InfraStack/scripts/ssl-management/rsync-certs-proxmox.sh

# Automated sync (for cron, skip confirmation)
/path/to/InfraStack/scripts/ssl-management/rsync-certs-proxmox.sh --yes

# Show help
/path/to/InfraStack/scripts/ssl-management/rsync-certs-proxmox.sh --help
```

**Configuration:**
Create a local config file in the same directory:
```bash
cp rsync-certs-proxmox.conf.example .rsync-certs-proxmox.conf
nano .rsync-certs-proxmox.conf
```

#### PHP & Xdebug Management

```bash
# Check Xdebug status (all PHP versions)
infrastack php xdebug-check

# Check specific PHP version
infrastack php xdebug-check 8.2

# Enable Xdebug profiler (all versions)
infrastack php xdebug-profile on

# Enable profiler for specific version
infrastack php xdebug-profile on 8.2

# Disable profiler
infrastack php xdebug-profile off

# Detailed Xdebug audit
infrastack php xdebug-audit

# Audit specific version
infrastack php xdebug-audit 8.2
```

#### Server Monitoring

```bash
# Run health check
infrastack health check
```

Exit codes:
- `0` - Healthy (all checks passed)
- `1` - Warnings (some issues detected)
- `2` - Critical (serious issues)

#### Radio Platform Deployment (Proxmox VE)

```bash
# Deploy AzuraCast station
infrastack radio deploy azuracast -i 340 -n my-station

# Deploy LibreTime station
infrastack radio deploy libretime -i 350 -n station1

# Check status of all stations
infrastack radio status

# View logs
infrastack radio logs --ctid 340 --follow

# Backup station
infrastack radio backup --ctid 340

# Update platform
infrastack radio update --ctid 340

# Remove station
infrastack radio remove --ctid 340
```

See [Radio Module Documentation](docs/radio/getting-started.md) for full details.

#### Container Deployment (Proxmox VE)

```bash
# Generic Debian container
infrastack containers debian-base -i 140 -n myservice --hostname svc.example.org

# Node.js web app (Node + PM2 + DB in Docker + nginx)
infrastack containers node-webapp -i 150 -n myapp-prod \
  --hostname app.example.com \
  --db-type mariadb --db-name myapp_prod --app-port 4001

# API-only backend with PostgreSQL, no nginx
infrastack containers node-webapp -i 152 -n myapi --db-type postgres --no-nginx --app-port 8080

# Nextcloud
infrastack containers nextcloud -i 210 -n nube -c 6 -m 8192

# Vaultwarden
infrastack containers vaultwarden -i 211 -n vault

# n8n + PostgreSQL (stacks/n8n-ai)
infrastack containers n8n-ai -i 220 -n n8n

# Virtualmin hosting server (direct script)
sudo ./scripts/containers/virtualmin-host.sh -i 103 -n web3 -c 4 -m 4096
```

Common options for every container script: `-i <ctid>` (required), `-n <name>` (required), `-c <cores>`, `-m <memory_mb>`, `-p <ip_suffix>` (defaults to the CTID). Run any script with `-h` for its full option list.

| Script | Default cores / RAM / rootfs | Extra flags |
|--------|------------------------------|-------------|
| `debian-base` | 2 / 2048 MB / 16 GB | `--hostname`, `--privileged` |
| `node-webapp` | 2 / 2048 MB / 20 GB | `--hostname`, `--db-type mariadb\|postgres`, `--db-name`, `--node-version` (22), `--app-port` (3000), `--no-nginx` |
| `nextcloud` | 4 / 4096 MB / 32 GB | `--domain`, `--dataset`, `--trusted-proxy` |
| `vaultwarden` | 2 / 512 MB / 8 GB | — |
| `n8n-ai` | 2 / 2048 MB / 20 GB | `--domain`, `--n8n-version`, `--tunnel-token-file` |
| `virtualmin-host` | 4 / 4096 MB / 32 GB | — |

Credentials generated during deployment are saved on the Proxmox host to `/root/<service>-credentials-ct<ctid>.txt` (chmod 600).

See [Nextcloud](docs/nextcloud/deploy-guide.md), [Vaultwarden](docs/vaultwarden/deploy-guide.md), [n8n-ai](stacks/n8n-ai/README.md) and [web3 (Virtualmin)](docs/virtualmin-deployment-guide.md) guides for details.

#### Network Configuration Generator

```bash
# Generate (but NOT apply) port-forwarding / NAT rules for review
sudo ./scripts/network/generate-config.sh generate-forwarding --ctid 103 --type virtualmin
```

See the [Network Guide](docs/network-guide.md).

### SSL Certificate Management

- **Proxmox SSL Sync**: Automatically sync wildcard certificates to Proxmox hosts
  - Pull-based architecture (each server pulls from source)
  - Configurable via local config files
  - Support for internal and external networks
  - Automated via cron

#### Other

```bash
# Show version
infrastack version

# Show help
infrastack help
```

---

## Configuration

Configuration file: `/etc/infrastack/infrastack.conf` (copy it from [configs/infrastack.conf.example](configs/infrastack.conf.example)).

Site-specific values live only in this file, never in the scripts:

| Setting | Used by | Default |
|---------|---------|---------|
| `INFRASTACK_DOMAIN` | container hostnames `<name>.<domain>`, LXC search domain | required (unless `--hostname`) |
| `CT_NETWORK`, `CT_GATEWAY`, `CT_BRIDGE`, `CT_NAMESERVER` | container networking | `192.168.2`, `.1`, `vmbr1`, `8.8.8.8` |
| `CT_TEMPLATE`, `CT_ROOTFS_STORAGE`, `CT_DATA_BASE` | LXC template, root disk storage, ZFS data parent | Debian 13, `data`, `hdd-pool/container-data` |
| `PROXY_INTERNAL_IP`, `PROXY_PUBLIC_IP` | Nextcloud trusted proxy, DNS hints | `<network>.200`, placeholder |
| `NEXTCLOUD_DOMAIN`, `VAULTWARDEN_DOMAIN` | public service URLs | `<name>.<INFRASTACK_DOMAIN>` |
| `SSL_CERT_DIR`, `SSL_REMOTE_HOST`, `SSL_REMOTE_PORT`, `SSL_REMOTE_USER`, `PROXMOX_HOSTS` | SSL certificate sync | required for those scripts |

Command-line flags override the config.

---

## Base Packages

The `infrastack setup base` command installs:

- **Editors**: nano, vim
- **Monitoring**: htop, iotop, iftop, ncdu
- **Networking**: curl, wget, net-tools, dnsutils, nmap
- **Utilities**: tmux, rsync, mc (Midnight Commander), git, zsh
- **File Search**: mlocate (locate command)

---

## Requirements

- Debian 10+ or Ubuntu 20.04+
- Root/sudo access for installation and most operations
- Internet connection for package installation

---

## Updating

```bash
cd /opt/infrastack
git pull
```

---

## Documentation

Detailed documentation is available in the `docs/` directory:

- [Getting Started](docs/getting-started.md)
- [Setup Tools](docs/tools/setup.md)
- [Xdebug Management](docs/tools/xdebug.md)
- [SSL Management](docs/tools/ssl-management.md)
- [Network Guide](docs/network-guide.md)
- [Changelog](CHANGELOG.md)

### Radio Module Documentation

- [Radio Getting Started](docs/radio/getting-started.md)
- [LibreTime Guide](docs/radio/libretime.md)
- [Storage Configuration](docs/radio/storage-configuration.md)
- [Quick Reference](docs/radio/quick-reference.md)
- [Migration from RadioStack](MIGRATION.md)

### Nextcloud Documentation

- [Nextcloud Deploy Guide](docs/nextcloud/deploy-guide.md)
- [Docker Compose Reference](docs/nextcloud/docker-compose.yml)

### Other Container Guides

- [Vaultwarden Deploy Guide](docs/vaultwarden/deploy-guide.md)
- [web3 (Virtualmin) Deployment Guide](docs/virtualmin-deployment-guide.md)

---

## Project Structure

```
infrastack/
├── infrastack.sh              # Main CLI entry point (v3.0.0)
├── install.sh                 # Installation script
├── CHANGELOG.md               # Version history
├── MIGRATION.md               # RadioStack migration guide
├── scripts/
│   ├── lib/
│   │   ├── common.sh          # Shared library functions
│   │   ├── container.sh       # LXC container management
│   │   ├── storage.sh         # ZFS storage operations
│   │   └── inventory.sh       # Station inventory tracking
│   ├── setup/
│   │   ├── base-packages.sh   # Base packages installer
│   │   └── zsh-setup.sh       # Zsh configuration
│   ├── php/
│   │   ├── xdebug-check.sh    # Xdebug status checker
│   │   ├── xdebug-profile.sh  # Profiler toggle
│   │   └── xdebug-audit.sh    # Configuration auditor
│   ├── monitoring/
│   │   └── health-check.sh    # Server health check
│   ├── containers/
│   │   ├── debian-base.sh     # Generic Debian container
│   │   ├── node-webapp.sh     # Node.js + PM2 + DB stack
│   │   ├── nextcloud.sh       # Nextcloud full-stack deployment
│   │   ├── vaultwarden.sh     # Vaultwarden deployment
│   │   ├── n8n-ai.sh          # n8n-ai stack deployment
│   │   └── virtualmin-host.sh # Virtualmin hosting server
│   ├── network/
│   │   └── generate-config.sh # Port-forwarding/NAT rule generator
│   ├── ssl-management/        # Proxmox SSL certificate sync
│   └── radio/                 # Radio module (formerly RadioStack)
│       ├── platforms/
│       │   ├── azuracast.sh   # AzuraCast deployment
│       │   ├── libretime.sh   # LibreTime deployment
│       │   └── deploy.sh      # Platform dispatcher
│       └── tools/
│           ├── status.sh      # Station status
│           ├── update.sh      # Platform updates
│           ├── backup.sh      # Backup operations
│           ├── logs.sh        # Log viewer
│           ├── info.sh        # Station info
│           └── remove.sh      # Station removal
├── stacks/                    # Versioned Docker Compose stacks
│   └── n8n-ai/                # n8n + task runner + PostgreSQL (pgvector)
├── configs/
│   └── infrastack.conf.example
├── docs/
│   ├── getting-started.md
│   ├── network-guide.md
│   ├── virtualmin-deployment-guide.md
│   ├── tools/                 # setup, xdebug, ssl-management
│   ├── nextcloud/             # Nextcloud module docs
│   │   ├── deploy-guide.md
│   │   └── docker-compose.yml
│   ├── vaultwarden/
│   │   └── deploy-guide.md
│   └── radio/                 # Radio module docs
│       ├── getting-started.md
│       ├── libretime.md
│       ├── storage-configuration.md
│       └── quick-reference.md
└── tests/
    └── test-radio-module.sh   # Structure/syntax tests
```

---

## Contributing

Contributions are welcome! Please feel free to submit issues, fork the repository, and create pull requests.

---

## License

MIT License - see [LICENSE](LICENSE) file for details

---

## Author

**TecnoSoul**

Senior Linux Sysadmin
- Development: Arch/Manjaro
- Production: Debian servers, Proxmox VE, Virtualmin

---

## Related Projects

- **RadioStack** - Now integrated as the InfraStack Radio Module. See [MIGRATION.md](MIGRATION.md) for migration guide.

---

## Support

For issues, questions, or feature requests, please use the GitHub issue tracker.

**InfraStack** - Making server administration simpler, one script at a time.
