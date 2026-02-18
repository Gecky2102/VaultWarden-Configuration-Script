# Operations

## Aliases

If you re-run the installer and choose `Commands-only` mode, it refreshes aliases and `vw-help` without reconfiguring the full stack.

After setup:
```bash
source ~/.bashrc
```

Main aliases:
- `vw-start`
- `vw-stop`
- `vw-restart`
- `vw-status`
- `vw-logs`
- `vw-update`
- `vw-backup`
- `vw-config`
- `vw-admin-key`
- `vw-cleanup`
- `vw-diagnose`
- `vw-help`
- `vw-edit-config`

`vw-edit-config` updates live network/domain settings and rewrites nginx safely.

Examples:
```bash
vw-edit-config --show
vw-edit-config --port 443
vw-edit-config --internal-port 443 --external-port 4443 --domain vault.example.com
```

## Logs

- install log: `/var/log/vaultwarden-setup.log`
- service logs: `journalctl -u vaultwarden -n 100`
- live logs: `journalctl -u vaultwarden -f`

## Backups

- backup script: `/usr/local/bin/vaultwarden-backup.sh`
- retention: 7 days
- scheduled: daily 02:00 via crontab

## Update Vaultwarden

```bash
docker pull vaultwarden/server:latest
systemctl restart vaultwarden
```

Or use:
```bash
vw-update
```

## Basic Troubleshooting

Service status:
```bash
systemctl status vaultwarden
```

Docker logs:
```bash
docker logs vaultwarden --tail 100
```

Nginx test:
```bash
nginx -t
```

Inspect active vhosts for your domain:
```bash
nginx -T 2>/dev/null | grep -n "server_name vault.example.com"
```

Check fullchain contains leaf + intermediate:
```bash
grep -c "BEGIN CERTIFICATE" /etc/ssl/vaultwarden/your-domain.fullchain.pem
```

Check if port 8000 is occupied:
```bash
ss -ltnp | grep ':8000'
```
