# VaultWarden Configuration Script by Gecky2102

Automated interactive installer for Vaultwarden on Linux (Docker + systemd + nginx).

## Quick Start

```bash
wget https://raw.githubusercontent.com/gecky2102/VaultWarden-Configuration-Script/main/vaultwarden-setup.sh
chmod +x vaultwarden-setup.sh
sudo ./vaultwarden-setup.sh
```

## What It Does

- installs dependencies and Docker
- configures Vaultwarden with SQLite/PostgreSQL/MySQL
- configures nginx reverse proxy and firewall
- supports multiple certificate modes:
  - Let's Encrypt single-domain
  - wildcard manual flow (generate private key + CSR, then import signed cert)
  - existing certificate/key import
- supports external/internal HTTPS port mapping (for NAT/port-forwarding setups)
- configures backups and management aliases
- optionally installs a custom MOTD dashboard

## Requirements

- Linux with systemd
- root privileges
- domain configured to your server/network

## Documentation

Detailed docs are in [`docs/`](docs/README.md):

- [Setup Flow](docs/setup-flow.md)
- [Certificate Modes](docs/certificates.md)
- [Networking and Port Forwarding](docs/networking.md)
- [Custom MOTD Dashboard](docs/motd.md)
- [Operations](docs/operations.md)

## License

MIT. See [`LICENSE`](LICENSE).
