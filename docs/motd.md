# Custom MOTD Dashboard

The setup can install an optional custom MOTD status dashboard shown at SSH login.

## What setup does

When MOTD configuration runs:
1. disables execute bit on existing scripts in `/etc/update-motd.d/*`
2. optionally writes `/etc/update-motd.d/99-vaultwarden`
3. sets it executable

The dashboard shows:
- Vaultwarden container state and uptime
- external endpoint check against configured `ACCESS_URL`
- docker summary and memory usage
- basic system stats (CPU/RAM/Disk)
- SSH snapshot (port, config flags, users, failed attempts)

## Manage MOTD manually

Enable custom MOTD script:
```bash
chmod +x /etc/update-motd.d/99-vaultwarden
```

Disable custom MOTD script:
```bash
chmod -x /etc/update-motd.d/99-vaultwarden
```

Preview output:
```bash
bash /etc/update-motd.d/99-vaultwarden
```
