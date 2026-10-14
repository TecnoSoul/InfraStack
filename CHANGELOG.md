# Changelog

All notable changes to InfraStack are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.2.0] - 2026-10-14

### Added
- `nextcloud.sh`: `--domain`, `--dataset` and `--trusted-proxy` flags, allowing isolated test instances with their own dataset and domain.
- `nextcloud.sh`: sets `TRUSTED_PROXIES` (default `192.168.2.200`, the NPM proxy) so Nextcloud sees real client IPs and brute-force throttling does not lock out the proxy.
- `nextcloud.sh`: summary now lists the NPM Advanced-tab settings for large uploads (`client_max_body_size 0`, `proxy_request_buffering off`, 3600 s timeouts).

### Changed
- `nextcloud.sh`: MariaDB and Redis now use Docker volumes on the NVMe root disk instead of the `hdd-pool` dataset; the HDD holds only user files and config. Existing deployments are unaffected; the change applies to new deployments.
- `nextcloud.sh`: default root disk raised from 20 to 32 GB.

### Fixed
- `nextcloud.sh`: trusted domain uses the container's real IP instead of a hardcoded `192.168.2.210`.

## [2.1.0] - 2026-10-14

### Added
- `containers` CLI category: `infrastack containers <debian-base|node-webapp|nextcloud|vaultwarden>` (2026-07-20).
- `node-webapp` container script: Debian 13 LXC with Node.js (nvm), PM2 with systemd startup, MariaDB or PostgreSQL in Docker, and optional nginx for SPA frontends (2026-07-20).
- `--hostname` flag for `debian-base.sh` to set custom FQDNs outside `tecnosoul.com.ar` (2026-06-23).
- Vaultwarden container script and deploy guide (2026-02-26).
- Nextcloud container script (Nextcloud apache + MariaDB + Redis on Docker, data on `hdd-pool`) and deploy guide (2026-02-26).
- `CHANGELOG.md`.

### Changed
- Version bumped to 2.1.0 (`infrastack.sh`, tests).
- README and CLAUDE.md now document the `containers` category, every container script, the network config generator and all guides.

### Fixed
- AzuraCast backups volume now maps to HDD storage; corrected default resources in the docs (2026-04-30).
- Docker port binding in Nextcloud and Vaultwarden: removed the `127.0.0.1` restriction so NPM (CT200) can reach the services (2026-02-26).
- `nextcloud.sh` now sources `container.sh` and defines `install_infrastack` (2026-02-26).

### Known issues
- `tests/test-radio-module.sh` aborts after the first PASS: `((TESTS_PASSED++))` returns a non-zero status under `set -e` when the counter is 0. Failed assertions also abort the run. With that fixed, the `container.sh uses INFRASTACK_ROOT` check still fails.
- `virtualmin-host.sh` and `network/generate-config.sh` are not wired into the CLI, even though their headers show `infrastack containers virtualmin` and `infrastack network ...` usage.

## [2.0.0] - 2026-02-12

### Added
- Radio module (formerly [RadioStack](https://github.com/TecnoSoul/RadioStack)): `infrastack radio <deploy|status|update|backup|logs|info|remove>` for AzuraCast and LibreTime on Proxmox VE.
- Shared libraries `container.sh`, `storage.sh` and `inventory.sh` in `scripts/lib/`.
- Radio documentation and `MIGRATION.md` (RadioStack → InfraStack).
- `tests/test-radio-module.sh`.
- Container deployment scripts `debian-base.sh` and `virtualmin-host.sh`, the network config generator (`scripts/network/generate-config.sh`, which only generates rules and never applies them), `docs/network-guide.md` and `docs/hosting3-deployment-guide.md` (2026-01-20).

## [1.0.0] - 2026-01-02

### Added
- Initial CLI `infrastack.sh` with `setup` (base packages, Zsh), `php` (Xdebug check/profile/audit) and `health` (server health check) categories.
- `install.sh` (installs to `/opt/infrastack`, symlinks `/usr/local/bin/infrastack`).
- Proxmox SSL certificate tools: `deploy-proxmox-ssl.sh` and the pull-based `rsync-certs-proxmox.sh` with a local config file.

[Unreleased]: https://github.com/TecnoSoul/InfraStack/compare/v2.2.0...HEAD
[2.2.0]: https://github.com/TecnoSoul/InfraStack/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/TecnoSoul/InfraStack/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/TecnoSoul/InfraStack/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/TecnoSoul/InfraStack/releases/tag/v1.0.0
