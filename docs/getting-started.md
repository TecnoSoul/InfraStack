# Getting Started with InfraStack

## Installation

### Prerequisites

- Debian 10+ or Ubuntu 20.04+
- Root or sudo access
- Internet connection
- Git (for installation from repository)

### Quick Installation

```bash
git clone https://github.com/TecnoSoul/InfraStack.git
cd InfraStack
sudo ./install.sh
```

### Verify Installation

```bash
infrastack version
infrastack help
```

## First Steps

### 1. Install Base Packages

Install essential sysadmin tools:

```bash
sudo infrastack setup base
```

This installs:
- Text editors (nano, vim)
- Monitoring tools (htop, iotop, iftop, ncdu)
- Network utilities (curl, wget, net-tools, dnsutils, nmap)
- File management (mc, rsync)
- Version control (git)
- Shell (zsh)
- File search (mlocate)

### 2. Configure Your Shell

Set up Zsh with Oh My Zsh and Agnoster theme:

```bash
sudo infrastack setup zsh
```

Or for a specific user:

```bash
sudo infrastack setup zsh username
```

### 3. Check Server Health

Run a health check to ensure your server is in good condition:

```bash
sudo infrastack health check
```

## Configuration

InfraStack can be customized via the configuration file:

```bash
sudo cp /etc/infrastack/infrastack.conf.example /etc/infrastack/infrastack.conf
sudo nano /etc/infrastack/infrastack.conf
```

## Next Steps

- [Setup Tools Guide](tools/setup.md)
- [Xdebug Management Guide](tools/xdebug.md)
- Browse all available commands: `infrastack help`

## Updating InfraStack

```bash
cd /opt/infrastack
sudo git pull
```

## Getting Help

- Run `infrastack help` for command overview
- Run `infrastack <category> <command> --help` for specific help (when implemented)
- Check documentation in `/opt/infrastack/docs/`
- Report issues on GitHub
