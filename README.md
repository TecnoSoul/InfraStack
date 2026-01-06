# InfraStack

**Sysadmin Infrastructure Toolkit for Debian/Ubuntu Servers**

InfraStack is a collection of battle-tested scripts and tools for managing Debian-based servers, Proxmox hosts, and Virtualmin hosting environments. Born from real-world sysadmin experience, it provides a unified CLI for common infrastructure management tasks.

Sister project to [RadioStack](https://github.com/TecnoSoul/RadioStack) - Radio Platform Deployment System.

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

Configuration file: `/etc/infrastack/infrastack.conf`

Example configuration is provided at `/etc/infrastack/infrastack.conf.example`

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

---

## Project Structure

```
infrastack/
├── infrastack.sh              # Main CLI entry point
├── install.sh                 # Installation script
├── scripts/
│   ├── lib/
│   │   └── common.sh          # Shared library functions
│   ├── setup/
│   │   ├── base-packages.sh   # Base packages installer
│   │   └── zsh-setup.sh       # Zsh configuration
│   ├── php/
│   │   ├── xdebug-check.sh    # Xdebug status checker
│   │   ├── xdebug-profile.sh  # Profiler toggle
│   │   └── xdebug-audit.sh    # Configuration auditor
│   └── monitoring/
│       └── health-check.sh    # Server health check
├── configs/
│   └── infrastack.conf.example
└── docs/
    ├── getting-started.md
    └── tools/
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

- **[RadioStack](https://github.com/TecnoSoul/RadioStack)** - Unified Radio Platform Deployment System for Proxmox VE

---

## Support

For issues, questions, or feature requests, please use the GitHub issue tracker.

**InfraStack** - Making server administration simpler, one script at a time.
