#!/bin/bash

CONTAINER="${CONTAINER:-vaultwarden}"
MOTD_DOMAIN="${MOTD_DOMAIN:-vault.example.com}"
MOTD_INTERNAL_HTTPS_PORT="${MOTD_INTERNAL_HTTPS_PORT:-443}"
EXTERNAL_URL="${EXTERNAL_URL:-https://${MOTD_DOMAIN}}"

# Controllo stato container
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    STATUS="🟢 Running"
else
    STATUS="🔴 Not Running"
fi

# Uptime container
UPTIME=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER" 2>/dev/null)
if [ -n "$UPTIME" ]; then
    START_TIME=$(date -d "$UPTIME" +%s 2>/dev/null)
    NOW=$(date +%s)
    if [ -n "$START_TIME" ]; then
        DIFF=$((NOW - START_TIME))
        DAYS=$((DIFF/86400))
        HOURS=$(((DIFF%86400)/3600))
        MINUTES=$(((DIFF%3600)/60))
        UPTIME_STR="${DAYS}g ${HOURS}h ${MINUTES}m"
    else
        UPTIME_STR="N/A"
    fi
else
    UPTIME_STR="N/A"
fi

# Health check esterno (max 3s). NAT loopback aware
HTTP_CODE=$(curl -k -sS -o /dev/null -m 3 -w "%{http_code}" "$EXTERNAL_URL" 2>/dev/null || true)
if [[ "$HTTP_CODE" =~ ^(2|3) ]]; then
    EXT_STATUS="🟢 OK ($HTTP_CODE)"
elif [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
    EXT_STATUS="🟠 Risponde ma errore ($HTTP_CODE)"
else
    LOCAL_URL="https://${MOTD_DOMAIN}:${MOTD_INTERNAL_HTTPS_PORT}"
    LOCAL_CODE=$(curl -k -sS -o /dev/null -m 3 \
        --resolve "${MOTD_DOMAIN}:${MOTD_INTERNAL_HTTPS_PORT}:127.0.0.1" \
        -w "%{http_code}" "$LOCAL_URL" 2>/dev/null || true)
    if [[ "$LOCAL_CODE" =~ ^(2|3) ]]; then
        EXT_STATUS="🟡 KO esterno da host (NAT loopback/DNS), locale OK ($LOCAL_CODE)"
    elif [ -n "$LOCAL_CODE" ] && [ "$LOCAL_CODE" != "000" ]; then
        EXT_STATUS="🟠 KO esterno, locale risponde con errore ($LOCAL_CODE)"
    else
        EXT_STATUS="🔴 KO (timeout/DNS/TLS)"
    fi
fi

# Docker stats
DOCKER_VER=$(docker --version 2>/dev/null | sed 's/,.*//')
RUNNING_C=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
TOTAL_C=$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')
STOPPED_C=$((TOTAL_C - RUNNING_C))

# RAM del container (se running)
VW_MEM="N/A"
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    VW_MEM=$(docker stats --no-stream --format "{{.MemUsage}}" "$CONTAINER" 2>/dev/null)
    [ -z "$VW_MEM" ] && VW_MEM="N/A"
fi

# Sicurezza / SSH info
SSH_PORT=$(ss -ltn 2>/dev/null | awk '$4 ~ /:22$/ {found=1} END{ if(found) print "22"; }')
if [ -z "$SSH_PORT" ]; then
    SSH_PORT=$(ss -ltnp 2>/dev/null | awk '/sshd/ {split($4,a,":"); print a[length(a)]; exit}')
fi
[ -z "$SSH_PORT" ] && SSH_PORT="N/A"

SSHD_CFG="/etc/ssh/sshd_config"
PRL="N/A"
PWA="N/A"
if [ -r "$SSHD_CFG" ]; then
    PRL=$(grep -iE '^[[:space:]]*PermitRootLogin[[:space:]]+' "$SSHD_CFG" | tail -n 1 | awk '{print $2}')
    PWA=$(grep -iE '^[[:space:]]*PasswordAuthentication[[:space:]]+' "$SSHD_CFG" | tail -n 1 | awk '{print $2}')
    [ -z "$PRL" ] && PRL="(default)"
    [ -z "$PWA" ] && PWA="(default)"
fi

USERS_NOW=$(who 2>/dev/null | awk '{print $1}' | sort | uniq | tr '\n' ' ')
[ -z "$USERS_NOW" ] && USERS_NOW="nessuno"

LAST_SSH_OK=$(last -n 3 2>/dev/null | awk '/sshd|pts/ && $1 != "reboot" && $1 != "wtmp" {print $1"@"$3" "$4" "$5" "$6}' | head -n 3)
[ -z "$LAST_SSH_OK" ] && LAST_SSH_OK="N/A"

FAIL_24H="N/A"
if command -v journalctl >/dev/null 2>&1; then
    FAIL_24H=$(journalctl -u ssh -u sshd --since "24 hours ago" 2>/dev/null | grep -Ei "Failed password|Invalid user|authentication failure" | wc -l | tr -d ' ')
fi
if [ "$FAIL_24H" = "N/A" ] || [ -z "$FAIL_24H" ]; then
    if [ -r /var/log/auth.log ]; then
        FAIL_24H=$(grep -Ei "Failed password|Invalid user|authentication failure" /var/log/auth.log 2>/dev/null | wc -l | tr -d ' ')
    else
        FAIL_24H="N/A"
    fi
fi

# Extra stats (sistema)
CPU_LOAD=$(uptime 2>/dev/null | awk -F'load average:' '{ print $2 }')
[ -z "$CPU_LOAD" ] && CPU_LOAD="N/A"

RAM_USAGE="N/A"
if [ -r /proc/meminfo ]; then
    RAM_USAGE=$(awk '
        /^MemTotal:/ {t=$2}
        /^MemAvailable:/ {a=$2}
        END {
            if (t>0 && a>=0) {
                u=t-a
                printf "%.1fGi/%.1fGi", u/1048576, t/1048576
            }
        }' /proc/meminfo 2>/dev/null)
fi
if [ "$RAM_USAGE" = "N/A" ] && command -v free >/dev/null 2>&1; then
    RAM_USAGE=$(free -h 2>/dev/null | awk 'NR==2 && NF>=3 {print $3 "/" $2}')
fi
[ -z "$RAM_USAGE" ] && RAM_USAGE="N/A"

DISK_USAGE=$(df -hP / 2>/dev/null | awk 'END {if (NR>=2) print $3 "/" $2 " (" $5 ")"}')
if [ -z "$DISK_USAGE" ]; then
    DISK_USAGE=$(df -h / 2>/dev/null | awk 'END {if (NR>=2) print $3 "/" $2 " (" $5 ")"}')
fi
[ -z "$DISK_USAGE" ] && DISK_USAGE="N/A"

clear

cat << "EOF_BANNER"
____   ____            .__   __   __      __                  .___
\   \ /   /____   __ __|  |_/  |_/  \    /  \_____ _______  __| _/____   ____
 \   Y   /\__  \ |  |  \  |\   __\   \/\/   /\__  \\_  __ \/ __ |/ __ \ /    \
  \     /  / __ \|  |  /  |_|  |  \        /  / __ \|  | \/ /_/ \  ___/|   |  \
   \___/  (____  /____/|____/__|   \__/\  /  (____  /__|  \____ |\___  >___|  /
               \/                       \/        \/           \/    \/     \/
EOF_BANNER

echo ""
echo "    Stato: $STATUS"
echo "    Uptime Container: $UPTIME_STR"
echo "    Check Esterno ($EXTERNAL_URL): $EXT_STATUS"
echo ""

echo "    CPU Load: $CPU_LOAD"
echo "    RAM Usage: $RAM_USAGE"
echo "    Disk Usage: $DISK_USAGE"
echo ""

echo "    Docker: ${DOCKER_VER:-N/A}"
echo "    Container: running $RUNNING_C | stopped $STOPPED_C | total $TOTAL_C"
echo "    Vaultwarden Mem: $VW_MEM"
echo ""

echo "    SSH Port: $SSH_PORT"
echo "    sshd_config: PermitRootLogin=$PRL | PasswordAuthentication=$PWA"
echo "    Logged users: $USERS_NOW"
echo "    SSH Failed (24h): $FAIL_24H"
echo "    Last SSH logins:"
echo "$LAST_SSH_OK" | sed 's/^/      - /'
echo ""
