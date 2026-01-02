# Setup Tools

InfraStack provides automated setup scripts for common system configuration tasks.

## Base Packages Installation

### Command

```bash
sudo infrastack setup base
```

### What It Does

Installs essential system administration packages on Debian/Ubuntu systems.

### Packages Installed

| Category | Packages |
|----------|----------|
| **Text Editors** | nano, vim |
| **System Monitoring** | htop, iotop, iftop, ncdu |
| **Network Tools** | curl, wget, net-tools, dnsutils, nmap |
| **Utilities** | tmux, rsync, mc, git, zsh |
| **File Search** | mlocate |

### Features

- **Idempotent**: Safe to run multiple times
- **Smart**: Only installs missing packages
- **Interactive**: Confirms before installing
- **Automatic**: Updates package index before installation
- **Background**: Updates locate database in background

### Example Output

```
InfraStack - Base Packages Installer
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[INFO] Already installed (8): vim htop curl wget git ...
[INFO] Packages to install (5): iotop iftop ncdu tmux rsync

Install 5 packages? [Y/n]: y

[STEP] Updating package index
[STEP] Installing packages
[SUCCESS] Successfully installed 5 packages
```

## Zsh Setup

### Command

```bash
# Install for current user (detected via SUDO_USER)
sudo infrastack setup zsh

# Install for specific user
sudo infrastack setup zsh username

# Install for root
sudo infrastack setup zsh root
```

### What It Does

1. Installs Zsh shell
2. Installs Oh My Zsh framework
3. Configures Agnoster theme
4. Optionally sets Zsh as default shell

### Features

- **User Detection**: Automatically detects user when run with sudo
- **Backup**: Creates backup of existing .zshrc
- **Theme**: Pre-configured with Agnoster theme
- **Optional Default**: Asks before changing default shell

### Post-Installation

For best theme appearance, install Powerline fonts:

```bash
sudo apt-get install fonts-powerline
```

### Customization

Edit your `.zshrc` file to customize:

```bash
nano ~/.zshrc
```

Common customizations:
- Change theme: `ZSH_THEME="robbyrussell"`
- Add plugins: `plugins=(git docker kubectl)`

### Available Oh My Zsh Themes

Some popular alternatives to Agnoster:
- `robbyrussell` - Default, simple
- `powerlevel10k` - Feature-rich (requires additional installation)
- `spaceship` - Minimalist
- `pure` - Minimal, fast

Browse all: https://github.com/ohmyzsh/ohmyzsh/wiki/Themes

## Tips

### Update Package List

Before installing, update your system:

```bash
sudo apt-get update
sudo apt-get upgrade
```

### Verify Installation

Check installed packages:

```bash
dpkg -l | grep package-name
```

Check Zsh version:

```bash
zsh --version
```

### Troubleshooting

**Problem**: Package not found  
**Solution**: Run `sudo apt-get update` first

**Problem**: Oh My Zsh installation fails  
**Solution**: Check internet connection and curl installation

**Problem**: Theme doesn't display correctly  
**Solution**: Install Powerline fonts: `sudo apt-get install fonts-powerline`
