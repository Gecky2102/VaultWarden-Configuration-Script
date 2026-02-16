# Setup Flow

This script is an interactive Linux installer for Vaultwarden with Docker + systemd + nginx.

## 1. Pre-checks

The script verifies:
- root privileges
- Linux + systemd support

At startup, you choose one mode:
- Full setup: complete installation/configuration
- Commands-only: updates only aliases and `vw-help` command

Internet connectivity check is required only for full setup mode.

## 2. Cleanup

Before configuration, it tries to clean previous Vaultwarden container/service resources.
It does **not** kill unrelated processes on port 8000.

## 3. Interactive Configuration

The installer asks for:
- domain
- certificate mode
- external HTTPS port (user-facing)
- internal HTTPS port (nginx listen port)
- Vaultwarden image tag/version
- database mode (SQLite/PostgreSQL/MySQL)
- admin token generation/custom value
- optional SMTP settings
- optional custom MOTD dashboard

## 4. Installation Steps

Execution order:
1. install dependencies
2. install/enable Docker
3. create directories
4. setup/import certificates
5. validate external DB connectivity (if PostgreSQL/MySQL)
6. write `/opt/vaultwarden/.env`
7. pull Vaultwarden image
8. create and enable systemd service
9. configure nginx reverse proxy
10. configure firewall
11. configure MOTD scripts
12. create management aliases
13. save admin token file
14. configure backup cron
15. start service and run diagnostics on failure

## 5. Idempotency Notes

Safe to re-run for most operations:
- aliases are managed with markers (no duplication)
- backup cron is added once
- existing cert files can be reused/imported

## 6. Main Files

- Script: `vaultwarden-setup.sh`
- Env config: `/opt/vaultwarden/.env`
- Data: `/var/lib/vaultwarden`
- Service: `/etc/systemd/system/vaultwarden.service`
- Nginx site: `/etc/nginx/sites-available/vaultwarden`
- Log: `/var/log/vaultwarden-setup.log`
