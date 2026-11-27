# Changelog

All notable changes to InfraStack are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `stacks/` directory for versioned Docker Compose stacks, starting with `stacks/n8n-ai`: n8n + external task runner + PostgreSQL 18 with pgvector, `.env.example`, `scripts/gen-env.sh` (random secrets, never overwrites an existing `.env`) and a README with operations notes and a first practice workflow.
- `n8n-ai.sh` container script and `infrastack containers n8n-ai`: unprivileged LXC with Docker, copies the stack to `/opt/n8n-ai`, generates `.env`, starts the stack, waits for `/healthz` and saves the secrets to `/root/n8n-ai-credentials-ct<ctid>.txt` on the Proxmox host. Flags: `--domain`, `--n8n-version`.
- `N8N_DOMAIN` setting in `configs/infrastack.conf.example`.
- `stacks/n8n-ai`: optional `tunnel` profile with `cloudflared` for Cloudflare Tunnel + Access (no open ports, n8n bound to `127.0.0.1`), selected with `COMPOSE_PROFILES` in `.env`. `gen-env.sh --tunnel-token-file` reads the token from a file or stdin and switches the stack to tunnel mode.
- `n8n-ai.sh`: `--tunnel-token-file` flag; the token reaches the container through stdin, never as an argument. The summary prints the Cloudflare steps (Access application first, then the public hostname) instead of the NPM ones.
- `docs/n8n-ai/deploy-guide.md`: architecture and deployment for both access options (Cloudflare Tunnel + Access, NPM) and how to switch between them.

### Changed
- README and CLAUDE.md: document Cloudflare Tunnel as the access option for `n8n-ai`, as an exception to the NPM convention.
- `infrastack version` no longer prints the "Includes: Radio Module (formerly RadioStack)" line.

## [3.0.0] - 2026-11-23

### Upgrading from 2.x
Site-specific values are no longer built into the scripts. Before updating a host, add these to `/etc/infrastack/infrastack.conf` (see `configs/infrastack.conf.example`):
- `INFRASTACK_DOMAIN`: required for container scripts unless `--hostname` is passed.
- `SSL_REMOTE_HOST`, `SSL_REMOTE_USER`, `SSL_CERT_DIR` (and `SSL_REMOTE_PORT` if not 22) on hosts running `rsync-certs-proxmox.sh`, or keep using the legacy `.rsync-certs-proxmox.conf`.
- `SSL_CERT_DIR` and `PROXMOX_HOSTS` on the host running `deploy-proxmox-ssl.sh`.
- Optionally `PROXY_PUBLIC_IP`, `NEXTCLOUD_DOMAIN`, `VAULTWARDEN_DOMAIN`, and any `CT_*` values that differ from the defaults.

### Added
- Site settings in `/etc/infrastack/infrastack.conf`: `INFRASTACK_DOMAIN`, `CT_*` network/storage/template settings, `PROXY_INTERNAL_IP`, `PROXY_PUBLIC_IP`, `NEXTCLOUD_DOMAIN`, `VAULTWARDEN_DOMAIN`, and SSL sync settings (`SSL_CERT_DIR`, `SSL_REMOTE_HOST`, `SSL_REMOTE_PORT`, `SSL_REMOTE_USER`, `PROXMOX_HOSTS`). All are documented in `configs/infrastack.conf.example`.
- `common.sh`: `load_container_defaults` and `require_config` helpers.
- `vaultwarden.sh`: `--domain` flag.
- `tests/check-private-data.sh`: fails if strings listed in the gitignored `.private/patterns.txt` appear in tracked files.

### Changed
- **Breaking:** container scripts require `INFRASTACK_DOMAIN` in the config (unless `--hostname` is given); they no longer default to a built-in domain. Nextcloud and Vaultwarden domains default to `<name>.<INFRASTACK_DOMAIN>`.
- **Breaking:** `deploy-proxmox-ssl.sh` reads `SSL_CERT_DIR` and `PROXMOX_HOSTS` from the config; `rsync-certs-proxmox.sh` reads `SSL_REMOTE_*`/`SSL_CERT_DIR` (the legacy `.rsync-certs-proxmox.conf` still overrides). Both exit with an error when unconfigured instead of using built-in hosts.
- Container scripts and `create_base_container` take network, template, storage and nameserver from the config, with the previous values as defaults.
- `infrastack.sh` exports `INFRASTACK_CONFIG`, so container and radio subprocesses load the same config file.
- Usage examples in README, CLAUDE.md, `node-webapp.sh` and `debian-base.sh` now use generic names (`myapp-prod`, `app.example.com`) instead of real project and domain names.
- Docs and help text no longer expose real infrastructure: public IPs became documentation-range placeholders (`203.0.113.x`), server names became generic (`pve1`, `pve2`, `web1`–`web4`, `example.com`), and the Virtualmin deployment guide was renamed to `docs/virtualmin-deployment-guide.md`. The Nextcloud and Vaultwarden DNS hints now print `<NPM_PUBLIC_IP>`.

### Fixed
- `deploy-proxmox-ssl.sh` stopped after the first successful host (`((success_count++))` under `set -e`).
- `tests/test-radio-module.sh` aborted after its first check; failures are now counted and reported. The `container.sh` import check matches how the library actually sources `common.sh`.

### Known issues
- `docs/network-guide.md` links to a non-existent `containers.md`.

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
- `--hostname` flag for `debian-base.sh` to set custom FQDNs outside the default domain (2026-06-23).
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
- Container deployment scripts `debian-base.sh` and `virtualmin-host.sh`, the network config generator (`scripts/network/generate-config.sh`, which only generates rules and never applies them), `docs/network-guide.md` and the Virtualmin deployment guide (2026-01-20).

## [1.0.0] - 2026-01-02

### Added
- Initial CLI `infrastack.sh` with `setup` (base packages, Zsh), `php` (Xdebug check/profile/audit) and `health` (server health check) categories.
- `install.sh` (installs to `/opt/infrastack`, symlinks `/usr/local/bin/infrastack`).
- Proxmox SSL certificate tools: `deploy-proxmox-ssl.sh` and the pull-based `rsync-certs-proxmox.sh` with a local config file.

[Unreleased]: https://github.com/TecnoSoul/InfraStack/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/TecnoSoul/InfraStack/compare/v2.2.0...v3.0.0
[2.2.0]: https://github.com/TecnoSoul/InfraStack/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/TecnoSoul/InfraStack/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/TecnoSoul/InfraStack/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/TecnoSoul/InfraStack/releases/tag/v1.0.0
