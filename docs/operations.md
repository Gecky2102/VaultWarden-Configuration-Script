# Operations

## Aliases

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

Check if port 8000 is occupied:
```bash
ss -ltnp | grep ':8000'
```
