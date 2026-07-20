# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

InfraStack is a Bash-based sysadmin toolkit for Debian/Ubuntu servers and Proxmox VE. It is **not a compiled project** — there is no build step. All scripts are executed directly with `bash` or via the installed `infrastack` CLI.

Target environments:
- Development: Arch/Manjaro workstation
- Production: Debian servers, Proxmox VE, Virtualmin

## Running tests

```bash
# Syntax and structure validation (no Proxmox required)
bash tests/test-radio-module.sh

# Syntax check a single script
bash -n scripts/lib/common.sh
bash -n scripts/radio/platforms/azuracast.sh
```

Tests validate file existence, executability, syntax (`bash -n`), and CLI output — they do **not** provision real containers.

## Architecture

### Entry point and dispatch

`infrastack.sh` is the single CLI entry point. It resolves `INFRASTACK_ROOT` (works as a direct script or via `/usr/local/bin/infrastack` symlink), sources `scripts/lib/common.sh`, then routes by category (`setup`, `php`, `health`, `radio`) and sub-command.

- **setup / php / health** commands are loaded with `source` (run in the same shell process)
- **radio** commands are invoked with `bash` (run as subprocesses)

### Shared libraries (`scripts/lib/`)

All scripts source from `scripts/lib/` using `$INFRASTACK_ROOT` or `$SCRIPT_DIR`. Never use relative paths.

| File | Provides |
|------|----------|
| `common.sh` | Logging (`log_info`, `log_warn`, `log_error`, `log_step`, `log_success`), `die`, `check_root`, `check_proxmox_version`, `validate_ctid`, `validate_ip`, `load_config`, `confirm_action`, `detect_php_versions` |
| `container.sh` | LXC lifecycle via `pct`: `create_base_container`, `start/stop/restart/delete_container`, `setup_container_system`, `setup_docker`, `exec_in_container`, `attach_mount_point` |
| `storage.sh` | ZFS operations: `create_media_dataset`, `delete_dataset`, `check_storage_pool`, `fix_dataset_permissions`, `create_snapshot`, `rollback_snapshot` |
| `inventory.sh` | CSV-based station tracking at `/etc/infrastack/inventory/stations.csv`: `add_to_inventory`, `remove_from_inventory`, `update_inventory_status`, `list_all_stations`, `find_available_ctid` |

All library functions are exported (`export -f`) so they're available to subprocesses.

### Radio module (`scripts/radio/`)

Mirrors the structure of the old RadioStack project. `platforms/deploy.sh` dispatches to `azuracast.sh` or `libretime.sh`. Tools in `scripts/radio/tools/` (status, update, backup, logs, info, remove) each source the lib files independently via `$INFRASTACK_ROOT`.

### Container scripts (`scripts/containers/`)

| Script | Purpose |
|--------|---------|
| `debian-base.sh` | Crea un CT Debian genérico con InfraStack, base packages y Zsh preinstalados. Punto de partida para cualquier servicio que no tenga su propio script. |
| `nextcloud.sh` | Nextcloud (apache) + MariaDB + Redis sobre Docker, con dataset ZFS en `hdd-pool`. |
| `vaultwarden.sh` | Vaultwarden (Bitwarden-compatible) sobre Docker. |
| `virtualmin-host.sh` | Contenedor Virtualmin para hosting compartido (requiere `--privileged`). |

**`debian-base.sh` flags:**
```bash
./scripts/containers/debian-base.sh \
  -i <ctid>            # ID del contenedor (requerido)
  -n <name>            # Nombre base (requerido); hostname por defecto: <name>.tecnosoul.com.ar
  --hostname <fqdn>    # Sobreescribe el hostname (útil para dominios externos)
  -c <cores>           # CPU cores (default: 2)
  -m <memory_mb>       # RAM en MB (default: 2048)
  -p <ip_suffix>       # Último octeto de IP (default: igual al CTID)
  --privileged         # Contenedor privilegiado (default: unprivileged)
```

Ejemplo con hostname externo:
```bash
./scripts/containers/debian-base.sh -i 140 -n novacast --hostname cast.novamusic.online -c 2 -m 2048 -p 140
```

### Container deployment pattern

New container scripts (e.g., `scripts/containers/nextcloud.sh`) follow this sequence:
1. Create ZFS dataset on `hdd-pool` with correct UID-offset permissions (`chown 100000+uid`)
2. `pct create` with unprivileged + nesting for Docker
3. Mount dataset into container as a bind mount (`--mp0`)
4. `pct start` + `wait_for_container`
5. System update, InfraStack install inside container, base packages, Zsh, timezone
6. Docker CE install
7. Deploy application stack

### Network and storage conventions

- Internal network: `192.168.2.0/24`, gateway `192.168.2.1`, bridge `vmbr1`
- IP assignment: container IP typically matches CTID (e.g., CT210 → `192.168.2.210`)
- LXC template: `debian-13-standard_13.1-2_amd64.tar.zst` from local storage
- Root disk: NVMe pool (`data:`) — size in GB specified directly
- User data: `hdd-pool/container-data/<service>` (ZFS, mounted at `/mnt/<service>-data`)
- Unprivileged UID mapping: host UID = container UID + 100000 (e.g., www-data uid 33 → host uid 100033)
- SSL proxy: NPM at CT200; public DNS → NPM → internal container port
- Credentials generated on deployment are saved to `/root/<service>-credentials-ct<ctid>.txt` (chmod 600) on the Proxmox host

### Configuration

Runtime config: `/etc/infrastack/infrastack.conf` (sourced by `infrastack.sh` at startup). Example at `configs/infrastack.conf.example`. Inventory file: `/etc/infrastack/inventory/stations.csv`.
