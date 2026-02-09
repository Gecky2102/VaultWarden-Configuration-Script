# VaultWarden Configuration Script by Gecky2102

A comprehensive, automated Bash script for deploying and configuring Vaultwarden EE on Linux systems.

## Features

### 🚀 Complete Automation
- **System Updates**: Automatically updates system packages and installs all required dependencies
- **One-Command Deployment**: Single script execution handles the entire installation process
- **Multi-Distribution Support**: Works on Ubuntu, Debian, CentOS, RHEL, Fedora, and Arch Linux

### 🔐 Certificate Management
- **Classic SSL Certificates**: Single domain certificates via Let's Encrypt
- **Wildcard Certificates**: Support for wildcard domains (*.example.com)
- **Automatic Renewal**: Integrated with certbot for automatic certificate renewal
- **User-Prompted Configuration**: Interactive prompts for all certificate parameters

### 🐳 Docker Integration
- **Automated Docker Installation**: Installs Docker if not present
- **Version Selection**: Choose specific Vaultwarden versions or use latest
- **Systemd Integration**: Creates and manages systemd service for automatic startup

### 🗄️ Database Support
- **SQLite**: Default option, perfect for small deployments
- **PostgreSQL**: Recommended for production environments
- **MySQL/MariaDB**: Full support with connection configuration

### 📊 Logging & Monitoring
- **Clean Console Output**: Color-coded, fixed-width console display
- **Comprehensive Logging**: All operations logged to `/var/log/vaultwarden-setup.log`
- **Status Indicators**: Visual feedback for each step (✓, ✗, ⚠, ℹ)

### 🔑 Security Features
- **Admin Token Generation**: Automatic secure token generation or custom input
- **Secure Storage**: Admin key saved to protected file (`/root/vaultwarden-admin-key.txt`)
- **Firewall Configuration**: Automatic UFW/firewalld setup
- **Fail2ban Integration**: Protection against brute-force attacks

### ⚙️ Configuration Management
- **Interactive Setup**: User-friendly prompts for all configuration options
- **SMTP Configuration**: Optional email notification setup
- **Environment Variables**: Organized .env file for easy updates
- **Nginx Reverse Proxy**: Automatic configuration with SSL/TLS

### 🛠️ Command Aliases
The script creates convenient aliases for Vaultwarden management:
- `vw-start` - Start Vaultwarden service
- `vw-stop` - Stop Vaultwarden service
- `vw-restart` - Restart Vaultwarden service
- `vw-status` - Check service status
- `vw-logs` - View real-time logs
- `vw-update` - Update to latest version
- `vw-backup` - Create manual backup
- `vw-config` - Edit configuration
- `vw-admin-key` - Display admin token
- `vw-cleanup` - Stop and remove containers/services
- `vw-diagnose` - Run diagnostics for troubleshooting

### 💾 Backup System
- **Automatic Backups**: Daily automated backups at 2 AM
- **Retention Policy**: Keeps backups for 7 days
- **Manual Backups**: Easy manual backup creation with `vw-backup`

## Prerequisites

- Linux system (Ubuntu 20.04+, Debian 10+, CentOS 7+, RHEL 7+, Fedora 30+, Arch Linux)
- Root access (sudo)
- Domain name pointed to your server's IP address
- Open ports: 80 (HTTP), 443 (HTTPS), 22 (SSH)

## Installation

### Quick Start

1. Download the script:
```bash
wget https://raw.githubusercontent.com/gecky2102/VaultWarden-Configuration-Script/main/vaultwarden-setup.sh
```

2. Make it executable:
```bash
chmod +x vaultwarden-setup.sh
```

3. Run as root:
```bash
sudo ./vaultwarden-setup.sh
```

### Interactive Configuration

The script will prompt you for:

1. **Domain Configuration**
   - Your domain name (e.g., vault.example.com)
   - Email address for Let's Encrypt notifications

2. **Certificate Type**
   - Option 1: Classic certificate (single domain)
   - Option 2: Wildcard certificate (*.example.com)

3. **Vaultwarden Version**
   - Specific version number or "latest"

4. **Database Configuration**
   - SQLite (default)
   - PostgreSQL (with connection details)
   - MySQL/MariaDB (with connection details)

5. **Admin Token**
   - Auto-generate secure token (recommended)
   - Custom token input

6. **SMTP Configuration** (optional)
   - SMTP server details for email notifications

## Usage

### Starting/Stopping Vaultwarden

```bash
# Start service
vw-start

# Stop service
vw-stop

# Restart service
vw-restart

# Check status
vw-status

# Cleanup (stop and remove everything)
vw-cleanup
```

### Troubleshooting

```bash
# Run diagnostics
vw-diagnose

# View logs in real-time
vw-logs
```

### Updating Vaultwarden

```bash
# Update to latest version
vw-update
```

### Backups

```bash
# Create manual backup
vw-backup

# Backups are stored in /root/vaultwarden-backups/
# Automatic backups run daily at 2 AM
```

### Configuration

```bash
# Edit configuration
vw-config

# After editing, restart the service
vw-restart
```

### Admin Access

```bash
# View admin token
vw-admin-key

# Or directly access the file
cat /root/vaultwarden-admin-key.txt
```

Access admin panel at: `https://your-domain.com/admin`

## File Locations

| Purpose | Location |
|---------|----------|
| Vaultwarden Directory | `/opt/vaultwarden` |
| Data Directory | `/var/lib/vaultwarden` |
| Configuration File | `/opt/vaultwarden/.env` |
| Installation Log | `/var/log/vaultwarden-setup.log` |
| Admin Key | `/root/vaultwarden-admin-key.txt` |
| Systemd Service | `/etc/systemd/system/vaultwarden.service` |
| Nginx Config | `/etc/nginx/sites-available/vaultwarden` |
| Backup Directory | `/root/vaultwarden-backups` |

## Security Recommendations

1. **Delete Admin Key File**: After noting the admin token, delete `/root/vaultwarden-admin-key.txt`
2. **Enable 2FA**: Enable two-factor authentication for all accounts
3. **Regular Updates**: Use `vw-update` to keep Vaultwarden current
4. **Monitor Logs**: Regularly check logs with `vw-logs` for suspicious activity
5. **Secure Backups**: Store backups in a secure, off-site location
6. **Firewall Rules**: Ensure only necessary ports are open
7. **Strong Passwords**: Enforce strong password policies

## Troubleshooting

### Service Won't Start

```bash
# Check service status
systemctl status vaultwarden

# View detailed logs
journalctl -u vaultwarden -n 50

# Check Docker container
docker ps -a
docker logs vaultwarden
```

### Certificate Issues

```bash
# Check certificates
certbot certificates

# Renew certificates manually
certbot renew

# Test nginx configuration
nginx -t
```

### Database Connection Problems

```bash
# Edit configuration
nano /opt/vaultwarden/.env

# Test database connection (PostgreSQL example)
psql -h DB_HOST -U DB_USER -d DB_NAME

# Restart after changes
systemctl restart vaultwarden
```

### Nginx Issues

```bash
# Test configuration
nginx -t

# Check nginx status
systemctl status nginx

# View nginx logs
tail -f /var/log/nginx/error.log
```

## Advanced Configuration

### Custom Port

Edit `/opt/vaultwarden/.env`:
```bash
ROCKET_PORT=8080
```

Update nginx configuration and restart both services.

### Disable Signups

Edit `/opt/vaultwarden/.env`:
```bash
SIGNUPS_ALLOWED=false
```

Restart service: `vw-restart`

### Enable Web Vault

The web vault is enabled by default. To disable:
```bash
WEB_VAULT_ENABLED=false
```

### Custom Data Directory

Before running the script, modify the `DATA_DIR` variable in `vaultwarden-setup.sh`.

## Uninstallation

```bash
# Stop and disable service
systemctl stop vaultwarden
systemctl disable vaultwarden

# Remove Docker container and image
docker stop vaultwarden
docker rm vaultwarden
docker rmi vaultwarden/server

# Remove files
rm -rf /opt/vaultwarden
rm -rf /var/lib/vaultwarden
rm /etc/systemd/system/vaultwarden.service
rm /etc/nginx/sites-available/vaultwarden
rm /etc/nginx/sites-enabled/vaultwarden

# Reload systemd
systemctl daemon-reload

# Restart nginx
systemctl restart nginx
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [Vaultwarden](https://github.com/dani-garcia/vaultwarden) - The excellent Bitwarden-compatible server
- [Let's Encrypt](https://letsencrypt.org/) - Free SSL certificates
- [Docker](https://www.docker.com/) - Container platform

## Support

For issues and questions:
- Open an issue on GitHub
- Visit [Vaultwarden Discussions](https://github.com/dani-garcia/vaultwarden/discussions)

## Disclaimer

This script is provided as-is, without any warranties. Always review scripts before running them with root privileges. Test in a non-production environment first.

## Credits
Created with ❤️ by [gecky2102](https://gmasiero.it)