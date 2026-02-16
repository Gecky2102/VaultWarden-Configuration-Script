#!/bin/bash

set -Eeuo pipefail

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
NGINX_SITE="/etc/nginx/sites-available/vaultwarden"
ALIAS_FILE="/root/.bashrc"
ALIAS_MARKER_START="# >>> VAULTWARDEN ALIASES START >>>"
ALIAS_MARKER_END="# <<< VAULTWARDEN ALIASES END <<<"
BACKUP_SCRIPT="/usr/local/bin/vaultwarden-backup.sh"
BACKUP_CRON_LINE="0 2 * * * /usr/local/bin/vaultwarden-backup.sh"
MANUAL_CERT_DIR="/etc/ssl/vaultwarden"

# Runtime variables (initialized for nounset safety)
OS=""
VERSION=""
DOMAIN=""
EMAIL=""
CERT_TYPE=""
VW_VERSION="latest"
DB_TYPE="1"
DB_HOST=""
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASS=""
GEN_TOKEN=""
ADMIN_TOKEN=""
SETUP_SMTP=""
SMTP_HOST=""
SMTP_PORT=""
SMTP_USER=""
SMTP_PASS=""
SMTP_FROM=""
SMTP_ENABLED="false"
SSL_CERT=""
SSL_KEY=""
DATABASE_URL=""
EXTERNAL_HTTPS_PORT="443"
INTERNAL_HTTPS_PORT="443"
ACCESS_URL=""
WILDCARD_BASE_DOMAIN=""
WILDCARD_ORGANIZATION=""
WILDCARD_CERT_PATH=""
WILDCARD_KEY_PATH=""
WILDCARD_CSR_PATH=""
WILDCARD_FULLCHAIN_PATH=""
EXISTING_CERT_PATH=""
EXISTING_KEY_PATH=""
SETUP_CUSTOM_MOTD="false"
SETUP_CUSTOM_MOTD_INPUT=""

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

handle_error() {
    local exit_code=$?
    local line_no=${1:-unknown}
    print_error "Unexpected error at line ${line_no}. Check $LOG_FILE for details."
    exit "$exit_code"
}

trap 'handle_error $LINENO' ERR

is_valid_port() {
    local port=$1
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

ensure_file_exists() {
    local file_path=$1
    local description=$2
    while [ ! -f "$file_path" ]; do
        print_error "$description not found: $file_path"
        read -e -p "Insert a valid path for $description: " file_path
    done
    echo "$file_path"
}

wait_for_existing_file() {
    local file_path=$1
    local description=$2
    local user_input=""
    while [ ! -f "$file_path" ]; do
        print_warning "$description not found: $file_path"
        read -e -p "Press ENTER to re-check or type a different path: " user_input
        if [ -n "$user_input" ]; then
            file_path=$user_input
        fi
    done
    echo "$file_path"
}

validate_private_key_file() {
    local key_path=$1
    if ! openssl pkey -in "$key_path" -noout >/dev/null 2>&1; then
        print_error "Invalid private key file: $key_path"
        exit 1
    fi
}

validate_csr_file() {
    local csr_path=$1
    if ! openssl req -in "$csr_path" -noout >/dev/null 2>&1; then
        print_error "Invalid CSR file: $csr_path"
        exit 1
    fi
}

validate_csr_contains_organization() {
    local csr_path=$1
    local subject
    subject=$(openssl req -in "$csr_path" -noout -subject -nameopt RFC2253 2>/dev/null || true)
    if ! printf "%s" "$subject" | grep -Eq '(^|,)O='; then
        print_error "CSR missing Organization (O) field: $csr_path"
        exit 1
    fi
}

validate_certificate_file() {
    local cert_path=$1
    if ! openssl x509 -in "$cert_path" -noout >/dev/null 2>&1; then
        print_error "Invalid certificate file: $cert_path"
        exit 1
    fi
}

validate_key_matches_certificate() {
    local key_path=$1
    local cert_path=$2
    local key_pub cert_pub
    key_pub=$(openssl pkey -in "$key_path" -pubout 2>/dev/null | openssl sha256 2>/dev/null | awk '{print $2}')
    cert_pub=$(openssl x509 -in "$cert_path" -pubkey -noout 2>/dev/null | openssl sha256 2>/dev/null | awk '{print $2}')
    if [ -z "$key_pub" ] || [ -z "$cert_pub" ] || [ "$key_pub" != "$cert_pub" ]; then
        print_error "Private key does not match certificate: key=$key_path cert=$cert_path"
        exit 1
    fi
}

is_valid_domain_name() {
    local domain=$1
    [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[A-Za-z]{2,}$ ]]
}

is_valid_email_address() {
    local email=$1
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

domain_matches_pattern() {
    local domain=$1
    local pattern=$2
    if [[ "$pattern" == \*.* ]]; then
        local suffix=${pattern#*.}
        [[ "$domain" == *".${suffix}" ]] && [[ "$domain" != "$suffix" ]]
    else
        [[ "$domain" == "$pattern" ]]
    fi
}

certificate_covers_domain() {
    local cert_path=$1
    local expected_domain=$2
    local cert_names=""
    local cn=""

    cert_names=$(openssl x509 -in "$cert_path" -noout -ext subjectAltName 2>/dev/null | tr ',' '\n' | sed -n 's/.*DNS:[[:space:]]*//p' || true)
    cn=$(openssl x509 -in "$cert_path" -noout -subject -nameopt RFC2253 2>/dev/null | sed -n 's/^subject=//p' | tr ',' '\n' | sed -n 's/^CN=//p' | head -n 1 || true)

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        if domain_matches_pattern "$expected_domain" "$name"; then
            return 0
        fi
    done <<< "$cert_names"

    if [ -n "$cn" ] && domain_matches_pattern "$expected_domain" "$cn"; then
        return 0
    fi

    return 1
}

validate_certificate_covers_domain() {
    local cert_path=$1
    local expected_domain=$2
    if ! certificate_covers_domain "$cert_path" "$expected_domain"; then
        print_error "Certificate does not cover domain '$expected_domain': $cert_path"
        exit 1
    fi
}

validate_output_path_writable() {
    local out_path=$1
    local out_dir
    out_dir=$(dirname "$out_path")
    mkdir -p "$out_dir"
    if [ -d "$out_path" ]; then
        print_error "Output path is a directory, expected file path: $out_path"
        exit 1
    fi
    if [ ! -w "$out_dir" ]; then
        print_error "Output directory is not writable: $out_dir"
        exit 1
    fi
}

validate_nginx_config_matches_inputs() {
    local redirect_port_suffix=""
    local expected_redirect=""

    if [ "$EXTERNAL_HTTPS_PORT" != "443" ]; then
        redirect_port_suffix=":$EXTERNAL_HTTPS_PORT"
    fi
    expected_redirect="return 301 https://\\\$server_name${redirect_port_suffix}\\\$request_uri;"

    if ! grep -qF "server_name $DOMAIN;" "$NGINX_SITE"; then
        print_error "Nginx config mismatch: server_name is not '$DOMAIN'"
        exit 1
    fi

    if ! grep -qF "ssl_certificate $SSL_CERT;" "$NGINX_SITE"; then
        print_error "Nginx config mismatch: ssl_certificate path is not '$SSL_CERT'"
        exit 1
    fi

    if ! grep -qF "ssl_certificate_key $SSL_KEY;" "$NGINX_SITE"; then
        print_error "Nginx config mismatch: ssl_certificate_key path is not '$SSL_KEY'"
        exit 1
    fi

    if ! grep -qF "proxy_pass http://127.0.0.1:8000;" "$NGINX_SITE"; then
        print_error "Nginx config mismatch: proxy_pass must target 127.0.0.1:8000"
        exit 1
    fi

    if [ "$INTERNAL_HTTPS_PORT" = "80" ]; then
        if ! grep -qF "listen 80 ssl http2;" "$NGINX_SITE"; then
            print_error "Nginx config mismatch: expected TLS listener on internal port 80"
            exit 1
        fi
    else
        if ! grep -qF "listen $INTERNAL_HTTPS_PORT ssl http2;" "$NGINX_SITE"; then
            print_error "Nginx config mismatch: expected TLS listener on internal port $INTERNAL_HTTPS_PORT"
            exit 1
        fi
        if ! grep -qF "$expected_redirect" "$NGINX_SITE"; then
            print_error "Nginx config mismatch: expected HTTP redirect '$expected_redirect'"
            exit 1
        fi
    fi
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
    if [ "$(uname -s)" != "Linux" ]; then
        print_error "Unsupported OS. This script currently supports Linux hosts with systemd."
        exit 1
    fi

    if [ ! -f /etc/os-release ]; then
        print_error "Cannot determine OS type"
        exit 1
    fi
    
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    
    print_success "Detected OS: $OS $VERSION"

    if ! command -v systemctl >/dev/null 2>&1; then
        print_error "systemctl not found. A systemd-based distribution is required."
        exit 1
    fi
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
    while [ -z "$DOMAIN" ] || ! is_valid_domain_name "$DOMAIN"; do
        print_error "Invalid domain format"
        read -p "Enter your domain: " DOMAIN
    done
    
    # Certificate type
    echo ""
    echo "Certificate Type:"
    echo "  1) Let's Encrypt (single domain, automatic)"
    echo "  2) Wildcard manual flow (generate private key + CSR, then import signed cert)"
    echo "  3) Use existing certificate and key paths"
    echo "  4) Resume wildcard flow from existing generated key/CSR"
    read -p "Select certificate type [1-4]: " CERT_TYPE
    while [[ ! "$CERT_TYPE" =~ ^[1-4]$ ]]; do
        print_error "Invalid selection"
        read -p "Select certificate type [1-4]: " CERT_TYPE
    done

    if [ "$CERT_TYPE" = "1" ]; then
        read -p "Enter your email for Let's Encrypt: " EMAIL
        while [ -z "$EMAIL" ] || ! is_valid_email_address "$EMAIL"; do
            print_error "Invalid email format"
            read -p "Enter your email: " EMAIL
        done
    elif [ "$CERT_TYPE" = "2" ]; then
        WILDCARD_BASE_DOMAIN=$(echo "$DOMAIN" | sed 's/^[^.]*\.//')
        if [ -z "$WILDCARD_BASE_DOMAIN" ] || [ "$WILDCARD_BASE_DOMAIN" = "$DOMAIN" ]; then
            read -p "Enter wildcard base domain (e.g., example.com): " WILDCARD_BASE_DOMAIN
        else
            read -p "Wildcard base domain [$WILDCARD_BASE_DOMAIN]: " input_base_domain
            WILDCARD_BASE_DOMAIN=${input_base_domain:-$WILDCARD_BASE_DOMAIN}
        fi

        while [ -z "$WILDCARD_BASE_DOMAIN" ] || [[ ! "$WILDCARD_BASE_DOMAIN" =~ \. ]]; do
            print_error "Invalid wildcard base domain"
            read -p "Enter wildcard base domain (e.g., example.com): " WILDCARD_BASE_DOMAIN
        done

        local default_key_path="$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.key"
        local default_csr_path="$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.csr"
        local default_signed_cert_path="$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.signed.fullchain.pem"
        local default_fullchain_path="$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.fullchain.pem"

        read -p "Organization (O) for wildcard CSR: " WILDCARD_ORGANIZATION
        while [ -z "$WILDCARD_ORGANIZATION" ]; do
            print_error "Organization (O) cannot be empty"
            read -p "Organization (O) for wildcard CSR: " WILDCARD_ORGANIZATION
        done

        read -e -p "Path for wildcard private key [$default_key_path]: " WILDCARD_KEY_PATH
        WILDCARD_KEY_PATH=${WILDCARD_KEY_PATH:-$default_key_path}

        read -e -p "Path for wildcard CSR [$default_csr_path]: " WILDCARD_CSR_PATH
        WILDCARD_CSR_PATH=${WILDCARD_CSR_PATH:-$default_csr_path}

        read -e -p "Path where you will place signed wildcard fullchain [$default_signed_cert_path]: " WILDCARD_CERT_PATH
        WILDCARD_CERT_PATH=${WILDCARD_CERT_PATH:-$default_signed_cert_path}

        read -e -p "Path for final wildcard fullchain used by nginx [$default_fullchain_path]: " WILDCARD_FULLCHAIN_PATH
        WILDCARD_FULLCHAIN_PATH=${WILDCARD_FULLCHAIN_PATH:-$default_fullchain_path}
        validate_output_path_writable "$WILDCARD_FULLCHAIN_PATH"
    elif [ "$CERT_TYPE" = "3" ]; then
        read -e -p "Path to existing fullchain certificate: " EXISTING_CERT_PATH
        EXISTING_CERT_PATH=$(ensure_file_exists "$EXISTING_CERT_PATH" "certificate file")
        validate_certificate_file "$EXISTING_CERT_PATH"
        validate_certificate_covers_domain "$EXISTING_CERT_PATH" "$DOMAIN"
        read -e -p "Path to existing private key: " EXISTING_KEY_PATH
        EXISTING_KEY_PATH=$(ensure_file_exists "$EXISTING_KEY_PATH" "private key")
        validate_private_key_file "$EXISTING_KEY_PATH"
        validate_key_matches_certificate "$EXISTING_KEY_PATH" "$EXISTING_CERT_PATH"
    else
        read -p "Enter wildcard base domain used before (e.g., example.com): " WILDCARD_BASE_DOMAIN
        while [ -z "$WILDCARD_BASE_DOMAIN" ] || [[ ! "$WILDCARD_BASE_DOMAIN" =~ \. ]]; do
            print_error "Invalid wildcard base domain"
            read -p "Enter wildcard base domain (e.g., example.com): " WILDCARD_BASE_DOMAIN
        done

        local default_key_path="$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.key"
        local default_csr_path="$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.csr"
        local default_signed_cert_path="$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.signed.fullchain.pem"
        local default_fullchain_path="$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.fullchain.pem"

        if [ -f "$default_key_path" ]; then
            print_success "Found existing wildcard private key: $default_key_path"
        else
            print_warning "Wildcard private key not found at default path: $default_key_path"
        fi

        if [ -f "$default_csr_path" ]; then
            print_success "Found existing wildcard CSR: $default_csr_path"
        else
            print_warning "Wildcard CSR not found at default path: $default_csr_path"
        fi

        read -e -p "Path to existing wildcard private key [$default_key_path]: " WILDCARD_KEY_PATH
        WILDCARD_KEY_PATH=${WILDCARD_KEY_PATH:-$default_key_path}
        WILDCARD_KEY_PATH=$(ensure_file_exists "$WILDCARD_KEY_PATH" "wildcard private key")
        validate_private_key_file "$WILDCARD_KEY_PATH"

        read -e -p "Path to existing wildcard CSR [$default_csr_path]: " WILDCARD_CSR_PATH
        WILDCARD_CSR_PATH=${WILDCARD_CSR_PATH:-$default_csr_path}
        WILDCARD_CSR_PATH=$(ensure_file_exists "$WILDCARD_CSR_PATH" "wildcard CSR")
        validate_csr_file "$WILDCARD_CSR_PATH"
        validate_csr_contains_organization "$WILDCARD_CSR_PATH"

        read -e -p "Path where signed wildcard fullchain is/will be available [$default_signed_cert_path]: " WILDCARD_CERT_PATH
        WILDCARD_CERT_PATH=${WILDCARD_CERT_PATH:-$default_signed_cert_path}

        read -e -p "Path for final wildcard fullchain used by nginx [$default_fullchain_path]: " WILDCARD_FULLCHAIN_PATH
        WILDCARD_FULLCHAIN_PATH=${WILDCARD_FULLCHAIN_PATH:-$default_fullchain_path}
        validate_output_path_writable "$WILDCARD_FULLCHAIN_PATH"
    fi

    echo ""
    read -p "External HTTPS port exposed to users [443]: " EXTERNAL_HTTPS_PORT
    EXTERNAL_HTTPS_PORT=${EXTERNAL_HTTPS_PORT:-443}
    while ! is_valid_port "$EXTERNAL_HTTPS_PORT"; do
        print_error "Invalid external HTTPS port"
        read -p "External HTTPS port [443]: " EXTERNAL_HTTPS_PORT
        EXTERNAL_HTTPS_PORT=${EXTERNAL_HTTPS_PORT:-443}
    done

    read -p "Internal HTTPS port on this server [443]: " INTERNAL_HTTPS_PORT
    INTERNAL_HTTPS_PORT=${INTERNAL_HTTPS_PORT:-443}
    while ! is_valid_port "$INTERNAL_HTTPS_PORT"; do
        print_error "Invalid internal HTTPS port"
        read -p "Internal HTTPS port [443]: " INTERNAL_HTTPS_PORT
        INTERNAL_HTTPS_PORT=${INTERNAL_HTTPS_PORT:-443}
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

        while [ -z "$DB_HOST" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ]; do
            print_error "Database host/name/user are required"
            read -p "Enter database host: " DB_HOST
            read -p "Enter database name: " DB_NAME
            read -p "Enter database user: " DB_USER
        done

        while ! is_valid_port "$DB_PORT"; do
            print_error "Invalid database port"
            read -p "Enter database port: " DB_PORT
        done
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
    
    if [ "$EXTERNAL_HTTPS_PORT" = "443" ]; then
        ACCESS_URL="https://$DOMAIN"
    else
        ACCESS_URL="https://$DOMAIN:$EXTERNAL_HTTPS_PORT"
    fi

    echo ""
    read -p "Install custom Vaultwarden MOTD dashboard? [Y/n]: " SETUP_CUSTOM_MOTD_INPUT
    if [[ "$SETUP_CUSTOM_MOTD_INPUT" =~ ^[Nn]$ ]]; then
        SETUP_CUSTOM_MOTD="false"
    else
        SETUP_CUSTOM_MOTD="true"
    fi

    echo ""
    print_success "Configuration collected"
}

# =============================================================================
# Certificate Management
# =============================================================================

setup_certificates() {
    print_step "Setting up SSL certificates..."
    
    if [ "$CERT_TYPE" = "1" ]; then
        # Automatic Let's Encrypt certificate
        print_info "Requesting classic SSL certificate for $DOMAIN..."

        # Stop nginx if running to free standalone challenge port
        systemctl stop nginx 2>/dev/null || true

        if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
            print_info "Existing Let's Encrypt certificate found for $DOMAIN, reusing it."
            SSL_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
            SSL_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
            validate_certificate_file "$SSL_CERT"
            validate_private_key_file "$SSL_KEY"
            validate_key_matches_certificate "$SSL_KEY" "$SSL_CERT"
            validate_certificate_covers_domain "$SSL_CERT" "$DOMAIN"
            print_success "SSL certificates ready"
            return
        fi

        certbot certonly --standalone \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL" \
            -d "$DOMAIN" \
            >> "$LOG_FILE" 2>&1

        SSL_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
        validate_certificate_file "$SSL_CERT"
        validate_private_key_file "$SSL_KEY"
        validate_key_matches_certificate "$SSL_KEY" "$SSL_CERT"
        validate_certificate_covers_domain "$SSL_CERT" "$DOMAIN"
        print_success "SSL certificates obtained successfully"
        return
    fi

    if [ "$CERT_TYPE" = "2" ] || [ "$CERT_TYPE" = "4" ]; then
        mkdir -p "$MANUAL_CERT_DIR"

        if [ "$CERT_TYPE" = "2" ]; then
            WILDCARD_KEY_PATH=${WILDCARD_KEY_PATH:-"$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.key"}
            WILDCARD_CSR_PATH=${WILDCARD_CSR_PATH:-"$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.csr"}
            WILDCARD_FULLCHAIN_PATH=${WILDCARD_FULLCHAIN_PATH:-"$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.fullchain.pem"}
        else
            WILDCARD_FULLCHAIN_PATH=${WILDCARD_FULLCHAIN_PATH:-"$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.fullchain.pem"}
        fi

        if [ "$CERT_TYPE" = "2" ]; then
            mkdir -p "$(dirname "$WILDCARD_KEY_PATH")" "$(dirname "$WILDCARD_CSR_PATH")" "$(dirname "$WILDCARD_FULLCHAIN_PATH")"
            if [ ! -f "$WILDCARD_KEY_PATH" ]; then
                print_info "Generating private key: $WILDCARD_KEY_PATH"
                openssl genrsa -out "$WILDCARD_KEY_PATH" 4096 >> "$LOG_FILE" 2>&1
                chmod 600 "$WILDCARD_KEY_PATH"
            else
                print_info "Private key already exists: $WILDCARD_KEY_PATH"
            fi

            print_info "Generating CSR for *.$WILDCARD_BASE_DOMAIN and $WILDCARD_BASE_DOMAIN..."
            local csr_organization="${WILDCARD_ORGANIZATION//\//-}"
            if ! openssl req -new \
                -key "$WILDCARD_KEY_PATH" \
                -out "$WILDCARD_CSR_PATH" \
                -subj "/O=$csr_organization/CN=*.$WILDCARD_BASE_DOMAIN" \
                -addext "subjectAltName=DNS:$WILDCARD_BASE_DOMAIN,DNS:*.$WILDCARD_BASE_DOMAIN" \
                >> "$LOG_FILE" 2>&1; then
                local openssl_cfg
                openssl_cfg=$(mktemp)
                cat > "$openssl_cfg" << EOF
[req]
distinguished_name = req_dn
req_extensions = req_ext
prompt = no

[req_dn]
O = $csr_organization
CN = *.$WILDCARD_BASE_DOMAIN

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $WILDCARD_BASE_DOMAIN
DNS.2 = *.$WILDCARD_BASE_DOMAIN
EOF
                openssl req -new \
                    -key "$WILDCARD_KEY_PATH" \
                    -out "$WILDCARD_CSR_PATH" \
                    -config "$openssl_cfg" \
                    >> "$LOG_FILE" 2>&1
                rm -f "$openssl_cfg"
            fi

            validate_private_key_file "$WILDCARD_KEY_PATH"
            validate_csr_file "$WILDCARD_CSR_PATH"
            validate_csr_contains_organization "$WILDCARD_CSR_PATH"

            echo ""
            print_info "Private key generated: $WILDCARD_KEY_PATH"
            print_info "CSR generated: $WILDCARD_CSR_PATH"
            print_info "Upload this CSR to your certificate provider."
            print_info "Then place the signed fullchain at the configured path and confirm."
            echo ""
        else
            validate_private_key_file "$WILDCARD_KEY_PATH"
            validate_csr_file "$WILDCARD_CSR_PATH"
            validate_csr_contains_organization "$WILDCARD_CSR_PATH"
            print_info "Resuming wildcard flow with existing key/CSR:"
            print_info "Private key: $WILDCARD_KEY_PATH"
            print_info "CSR: $WILDCARD_CSR_PATH"
        fi

        if [ -z "$WILDCARD_CERT_PATH" ]; then
            WILDCARD_CERT_PATH="$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.signed.fullchain.pem"
        fi
        print_info "Place the signed wildcard fullchain at: $WILDCARD_CERT_PATH"
        WILDCARD_CERT_PATH=$(wait_for_existing_file "$WILDCARD_CERT_PATH" "signed certificate/fullchain")
        validate_certificate_file "$WILDCARD_CERT_PATH"
        validate_key_matches_certificate "$WILDCARD_KEY_PATH" "$WILDCARD_CERT_PATH"
        validate_certificate_covers_domain "$WILDCARD_CERT_PATH" "$DOMAIN"
        validate_certificate_covers_domain "$WILDCARD_CERT_PATH" "*.$WILDCARD_BASE_DOMAIN"

        if [ -z "$WILDCARD_FULLCHAIN_PATH" ]; then
            WILDCARD_FULLCHAIN_PATH="$MANUAL_CERT_DIR/${WILDCARD_BASE_DOMAIN}.fullchain.pem"
        else
            print_info "Using wildcard fullchain output path: $WILDCARD_FULLCHAIN_PATH"
        fi
        validate_output_path_writable "$WILDCARD_FULLCHAIN_PATH"

        if [ "$WILDCARD_CERT_PATH" != "$WILDCARD_FULLCHAIN_PATH" ]; then
            cp "$WILDCARD_CERT_PATH" "$WILDCARD_FULLCHAIN_PATH"
        else
            print_info "Signed fullchain already in final output path."
        fi
        chmod 600 "$WILDCARD_FULLCHAIN_PATH"

        SSL_CERT="$WILDCARD_FULLCHAIN_PATH"
        SSL_KEY="$WILDCARD_KEY_PATH"
        print_success "Manual wildcard certificate imported successfully"
        return
    fi

    mkdir -p "$MANUAL_CERT_DIR"
    SSL_CERT="$MANUAL_CERT_DIR/$(basename "$EXISTING_CERT_PATH")"
    SSL_KEY="$MANUAL_CERT_DIR/$(basename "$EXISTING_KEY_PATH")"
    validate_certificate_file "$EXISTING_CERT_PATH"
    validate_private_key_file "$EXISTING_KEY_PATH"
    validate_key_matches_certificate "$EXISTING_KEY_PATH" "$EXISTING_CERT_PATH"
    validate_certificate_covers_domain "$EXISTING_CERT_PATH" "$DOMAIN"
    cp "$EXISTING_CERT_PATH" "$SSL_CERT"
    cp "$EXISTING_KEY_PATH" "$SSL_KEY"
    chmod 600 "$SSL_CERT" "$SSL_KEY"
    print_success "Existing certificate and key imported successfully"
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

validate_database_connection() {
    if [ "$DB_TYPE" = "1" ]; then
        return
    fi

    print_step "Validating external database connectivity..."
    if timeout 5 bash -c ">/dev/tcp/$DB_HOST/$DB_PORT" 2>/dev/null; then
        print_success "Database endpoint reachable at $DB_HOST:$DB_PORT"
    else
        print_error "Cannot reach database endpoint $DB_HOST:$DB_PORT"
        exit 1
    fi
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
DOMAIN=$ACCESS_URL
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
    local redirect_port_suffix=""
    if [ "$EXTERNAL_HTTPS_PORT" != "443" ]; then
        redirect_port_suffix=":$EXTERNAL_HTTPS_PORT"
    fi

    if [ "$INTERNAL_HTTPS_PORT" = "80" ]; then
        cat > "$NGINX_SITE" << EOF
server {
    listen 80 ssl http2;
    listen [::]:80 ssl http2;
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
    else
        cat > "$NGINX_SITE" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$server_name$redirect_port_suffix\$request_uri;
}

server {
    listen $INTERNAL_HTTPS_PORT ssl http2;
    listen [::]:$INTERNAL_HTTPS_PORT ssl http2;
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
    fi

    # Enable site
    ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # Validate generated config against user inputs
    validate_nginx_config_matches_inputs

    # Test nginx configuration and restart service
    if nginx -t >> "$LOG_FILE" 2>&1; then
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
            ufw allow "$INTERNAL_HTTPS_PORT"/tcp
            ufw reload
            print_success "UFW firewall configured"
            ;;
        centos|rhel|fedora)
            systemctl enable firewalld
            systemctl start firewalld
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-port="$INTERNAL_HTTPS_PORT"/tcp
            firewall-cmd --reload
            print_success "Firewalld configured"
            ;;
    esac
}

# =============================================================================
# MOTD Configuration
# =============================================================================

setup_custom_motd() {
    print_step "Configuring MOTD scripts..."
    mkdir -p /etc/update-motd.d

    shopt -s nullglob
    local motd_files=(/etc/update-motd.d/*)
    if [ ${#motd_files[@]} -gt 0 ]; then
        chmod -x /etc/update-motd.d/* || true
    fi
    shopt -u nullglob
    print_success "Default MOTD scripts disabled"

    if [ "$SETUP_CUSTOM_MOTD" != "true" ]; then
        print_info "Custom MOTD skipped by user choice."
        return
    fi

    cat > /etc/update-motd.d/99-vaultwarden << EOF
#!/bin/bash

CONTAINER="vaultwarden"
EXTERNAL_URL="$ACCESS_URL"

# Controllo stato container
if docker ps --format '{{.Names}}' | grep -q "^\${CONTAINER}\$"; then
    STATUS="🟢 Running"
else
    STATUS="🔴 Not Running"
fi

# Uptime container
UPTIME=\$(docker inspect -f '{{.State.StartedAt}}' "\$CONTAINER" 2>/dev/null)

if [ -n "\$UPTIME" ]; then
    START_TIME=\$(date -d "\$UPTIME" +%s 2>/dev/null)
    NOW=\$(date +%s)
    if [ -n "\$START_TIME" ]; then
        DIFF=\$((NOW - START_TIME))
        DAYS=\$((DIFF/86400))
        HOURS=\$(((DIFF%86400)/3600))
        MINUTES=\$(((DIFF%3600)/60))
        UPTIME_STR="\${DAYS}g \${HOURS}h \${MINUTES}m"
    else
        UPTIME_STR="N/A"
    fi
else
    UPTIME_STR="N/A"
fi

# Health check esterno (max 3s). Non stampa HTML, solo status code
HTTP_CODE=\$(curl -k -sS -o /dev/null -m 3 -w "%{http_code}" "\$EXTERNAL_URL" 2>/dev/null || true)
if [[ "\$HTTP_CODE" =~ ^(2|3) ]]; then
    EXT_STATUS="🟢 OK (\$HTTP_CODE)"
elif [ -n "\$HTTP_CODE" ] && [ "\$HTTP_CODE" != "000" ]; then
    EXT_STATUS="🟠 Risponde ma errore (\$HTTP_CODE)"
else
    EXT_STATUS="🔴 KO (timeout/DNS/TLS)"
fi

# Docker stats
DOCKER_VER=\$(docker --version 2>/dev/null | sed 's/,.*//')
RUNNING_C=\$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
TOTAL_C=\$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')
STOPPED_C=\$((TOTAL_C - RUNNING_C))

# RAM del container (se running)
VW_MEM="N/A"
if docker ps --format '{{.Names}}' | grep -q "^\${CONTAINER}\$"; then
    VW_MEM=\$(docker stats --no-stream --format "{{.MemUsage}}" "\$CONTAINER" 2>/dev/null)
    [ -z "\$VW_MEM" ] && VW_MEM="N/A"
fi

# Sicurezza / SSH info (no ufw/fail2ban)
SSH_PORT=\$(ss -ltn 2>/dev/null | awk '\$4 ~ /:22\$/ {found=1} END{ if(found) print "22"; }')
if [ -z "\$SSH_PORT" ]; then
    SSH_PORT=\$(ss -ltnp 2>/dev/null | awk '/sshd/ {split(\$4,a,":"); print a[length(a)]; exit}')
fi
[ -z "\$SSH_PORT" ] && SSH_PORT="N/A"

# Opzioni sshd (se leggibili)
SSHD_CFG="/etc/ssh/sshd_config"
PRL="N/A"
PWA="N/A"
if [ -r "\$SSHD_CFG" ]; then
    PRL=\$(grep -iE '^[[:space:]]*PermitRootLogin[[:space:]]+' "\$SSHD_CFG" | tail -n 1 | awk '{print \$2}')
    PWA=\$(grep -iE '^[[:space:]]*PasswordAuthentication[[:space:]]+' "\$SSHD_CFG" | tail -n 1 | awk '{print \$2}')
    [ -z "\$PRL" ] && PRL="(default)"
    [ -z "\$PWA" ] && PWA="(default)"
fi

# Utenti connessi
USERS_NOW=\$(who 2>/dev/null | awk '{print \$1}' | sort | uniq | tr '\n' ' ')
[ -z "\$USERS_NOW" ] && USERS_NOW="nessuno"

# Ultime login SSH OK (ultime 3)
LAST_SSH_OK=\$(last -n 3 2>/dev/null | awk '/sshd|pts/ && \$1 != "reboot" && \$1 != "wtmp" {print \$1"@"\$3" "\$4" "\$5" "\$6}' | head -n 3)
[ -z "\$LAST_SSH_OK" ] && LAST_SSH_OK="N/A"

# Tentativi falliti SSH (ultime 24h): prima journalctl, fallback auth.log
FAIL_24H="N/A"
if command -v journalctl >/dev/null 2>&1; then
    FAIL_24H=\$(journalctl -u ssh -u sshd --since "24 hours ago" 2>/dev/null | grep -Ei "Failed password|Invalid user|authentication failure" | wc -l | tr -d ' ')
fi
if [ "\$FAIL_24H" = "N/A" ] || [ -z "\$FAIL_24H" ]; then
    if [ -r /var/log/auth.log ]; then
        FAIL_24H=\$(grep -Ei "Failed password|Invalid user|authentication failure" /var/log/auth.log 2>/dev/null | wc -l | tr -d ' ')
    else
        FAIL_24H="N/A"
    fi
fi

clear

cat << "EOBANNER"
____   ____            .__   __   __      __                  .___
\   \ /   /____   __ __|  |_/  |_/  \    /  \_____ _______  __| _/____   ____
 \   Y   /\__  \ |  |  \  |\   __\   \/\/   /\__  \\_  __ \/ __ |/ __ \ /    \
  \     /  / __ \|  |  /  |_|  |  \        /  / __ \|  | \/ /_/ \  ___/|   |  \
   \___/  (____  /____/|____/__|   \__/\  /  (____  /__|  \____ |\___  >___|  /
               \/                       \/        \/           \/    \/     \/
EOBANNER

echo ""
echo "    Stato: \$STATUS"
echo "    Uptime Container: \$UPTIME_STR"
echo "    Check Esterno (\$EXTERNAL_URL): \$EXT_STATUS"
echo ""

echo "    CPU Load: \$(uptime | awk -F'load average:' '{ print \$2 }')"
if command -v free >/dev/null 2>&1; then
    echo "    RAM Usage: \$(free -h | awk '/Mem:/ {print \$3 \"/\" \$2}')"
else
    echo "    RAM Usage: N/A"
fi
echo "    Disk Usage: \$(df -h / | awk 'NR==2 {print \$3 \"/\" \$2 \" (\" \$5 \")\"}')"
echo ""

echo "    Docker: \${DOCKER_VER:-N/A}"
echo "    Container: running \$RUNNING_C | stopped \$STOPPED_C | total \$TOTAL_C"
echo "    Vaultwarden Mem: \$VW_MEM"
echo ""

echo "    SSH Port: \$SSH_PORT"
echo "    sshd_config: PermitRootLogin=\$PRL | PasswordAuthentication=\$PWA"
echo "    Logged users: \$USERS_NOW"
echo "    SSH Failed (24h): \$FAIL_24H"
echo "    Last SSH logins:"
echo "\$LAST_SSH_OK" | sed 's/^/      - /'
echo ""
EOF

    chmod +x /etc/update-motd.d/99-vaultwarden
    print_success "Custom MOTD installed at /etc/update-motd.d/99-vaultwarden"
}

# =============================================================================
# Command Aliases
# =============================================================================

create_aliases() {
    print_step "Creating command aliases..."

    touch "$ALIAS_FILE"
    if grep -qF "$ALIAS_MARKER_START" "$ALIAS_FILE"; then
        sed -i "/$ALIAS_MARKER_START/,/$ALIAS_MARKER_END/d" "$ALIAS_FILE"
    fi

    cat >> "$ALIAS_FILE" << EOF

$ALIAS_MARKER_START
alias vw-start='systemctl start vaultwarden'
alias vw-stop='systemctl stop vaultwarden'
alias vw-restart='systemctl restart vaultwarden'
alias vw-status='systemctl status vaultwarden'
alias vw-logs='journalctl -u vaultwarden -f'
alias vw-update='docker pull vaultwarden/server:latest && systemctl restart vaultwarden'
alias vw-backup='tar -czf /root/vaultwarden-backup-\$(date +%Y%m%d-%H%M%S).tar.gz /var/lib/vaultwarden'
alias vw-config='nano /opt/vaultwarden/.env'
alias vw-admin-key='cat /root/vaultwarden-admin-key.txt'
alias vw-cleanup='docker stop vaultwarden 2>/dev/null; docker rm vaultwarden 2>/dev/null; systemctl stop vaultwarden 2>/dev/null; echo "Cleanup completed"'
alias vw-diagnose='echo "=== Service Status ==="; systemctl status vaultwarden; echo ""; echo "=== Docker Logs ==="; docker logs vaultwarden 2>&1 | tail -20; echo ""; echo "=== Port 8000 ==="; ss -tuln | grep 8000'
$ALIAS_MARKER_END
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
Domain: $ACCESS_URL
Admin Panel: $ACCESS_URL/admin
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
        print_warning "Port 8000 is in use by another process. Not killing it automatically."
        lsof -nP -iTCP:8000 -sTCP:LISTEN 2>/dev/null || true
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
    
    # Report port conflict instead of force-killing unknown processes
    if netstat -tuln 2>/dev/null | grep -q ":8000 " || ss -tuln 2>/dev/null | grep -q ":8000 "; then
        print_warning "Port 8000 is in use. Resolve this conflict manually before retry."
        lsof -nP -iTCP:8000 -sTCP:LISTEN 2>/dev/null || true
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
    
    cat > "$BACKUP_SCRIPT" << 'EOF'
#!/bin/bash
BACKUP_DIR="/root/vaultwarden-backups"
DATE=$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"
tar -czf "$BACKUP_DIR/vaultwarden-$DATE.tar.gz" /var/lib/vaultwarden
find "$BACKUP_DIR" -name "vaultwarden-*.tar.gz" -mtime +7 -delete
EOF

    chmod +x "$BACKUP_SCRIPT"
    
    # Add cron job for daily backup at 2 AM
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || true)
    if ! printf "%s\n" "$current_crontab" | grep -qF "$BACKUP_CRON_LINE"; then
        (printf "%s\n" "$current_crontab"; echo "$BACKUP_CRON_LINE") | crontab -
    fi
    
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
    echo "  🌐 URL: $ACCESS_URL"
    echo "  🔐 Admin Panel: $ACCESS_URL/admin"
    echo "  🔑 Admin Token: Saved in $ADMIN_KEY_FILE"
    echo "  🔌 Port Mapping: external $EXTERNAL_HTTPS_PORT -> internal $INTERNAL_HTTPS_PORT"
    if [ "$SETUP_CUSTOM_MOTD" = "true" ]; then
        echo "  🖥️  MOTD: /etc/update-motd.d/99-vaultwarden (enabled)"
    else
        echo "  🖥️  MOTD: default scripts disabled, custom MOTD skipped"
    fi
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
    validate_database_connection
    configure_vaultwarden
    pull_vaultwarden_image
    create_systemd_service
    configure_nginx
    configure_firewall
    setup_custom_motd
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
