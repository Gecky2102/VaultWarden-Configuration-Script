#!/bin/bash

set -e

# =============================================================================
# Vaultwarden EE Configuration Script
# =============================================================================
# This script automates the installation and configuration of Vaultwarden EE
# Features:
# - System updates and dependency installation
# - Certificate management (wildcard and classic)
# - Version selection
# - Comprehensive logging
# - Command alias creation
# - Admin key storage
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Log file
LOG_FILE="/var/log/vaultwarden-setup.log"
ADMIN_KEY_FILE="/root/vaultwarden-admin-key.txt"

# Default configuration
VAULTWARDEN_DIR="/opt/vaultwarden"
DATA_DIR="/var/lib/vaultwarden"
ENV_FILE="$VAULTWARDEN_DIR/.env"
SYSTEMD_SERVICE="/etc/systemd/system/vaultwarden.service"

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

print_header() {
    clear
    echo -e "${PURPLE}${BOLD}"
    echo "═══════════════════════════════════════════════════════════════════"
    echo "      VaultWarden Configuration Script by Gecky2102"
    echo "═══════════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

print_step() {
    echo -e "${CYAN}${BOLD}[Step] $1${NC}"
    log "INFO" "$1"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    log "SUCCESS" "$1"
}

print_error() {
    echo -e "${RED}✗ Error: $1${NC}"
    log "ERROR" "$1"
}

print_warning() {
    echo -e "${YELLOW}⚠ Warning: $1${NC}"
    log "WARNING" "$1"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# =============================================================================
# System Checks
# =============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

check_os() {
    if [ ! -f /etc/os-release ]; then
        print_error "Cannot determine OS type"
        exit 1
    fi
    
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    
    print_success "Detected OS: $OS $VERSION"
}

check_internet() {
    print_step "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_error "No internet connection detected"
        exit 1
    fi
    print_success "Internet connection active"
}

# =============================================================================
# Dependency Management
# =============================================================================

install_dependencies() {
    print_step "Installing system dependencies..."
    
    case $OS in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y \
                curl \
                wget \
                git \
                build-essential \
                libssl-dev \
                pkg-config \
                sqlite3 \
                openssl \
                ca-certificates \
                gnupg \
                lsb-release \
                jq \
                certbot \
                python3-certbot-nginx \
                nginx \
                ufw \
                fail2ban \
                net-tools \
                lsof \
                psmisc \
                >> "$LOG_FILE" 2>&1
            ;;
        centos|rhel|fedora)
            yum update -y -q
            yum install -y \
                curl \
                wget \
                git \
                gcc \
                openssl-devel \
                sqlite \
                openssl \
                ca-certificates \
                jq \
                certbot \
                python3-certbot-nginx \
                nginx \
                firewalld \
                fail2ban \
                net-tools \
                lsof \
                psmisc \
                >> "$LOG_FILE" 2>&1
            ;;
        arch)
            pacman -Syu --noconfirm --quiet \
                curl \
                wget \
                git \
                base-devel \
                openssl \
                sqlite \
                jq \
                certbot \
                certbot-nginx \
                nginx \
                ufw \
                fail2ban \
                net-tools \
                lsof \
                psmisc \
                >> "$LOG_FILE" 2>&1
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    
    print_success "Dependencies installed successfully"
}

install_docker() {
    print_step "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        print_success "Docker already installed"
        return
    fi
    
    case $OS in
        ubuntu|debian)
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh >> "$LOG_FILE" 2>&1
            rm get-docker.sh
            ;;
        centos|rhel|fedora)
            yum install -y docker >> "$LOG_FILE" 2>&1
            ;;
        arch)
            pacman -S --noconfirm docker >> "$LOG_FILE" 2>&1
            ;;
    esac
    
    systemctl enable docker
    systemctl start docker
    
    print_success "Docker installed and started"
}

# =============================================================================
# User Input Functions
# =============================================================================

get_user_input() {
    print_header
    echo -e "${BOLD}Please provide the following information:${NC}\n"
    
    # Domain
    read -p "Enter your domain (e.g., vault.example.com): " DOMAIN
    while [ -z "$DOMAIN" ]; do
        print_error "Domain cannot be empty"
        read -p "Enter your domain: " DOMAIN
    done
    
    # Email for certificates
    read -p "Enter your email for Let's Encrypt: " EMAIL
    while [ -z "$EMAIL" ]; do
        print_error "Email cannot be empty"
        read -p "Enter your email: " EMAIL
    done
    
    # Certificate type
    echo ""
    echo "Certificate Type:"
    echo "  1) Classic certificate (single domain)"
    echo "  2) Wildcard certificate (*.example.com)"
    read -p "Select certificate type [1-2]: " CERT_TYPE
    while [[ ! "$CERT_TYPE" =~ ^[1-2]$ ]]; do
        print_error "Invalid selection"
        read -p "Select certificate type [1-2]: " CERT_TYPE
    done
    
    # Vaultwarden version
    echo ""
    read -p "Enter Vaultwarden version (or press Enter for latest): " VW_VERSION
    if [ -z "$VW_VERSION" ]; then
        VW_VERSION="latest"
    fi
    
    # Database type
    echo ""
    echo "Database Type:"
    echo "  1) SQLite (default, recommended for small deployments)"
    echo "  2) PostgreSQL (recommended for production)"
    echo "  3) MySQL/MariaDB"
    read -p "Select database type [1-3]: " DB_TYPE
    while [[ ! "$DB_TYPE" =~ ^[1-3]$ ]]; do
        print_error "Invalid selection"
        read -p "Select database type [1-3]: " DB_TYPE
    done
    
    if [ "$DB_TYPE" != "1" ]; then
        read -p "Enter database host: " DB_HOST
        read -p "Enter database port: " DB_PORT
        read -p "Enter database name: " DB_NAME
        read -p "Enter database user: " DB_USER
        read -sp "Enter database password: " DB_PASS
        echo ""
    fi
    
    # Admin token
    echo ""
    read -p "Generate random admin token? [Y/n]: " GEN_TOKEN
    if [[ "$GEN_TOKEN" =~ ^[Nn]$ ]]; then
        read -sp "Enter custom admin token: " ADMIN_TOKEN
        echo ""
    else
        ADMIN_TOKEN=$(openssl rand -base64 48)
    fi
    
    # SMTP Configuration
    echo ""
    read -p "Configure SMTP for email notifications? [Y/n]: " SETUP_SMTP
    if [[ ! "$SETUP_SMTP" =~ ^[Nn]$ ]]; then
        read -p "SMTP Host: " SMTP_HOST
        read -p "SMTP Port: " SMTP_PORT
        read -p "SMTP Username: " SMTP_USER
        read -sp "SMTP Password: " SMTP_PASS
        echo ""
        read -p "SMTP From Address: " SMTP_FROM
        
        # Validate SMTP fields if user chose to configure SMTP
        if [ -z "$SMTP_HOST" ] || [ -z "$SMTP_FROM" ]; then
            print_warning "SMTP_HOST and SMTP_FROM are required for email support"
            print_info "Disabling SMTP configuration..."
            SMTP_ENABLED="false"
        else
            SMTP_ENABLED="true"
        fi
    else
        SMTP_ENABLED="false"
    fi
    
    echo ""
    print_success "Configuration collected"
}

# =============================================================================
# Certificate Management
# =============================================================================

setup_certificates() {
    print_step "Setting up SSL certificates..."
    
    # Stop nginx if running
    systemctl stop nginx 2>/dev/null || true
    
    if [ "$CERT_TYPE" = "1" ]; then
        # Classic certificate
        print_info "Requesting classic SSL certificate for $DOMAIN..."
        certbot certonly --standalone \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL" \
            -d "$DOMAIN" \
            >> "$LOG_FILE" 2>&1
    else
        # Wildcard certificate
        print_info "Requesting wildcard SSL certificate for *.$DOMAIN..."
        certbot certonly --manual \
            --preferred-challenges=dns \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL" \
            -d "*.$DOMAIN" \
            -d "$DOMAIN" \
            >> "$LOG_FILE" 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificates obtained successfully"
        
        # Extract domain for cert path
        if [ "$CERT_TYPE" = "2" ]; then
            CERT_DOMAIN=$(echo "$DOMAIN" | sed 's/^[^.]*\.//')
        else
            CERT_DOMAIN="$DOMAIN"
        fi
        
        SSL_CERT="/etc/letsencrypt/live/$CERT_DOMAIN/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/$CERT_DOMAIN/privkey.pem"
    else
        print_error "Failed to obtain SSL certificates"
        exit 1
    fi
}

# =============================================================================
# Vaultwarden Installation
# =============================================================================

create_directories() {
    print_step "Creating directories..."
    
    mkdir -p "$VAULTWARDEN_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    print_success "Directories created"
}

configure_vaultwarden() {
    print_step "Configuring Vaultwarden..."
    
    # Build database URL
    case $DB_TYPE in
        1)
            DATABASE_URL="$DATA_DIR/db.sqlite3"
            ;;
        2)
            DATABASE_URL="postgresql://$DB_USER:$DB_PASS@$DB_HOST:$DB_PORT/$DB_NAME"
            ;;
        3)
            DATABASE_URL="mysql://$DB_USER:$DB_PASS@$DB_HOST:$DB_PORT/$DB_NAME"
            ;;
    esac
    
    # Create .env file
    cat > "$ENV_FILE" << EOF
# Vaultwarden Configuration
DOMAIN=https://$DOMAIN
DATABASE_URL=$DATABASE_URL
DATA_FOLDER=$DATA_DIR
WEB_VAULT_ENABLED=true
SIGNUPS_ALLOWED=true
INVITATIONS_ALLOWED=true
ADMIN_TOKEN=$ADMIN_TOKEN
ROCKET_PORT=8000
ROCKET_ADDRESS=0.0.0.0

# Security Settings
ROCKET_WORKERS=10
SHOW_PASSWORD_HINT=false
PASSWORD_ITERATIONS=600000
EOF

    # Add SMTP configuration only if enabled
    if [ "$SMTP_ENABLED" = "true" ]; then
        cat >> "$ENV_FILE" << EOF

# SMTP Configuration
SMTP_HOST=$SMTP_HOST
SMTP_FROM=$SMTP_FROM
SMTP_PORT=$SMTP_PORT
SMTP_SECURITY=starttls
SMTP_USERNAME=$SMTP_USER
SMTP_PASSWORD=$SMTP_PASS
EOF
    fi

    chmod 600 "$ENV_FILE"
    
    print_success "Configuration file created"
}

pull_vaultwarden_image() {
    print_step "Pulling Vaultwarden EE Docker image..."
    
    docker pull vaultwarden/server:$VW_VERSION >> "$LOG_FILE" 2>&1
    
    print_success "Docker image pulled"
}

create_systemd_service() {
    print_step "Creating systemd service..."
    
    cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Vaultwarden Password Manager
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=10
TimeoutStartSec=0
ExecStartPre=-/usr/bin/docker stop vaultwarden
ExecStartPre=-/usr/bin/docker rm vaultwarden
ExecStart=/usr/bin/docker run \\
    --name vaultwarden \\
    --rm \\
    -v $DATA_DIR:/data \\
    --env-file $ENV_FILE \\
    -p 127.0.0.1:8000:8000 \\
    vaultwarden/server:$VW_VERSION
ExecStop=/usr/bin/docker stop vaultwarden

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable vaultwarden
    
    print_success "Systemd service created"
}

# =============================================================================
# Nginx Configuration
# =============================================================================

configure_nginx() {
    print_step "Configuring Nginx reverse proxy..."
    
    cat > "/etc/nginx/sites-available/vaultwarden" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;

    client_max_body_size 525M;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /notifications/hub {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /notifications/hub/negotiate {
        proxy_pass http://127.0.0.1:8000;
    }
}
EOF

    # Enable site
    ln -sf /etc/nginx/sites-available/vaultwarden /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx configuration
    nginx -t >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        systemctl restart nginx
        print_success "Nginx configured and restarted"
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
}

# =============================================================================
# Firewall Configuration
# =============================================================================

configure_firewall() {
    print_step "Configuring firewall..."
    
    case $OS in
        ubuntu|debian|arch)
            ufw --force enable
            ufw allow 22/tcp
            ufw allow 80/tcp
            ufw allow 443/tcp
            ufw reload
            print_success "UFW firewall configured"
            ;;
        centos|rhel|fedora)
            systemctl enable firewalld
            systemctl start firewalld
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https
            firewall-cmd --reload
            print_success "Firewalld configured"
            ;;
    esac
}

# =============================================================================
# Command Aliases
# =============================================================================

create_aliases() {
    print_step "Creating command aliases..."
    
    cat >> /root/.bashrc << 'EOF'

# Vaultwarden Management Aliases
alias vw-start='systemctl start vaultwarden'
alias vw-stop='systemctl stop vaultwarden'
alias vw-restart='systemctl restart vaultwarden'
alias vw-status='systemctl status vaultwarden'
alias vw-logs='journalctl -u vaultwarden -f'
alias vw-update='docker pull vaultwarden/server:latest && systemctl restart vaultwarden'
alias vw-backup='tar -czf /root/vaultwarden-backup-$(date +%Y%m%d-%H%M%S).tar.gz /var/lib/vaultwarden'
alias vw-config='nano /opt/vaultwarden/.env'
alias vw-admin-key='cat /root/vaultwarden-admin-key.txt'
alias vw-cleanup='docker stop vaultwarden 2>/dev/null; docker rm vaultwarden 2>/dev/null; systemctl stop vaultwarden 2>/dev/null; echo "Cleanup completed"'
alias vw-diagnose='echo "=== Service Status ==="; systemctl status vaultwarden; echo ""; echo "=== Docker Logs ==="; docker logs vaultwarden 2>&1 | tail -20; echo ""; echo "=== Port 8000 ==="; ss -tuln | grep 8000'
EOF

    print_success "Command aliases created"
}

# =============================================================================
# Admin Key Storage
# =============================================================================

save_admin_key() {
    print_step "Saving admin access key..."
    
    cat > "$ADMIN_KEY_FILE" << EOF
Vaultwarden Admin Access Information
=====================================
Generated: $(date)
Domain: https://$DOMAIN
Admin Panel: https://$DOMAIN/admin
Admin Token: $ADMIN_TOKEN

Important: Keep this file secure and delete it after noting the token.
EOF

    chmod 600 "$ADMIN_KEY_FILE"
    
    print_success "Admin key saved to $ADMIN_KEY_FILE"
}

# =============================================================================
# Cleanup and Error Recovery
# =============================================================================

cleanup_existing() {
    print_step "Checking for existing installation..."
    
    # Stop and remove existing Docker container
    if docker ps -a | grep -q vaultwarden; then
        print_info "Stopping existing Vaultwarden container..."
        docker stop vaultwarden 2>/dev/null || true
        docker rm vaultwarden 2>/dev/null || true
        print_success "Existing container removed"
    fi
    
    # Stop and disable existing systemd service
    if systemctl list-units --full -all | grep -q vaultwarden.service; then
        print_info "Stopping existing Vaultwarden service..."
        systemctl stop vaultwarden 2>/dev/null || true
        systemctl disable vaultwarden 2>/dev/null || true
        print_success "Existing service stopped"
    fi
    
    # Check if port 8000 is in use
    if netstat -tuln 2>/dev/null | grep -q ":8000 " || ss -tuln 2>/dev/null | grep -q ":8000 "; then
        print_warning "Port 8000 is in use, attempting to free it..."
        # Find and kill process using port 8000
        local pid=$(lsof -ti:8000 2>/dev/null || fuser 8000/tcp 2>/dev/null | awk '{print $1}')
        if [ -n "$pid" ]; then
            kill -9 "$pid" 2>/dev/null || true
            sleep 2
            print_success "Port 8000 freed"
        fi
    fi
    
    print_success "Cleanup completed"
}

diagnose_startup_failure() {
    print_error "Service failed to start. Diagnosing..."
    echo ""
    
    # Check systemd logs
    print_info "Systemd logs:"
    journalctl -u vaultwarden -n 20 --no-pager
    echo ""
    
    # Check Docker logs if container exists
    if docker ps -a | grep -q vaultwarden; then
        print_info "Docker container logs:"
        docker logs vaultwarden 2>&1 | tail -20
        echo ""
    fi
    
    # Check port availability
    print_info "Checking port 8000..."
    if netstat -tuln 2>/dev/null | grep -q ":8000 " || ss -tuln 2>/dev/null | grep -q ":8000 "; then
        print_warning "Port 8000 is already in use!"
        netstat -tuln 2>/dev/null | grep ":8000 " || ss -tuln 2>/dev/null | grep ":8000 "
    else
        print_success "Port 8000 is available"
    fi
    
    # Check Docker status
    print_info "Docker service status:"
    systemctl status docker --no-pager -l | head -10
    echo ""
    
    # Check file permissions
    print_info "Directory permissions:"
    ls -la "$VAULTWARDEN_DIR" "$DATA_DIR" 2>/dev/null || true
    echo ""
}

# =============================================================================
# Service Management
# =============================================================================

start_services() {
    print_step "Starting Vaultwarden service..."
    
    # Try to start the service
    systemctl start vaultwarden
    sleep 5
    
    # Check if service is active
    if systemctl is-active --quiet vaultwarden; then
        print_success "Vaultwarden service started successfully"
        return 0
    fi
    
    # First attempt failed, diagnose and retry
    print_warning "First start attempt failed, diagnosing issue..."
    diagnose_startup_failure
    
    print_step "Attempting automatic recovery..."
    
    # Stop everything
    systemctl stop vaultwarden 2>/dev/null || true
    docker stop vaultwarden 2>/dev/null || true
    docker rm vaultwarden 2>/dev/null || true
    sleep 3
    
    # Free port 8000 if needed
    local pid=$(lsof -ti:8000 2>/dev/null || fuser 8000/tcp 2>/dev/null | awk '{print $1}')
    if [ -n "$pid" ]; then
        print_info "Killing process on port 8000 (PID: $pid)..."
        kill -9 "$pid" 2>/dev/null || true
        sleep 2
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    # Try starting again
    print_info "Retrying service start..."
    systemctl start vaultwarden
    sleep 5
    
    if systemctl is-active --quiet vaultwarden; then
        print_success "Vaultwarden service started successfully after recovery"
        return 0
    fi
    
    # Still failed, show detailed error
    print_error "Failed to start Vaultwarden service after recovery attempt"
    echo ""
    print_info "Final diagnostic information:"
    diagnose_startup_failure
    
    print_info "Manual commands to try:"
    echo "  1. Check configuration: cat $ENV_FILE"
    echo "  2. Test Docker manually: docker run --rm -v $DATA_DIR:/data vaultwarden/server:latest"
    echo "  3. Check systemd status: systemctl status vaultwarden"
    echo "  4. View full logs: journalctl -u vaultwarden -n 100"
    
    exit 1
}

# =============================================================================
# Backup Configuration
# =============================================================================

setup_backup() {
    print_step "Setting up automatic backups..."
    
    cat > /usr/local/bin/vaultwarden-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/root/vaultwarden-backups"
DATE=$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"
tar -czf "$BACKUP_DIR/vaultwarden-$DATE.tar.gz" /var/lib/vaultwarden
find "$BACKUP_DIR" -name "vaultwarden-*.tar.gz" -mtime +7 -delete
EOF

    chmod +x /usr/local/bin/vaultwarden-backup.sh
    
    # Add cron job for daily backup at 2 AM
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/vaultwarden-backup.sh") | crontab -
    
    print_success "Automatic daily backups configured"
}

# =============================================================================
# Final Summary
# =============================================================================

print_summary() {
    print_header
    
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║          Installation Completed Successfully!                    ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${BOLD}Access Information:${NC}"
    echo "  🌐 URL: https://$DOMAIN"
    echo "  🔐 Admin Panel: https://$DOMAIN/admin"
    echo "  🔑 Admin Token: Saved in $ADMIN_KEY_FILE"
    echo ""
    echo -e "${YELLOW}${BOLD}⚠ IMPORTANT: Load aliases first!${NC}"
    echo "  Run this command to enable management aliases:"
    echo -e "  ${CYAN}source ~/.bashrc${NC}"
    echo ""
    echo -e "${BOLD}Useful Commands (after loading aliases):${NC}"
    echo "  vw-start      - Start Vaultwarden"
    echo "  vw-stop       - Stop Vaultwarden"
    echo "  vw-restart    - Restart Vaultwarden"
    echo "  vw-status     - Check service status"
    echo "  vw-logs       - View real-time logs"
    echo "  vw-update     - Update to latest version"
    echo "  vw-backup     - Create manual backup"
    echo "  vw-config     - Edit configuration"
    echo "  vw-admin-key  - Display admin token"
    echo "  vw-cleanup    - Stop and remove containers"
    echo "  vw-diagnose   - Run diagnostics"
    echo ""
    echo -e "${BOLD}Important Files:${NC}"
    echo "  📁 Data Directory: $DATA_DIR"
    echo "  ⚙️  Configuration: $ENV_FILE"
    echo "  📝 Log File: $LOG_FILE"
    echo "  🔐 Admin Key: $ADMIN_KEY_FILE"
    echo ""
    echo -e "${YELLOW}${BOLD}Security Recommendations:${NC}"
    echo "  1. Delete $ADMIN_KEY_FILE after saving the token"
    echo "  2. Enable 2FA for all accounts"
    echo "  3. Regularly update Vaultwarden (use vw-update)"
    echo "  4. Monitor logs for suspicious activity"
    echo "  5. Keep regular backups"
    echo ""
    echo -e "${CYAN}For support, visit: https://github.com/dani-garcia/vaultwarden${NC}"
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    # Initialize log file
    touch "$LOG_FILE" 2>/dev/null || true
    log "INFO" "=== Vaultwarden Installation Started ==="
    
    # System checks
    print_header
    check_root
    check_os
    check_internet
    
    # Cleanup existing installation
    cleanup_existing
    
    # Get user input
    get_user_input
    
    # Installation steps
    install_dependencies
    install_docker
    create_directories
    setup_certificates
    configure_vaultwarden
    pull_vaultwarden_image
    create_systemd_service
    configure_nginx
    configure_firewall
    create_aliases
    save_admin_key
    setup_backup
    start_services
    
    # Final summary
    log "INFO" "=== Vaultwarden Installation Completed ==="
    print_summary
}

# Run main function
main
