#!/bin/bash
# ================================================================
# FILE: var_cleanup.sh
# RUN:  sudo bash var_cleanup.sh
# PURPOSE: Find and clean everything large inside /var (42GB)
# ================================================================

GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC}  $1"; }
info() { echo -e "${CYAN}[..]${NC}  $1"; }
warn() { echo -e "${YELLOW}[!]${NC}   $1"; }

[[ $EUID -ne 0 ]] && { echo "Run: sudo bash var_cleanup.sh"; exit 1; }

FREE_BEFORE=$(df -h / | tail -1 | awk '{print $4}')
echo -e "${BOLD}Disk free before: $FREE_BEFORE${NC}"
echo ""
echo "Breakdown of /var:"
du -sh /var/* 2>/dev/null | sort -rh | head -15
echo ""

# ── 1. APT cache ─────────────────────────────────────────────
info "Cleaning /var/cache/apt..."
apt-get clean
apt-get autoclean
rm -rf /var/cache/apt/archives/*.deb
rm -rf /var/cache/apt/archives/partial/*
rm -rf /var/cache/apt/pkgcache.bin
rm -rf /var/cache/apt/srcpkgcache.bin
log "APT cache: $(du -sh /var/cache/apt 2>/dev/null | awk '{print $1}')"

# ── 2. APT lists ─────────────────────────────────────────────
info "Wiping stale /var/lib/apt/lists..."
rm -rf /var/lib/apt/lists/*
log "APT lists wiped"

# ── 3. Journal logs ───────────────────────────────────────────
info "Cleaning /var/log/journal..."
journalctl --vacuum-size=20M 2>/dev/null || true
journalctl --vacuum-time=1d  2>/dev/null || true
rm -rf /var/log/journal/*/*  2>/dev/null || true
log "Journal: $(du -sh /var/log/journal 2>/dev/null | awk '{print $1}')"

# ── 4. All rotated/old logs ───────────────────────────────────
info "Removing all rotated log files in /var/log..."
find /var/log -name "*.gz"        -delete 2>/dev/null || true
find /var/log -name "*.1"         -delete 2>/dev/null || true
find /var/log -name "*.2"         -delete 2>/dev/null || true
find /var/log -name "*.old"       -delete 2>/dev/null || true
find /var/log -name "*-????????"  -delete 2>/dev/null || true
find /var/log -name "*.log.*"     -delete 2>/dev/null || true
# Truncate (not delete) active log files
find /var/log -name "*.log" -type f | while read -r f; do
    truncate -s 0 "$f" 2>/dev/null || true
done
log "Logs cleaned: $(du -sh /var/log 2>/dev/null | awk '{print $1}')"

# ── 5. Crash reports ─────────────────────────────────────────
info "Removing /var/crash..."
rm -rf /var/crash/*
log "Crash reports removed"

# ── 6. Core dumps ────────────────────────────────────────────
info "Removing core dumps..."
find /var -name "core" -type f -delete 2>/dev/null || true
find /var -name "*.core" -type f -delete 2>/dev/null || true
log "Core dumps removed"

# ── 7. Snapd cache ───────────────────────────────────────────
info "Cleaning /var/lib/snapd..."
rm -rf /var/lib/snapd/cache/* 2>/dev/null || true
# Remove disabled snap revisions
if command -v snap &>/dev/null; then
    snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | \
    while read -r name rev; do
        snap remove "$name" --revision="$rev" 2>/dev/null || true
    done
fi
log "Snapd cache: $(du -sh /var/lib/snapd 2>/dev/null | awk '{print $1}')"

# ── 8. Docker cleanup ────────────────────────────────────────
if command -v docker &>/dev/null; then
    info "Cleaning Docker..."
    docker system prune -af --volumes 2>/dev/null || true
    log "Docker cleaned: $(du -sh /var/lib/docker 2>/dev/null | awk '{print $1}')"
fi

# ── 9. Old kernels ────────────────────────────────────────────
info "Removing old kernels..."
CURRENT=$(uname -r)
OLD=$(dpkg -l 'linux-image-*' 2>/dev/null | grep "^ii" | \
    grep -v "$CURRENT" | grep -v "linux-image-generic" | \
    awk '{print $2}')
if [[ -n "$OLD" ]]; then
    echo "$OLD" | xargs apt-get purge -y 2>/dev/null | tail -3 || true
    log "Old kernels removed"
fi

# ── 10. PostgreSQL leftover data ──────────────────────────────
if [[ -d /var/lib/postgresql ]]; then
    info "Removing leftover PostgreSQL data..."
    rm -rf /var/lib/postgresql/
    log "PostgreSQL data removed"
fi

# ── 11. Temp/cache directories ────────────────────────────────
info "Cleaning /var/tmp and /tmp..."
rm -rf /var/tmp/*  2>/dev/null || true
rm -rf /tmp/*      2>/dev/null || true
log "Temp dirs cleaned"

# ── 12. Old package manager state files ──────────────────────
info "Cleaning stale dpkg files..."
rm -rf /var/lib/dpkg/info/*.list.bak  2>/dev/null || true
rm -rf /var/cache/debconf/*-old       2>/dev/null || true

# ── 13. Find any single file > 100MB still left ──────────────
echo ""
info "Checking for large files still remaining in /var..."
LARGE=$(find /var -size +100M -type f 2>/dev/null | head -20)
if [[ -n "$LARGE" ]]; then
    warn "Large files still in /var:"
    echo "$LARGE" | while read -r f; do
        SIZE=$(du -sh "$f" 2>/dev/null | awk '{print $1}')
        printf "    %-10s %s\n" "$SIZE" "$f"
    done
    echo ""
    warn "Review and delete manually if safe:"
    echo "  sudo rm -f <filepath>"
else
    log "No single files over 100MB found"
fi

# ── Final report ─────────────────────────────────────────────
FREE_AFTER=$(df -h / | tail -1 | awk '{print $4}')
FREE_AFTER_MB=$(df / | tail -1 | awk '{print int($4/1024)}')

echo ""
echo -e "${BOLD}New breakdown of /var:${NC}"
du -sh /var/* 2>/dev/null | sort -rh | head -10

echo ""
echo -e "${BOLD}${GREEN}"
echo "=================================="
echo "  Cleanup Complete"
echo "=================================="
echo -e "${NC}"
printf "  %-20s %s\n" "Free before:"  "$FREE_BEFORE"
printf "  %-20s %s\n" "Free after:"   "$FREE_AFTER"
echo ""

if [[ "$FREE_AFTER_MB" -gt 2000 ]]; then
    echo -e "${GREEN}Good! Enough space. Now run:${NC}"
    echo "  sudo bash kong-setup.sh"
elif [[ "$FREE_AFTER_MB" -gt 500 ]]; then
    echo -e "${YELLOW}Marginal space (${FREE_AFTER_MB}MB). Try running:${NC}"
    echo "  sudo bash kong-setup.sh"
else
    echo -e "${YELLOW}Still low (${FREE_AFTER_MB}MB).${NC}"
    echo ""
    echo "  What's left in /var:"
    du -sh /var/lib/* 2>/dev/null | sort -rh | head -10
    echo ""
    echo "  The VM disk is too small. Options:"
    echo ""
    echo "  OPTION A — Increase VirtualBox disk size:"
    echo "    1. Power off VM"
    echo "    2. VirtualBox → File → Virtual Media Manager"
    echo "       → select your .vdi → resize to 30GB+"
    echo "    3. Boot VM, then run:"
    echo "       sudo apt install -y cloud-guest-utils"
    echo "       sudo growpart /dev/sda 1"
    echo "       sudo resize2fs /dev/sda1"
    echo ""
    echo "  OPTION B — Check /var/lib breakdown:"
    echo "    sudo du -sh /var/lib/* 2>/dev/null | sort -rh | head -15"
fi
