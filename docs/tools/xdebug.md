# Xdebug Management

InfraStack provides comprehensive tools for managing Xdebug across multiple PHP versions.

## Overview

The Xdebug tools support:
- **Multiple PHP versions**: 7.4, 8.0, 8.1, 8.2, 8.3, 8.4
- **Automatic detection**: Finds all installed PHP versions
- **Both SAPIs**: CLI and FPM configurations
- **Safe operations**: Backups before modifications

## Commands

### Quick Status Check

```bash
infrastack php xdebug-check
```

Shows Xdebug status for all PHP versions.

**Output Example:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Xdebug Status Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[INFO] Detected PHP versions: 8.1 8.2 8.3

[STEP] PHP 8.1
[INFO] Xdebug 3.2.1 - ENABLED
       Mode: develop,debug
       CLI:  /etc/php/8.1/cli/conf.d/20-xdebug.ini
       FPM:  /etc/php/8.1/fpm/conf.d/20-xdebug.ini
```

### Check Specific Version

```bash
infrastack php xdebug-check 8.2
```

### Toggle Profiler

Enable profiling for all PHP versions:

```bash
sudo infrastack php xdebug-profile on
```

Enable for specific version:

```bash
sudo infrastack php xdebug-profile on 8.2
```

Disable profiling:

```bash
sudo infrastack php xdebug-profile off
```

**What It Does:**
1. Adds or removes `profile` mode from Xdebug configuration
2. Sets output directory to `/tmp/xdebug/`
3. Restarts PHP-FPM service
4. Creates backups before modification

### Detailed Audit

Full configuration audit:

```bash
infrastack php xdebug-audit
```

Audit specific version:

```bash
infrastack php xdebug-audit 8.2
```

**Shows:**
- Xdebug version
- All configuration settings
- CLI and FPM configurations
- Output directory status
- Service status

## Xdebug Modes

InfraStack works with all Xdebug 3.x modes:

| Mode | Purpose |
|------|---------|
| `develop` | Development helpers (var_dump improvements, etc.) |
| `debug` | Step debugging with IDE |
| `profile` | Performance profiling |
| `trace` | Function execution trace |
| `coverage` | Code coverage analysis |

Modes can be combined: `xdebug.mode=develop,profile,debug`

## Profiling Workflow

### 1. Enable Profiler

```bash
sudo infrastack php xdebug-profile on
```

### 2. Trigger Profiling

Add to URL query string:
```
https://yoursite.com/page?XDEBUG_PROFILE=1
```

Or set in php.ini to always profile:
```ini
xdebug.start_with_request=yes
```

### 3. Analyze Results

Profile files are saved to `/tmp/xdebug/`

View with KCachegrind (install separately):

```bash
# Install analyzer
sudo apt-get install kcachegrind

# Analyze profile
kcachegrind /tmp/xdebug/cachegrind.out.*
```

### 4. Disable When Done

```bash
sudo infrastack php xdebug-profile off
```

## Configuration Files

InfraStack modifies these files:

- CLI: `/etc/php/X.X/cli/conf.d/20-xdebug.ini`
- FPM: `/etc/php/X.X/fpm/conf.d/20-xdebug.ini`

Backups are created before modification:
- `20-xdebug.ini.backup.YYYYMMDD_HHMMSS`

## Manual Configuration

If you need to manually configure Xdebug:

```bash
# Edit configuration
sudo nano /etc/php/8.2/fpm/conf.d/20-xdebug.ini

# Restart FPM
sudo systemctl restart php8.2-fpm
```

Common settings:

```ini
; Enable Xdebug
zend_extension=xdebug.so

; Set mode(s)
xdebug.mode=develop,profile

; Profiling output
xdebug.output_dir=/tmp/xdebug

; Always profile (or use XDEBUG_PROFILE trigger)
xdebug.start_with_request=trigger

; Step debugging (IDE)
xdebug.client_host=localhost
xdebug.client_port=9003
```

## Troubleshooting

### Xdebug Not Loading

Check if installed:
```bash
php -m | grep xdebug
```

Install if missing:
```bash
sudo apt-get install php8.2-xdebug
```

### Profiler Not Creating Files

1. Check output directory exists and is writable:
```bash
ls -la /tmp/xdebug/
```

2. Create if needed:
```bash
sudo mkdir -p /tmp/xdebug
sudo chmod 777 /tmp/xdebug
```

3. Check Xdebug mode:
```bash
php -i | grep xdebug.mode
```

### FPM Not Restarting

Check service status:
```bash
sudo systemctl status php8.2-fpm
```

Manually restart:
```bash
sudo systemctl restart php8.2-fpm
```

View logs:
```bash
sudo journalctl -u php8.2-fpm -n 50
```

## Best Practices

1. **Disable profiling in production**: Performance overhead
2. **Clean up profile files**: They can consume significant disk space
3. **Use trigger mode**: Only profile specific requests
4. **Monitor output directory**: Set up rotation/cleanup

## Resources

- [Xdebug Documentation](https://xdebug.org/docs/)
- [Profiling Guide](https://xdebug.org/docs/profiler)
- [KCachegrind Manual](https://kcachegrind.github.io/)
