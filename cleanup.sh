#!/bin/bash
# ============================================================
# FILE: uninstall_postgres_and_clean.sh
# RUN:  sudo bash uninstall_postgres_and_clean.sh
# PURPOSE:
#   1. Uninstall PostgreSQL completely
#   2. Clean /var/cache/apt/archives (all .deb files)
#   3. Free up disk space for Kong DB-Less install
# ============================================================

GREEN='\033[0;32m'; CYAN='\033[0;36m'
RED='\033[0;31m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC}  $1"; }
info() { echo -e "${CYAN}[..]${NC}  $1"; }
warn() { echo -e "${YELLOW}[!]${NC}   $1"; }

[[ $EUID -ne 0 ]] && { echo "Run: sudo bash uninstall_postgres_and_clean.sh"; exit 1; }

echo -e "${BOLD}${CYAN}"
echo "========================================================"
echo "  Uninstall PostgreSQL + Clean APT Cache"
echo "========================================================"
echo -e "${NC}"

FREE_BEFORE=$(df -h / | tail -1 | awk '{print $4}')
echo "  Disk free BEFORE: $FREE_BEFORE"
echo "  APT cache size:   $(du -sh /var/cache/apt/archives/ | awk '{print $1}')"
echo ""

# ============================================================
# STEP 1 — STOP POSTGRESQL SERVICE
# ============================================================
info "Step 1: Stopping PostgreSQL service..."
systemctl stop postgresql   2>/dev/null || true
systemctl disable postgresql 2>/dev/null || true
log "PostgreSQL service stopped"

# ============================================================
# STEP 2 — UNINSTALL POSTGRESQL COMPLETELY
# ============================================================
info "Step 2: Removing PostgreSQL packages..."
export DEBIAN_FRONTEND=noninteractive

# Remove all postgresql packages
apt-get purge -y \
    postgresql \
    postgresql-14 \
    postgresql-15 \
    postgresql-16 \
    postgresql-client \
    postgresql-client-14 \
    postgresql-client-common \
    postgresql-common \
    postgresql-contrib \
    'postgresql-*' \
    2>&1 | tail -5 || true

apt-get autoremove -y 2>&1 | tail -3 || true
log "PostgreSQL packages removed"

# ============================================================
# STEP 3 — REMOVE POSTGRESQL DATA AND CONFIG DIRS
# ============================================================
info "Step 3: Removing PostgreSQL data directories..."
rm -rf /var/lib/postgresql/  && log "Removed /var/lib/postgresql/"
rm -rf /var/log/postgresql/  && log "Removed /var/log/postgresql/"
rm -rf /etc/postgresql/      && log "Removed /etc/postgresql/"
rm -rf /etc/postgresql-common/ 2>/dev/null || true

# ============================================================
# STEP 4 — CLEAN ALL CACHED .DEB FILES
# ============================================================
info "Step 4: Cleaning /var/cache/apt/archives/..."
echo "  Removing all cached .deb packages:"
ls /var/cache/apt/archives/*.deb 2>/dev/null | wc -l | \
    xargs -I{} echo "  Found {} .deb files to remove"

rm -f /var/cache/apt/archives/*.deb
rm -f /var/cache/apt/archives/partial/*
apt-get clean
apt-get autoclean
log "APT cache cleared"

# ============================================================
# STEP 5 — CLEAN OTHER LARGE /var FILES
# ============================================================
info "Step 5: Cleaning other large files in /var..."

# Journal logs
journalctl --vacuum-size=50M 2>/dev/null || true
journalctl --vacuum-time=3d  2>/dev/null || true
find /var/log -name "*.gz" -delete  2>/dev/null || true
find /var/log -name "*.old" -delete 2>/dev/null || true
find /var/log -name "*.1" -delete   2>/dev/null || true
log "Journal and old logs cleaned"

# Crash reports
rm -rf /var/crash/* 2>/dev/null || true
log "Crash reports removed"

# Snap old revisions
if command -v snap &>/dev/null; then
    snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | \
    while read -r name rev; do
        snap remove "$name" --revision="$rev" 2>/dev/null || true
    done
    rm -rf /var/lib/snapd/cache/* 2>/dev/null || true
    log "Snap old revisions cleaned"
fi

# Old kernels
CURRENT=$(uname -r)
dpkg -l 'linux-image-*' 2>/dev/null | grep "^ii" | \
    grep -v "$CURRENT" | grep -v "linux-image-generic" | \
    awk '{print $2}' | \
    xargs -r apt-get purge -y 2>/dev/null || true
log "Old kernels removed (kept: $CURRENT)"

# ============================================================
# STEP 6 — VERIFY POSTGRESQL IS GONE
# ============================================================
info "Step 6: Verifying PostgreSQL is fully removed..."

if dpkg -l postgresql 2>/dev/null | grep -q "^ii"; then
    warn "PostgreSQL still shows as installed — forcing removal..."
    dpkg --purge postgresql 2>/dev/null || true
else
    log "PostgreSQL: NOT installed (confirmed)"
fi

if [[ -d /var/lib/postgresql ]]; then
    warn "/var/lib/postgresql still exists — removing..."
    rm -rf /var/lib/postgresql
else
    log "/var/lib/postgresql: removed"
fi

# ============================================================
# STEP 7 — SHOW DISK SPACE FREED
# ============================================================
FREE_AFTER=$(df -h / | tail -1 | awk '{print $4}')
FREE_AFTER_MB=$(df / | tail -1 | awk '{print int($4/1024)}')

echo ""
echo -e "${BOLD}${GREEN}"
echo "========================================================"
echo "  Cleanup Complete"
echo "========================================================"
echo -e "${NC}"

printf "  %-25s %s\n" "Disk free before:"  "$FREE_BEFORE"
printf "  %-25s %s\n" "Disk free after:"   "$FREE_AFTER"
printf "  %-25s %s\n" "PostgreSQL:"        "UNINSTALLED"
printf "  %-25s %s\n" "APT cache:"         "$(du -sh /var/cache/apt/archives/ | awk '{print $1}')"

echo ""
echo "  Top space users now:"
du -sh /var/* 2>/dev/null | sort -rh | head -8 | \
    while read -r size path; do
        printf "    %-10s %s\n" "$size" "$path"
    done

echo ""
if [[ "$FREE_AFTER_MB" -gt 1000 ]]; then
    echo -e "${GREEN}${BOLD}Enough space freed! Next steps:${NC}"
    echo ""
    echo "  # Install Kong dependencies:"
    echo "  sudo bash kongo-pre-requisites.sh"
    echo ""
    echo "  # Run Kong DB-Less playbook:"
    echo "  ansible-playbook kong_dbless.yml -v"
else
    echo -e "${YELLOW}${BOLD}Still low on space (${FREE_AFTER_MB}MB).${NC}"
    echo "  Check what else is large:"
    echo "  sudo du -sh /var/lib/* 2>/dev/null | sort -rh | head -10"
fi
