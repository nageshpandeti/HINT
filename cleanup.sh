#!/bin/bash
# ============================================================
# FILE: disk_cleanup.sh
# RUN:  sudo bash disk_cleanup.sh
# PURPOSE: Free disk space - targets /var (40G) and /snap (1.2G)
# ============================================================

GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC}  $1"; }
info() { echo -e "${CYAN}[..]${NC}  $1"; }
warn() { echo -e "${YELLOW}[!]${NC}   $1"; }

[[ $EUID -ne 0 ]] && { echo "Run: sudo bash disk_cleanup.sh"; exit 1; }

echo -e "${BOLD}${CYAN}"
echo "========================================================"
echo "  Disk Cleanup — targeting /var (40G) + /snap (1.2G)"
echo "========================================================"
echo -e "${NC}"

FREE_BEFORE=$(df -h / | tail -1 | awk '{print $4}')
echo "  Disk free BEFORE: $FREE_BEFORE"
echo ""

# ── 1. APT cache ─────────────────────────────────────────────
info "Cleaning APT cache..."
apt-get clean
apt-get autoclean
apt-get autoremove -y 2>/dev/null || true
rm -rf /var/cache/apt/archives/*.deb 2>/dev/null || true
rm -rf /var/cache/apt/archives/partial/* 2>/dev/null || true
FREED=$(du -sh /var/cache/apt 2>/dev/null | awk '{print $1}')
log "APT cache cleaned"

# ── 2. Journal logs ───────────────────────────────────────────
info "Truncating journal logs (keep last 50MB)..."
journalctl --vacuum-size=50M 2>/dev/null || true
journalctl --vacuum-time=2d  2>/dev/null || true
log "Journal logs cleaned: $(du -sh /var/log/journal 2>/dev/null | awk '{print $1}')"

# ── 3. Old system logs ────────────────────────────────────────
info "Removing old /var/log files..."
find /var/log -name "*.gz"    -delete 2>/dev/null || true
find /var/log -name "*.1"     -delete 2>/dev/null || true
find /var/log -name "*.old"   -delete 2>/dev/null || true
find /var/log -name "*-????????" -delete 2>/dev/null || true
log "Old log files removed"

# ── 4. Snap cleanup ───────────────────────────────────────────
info "Cleaning snap (removing disabled/old revisions)..."
if command -v snap &>/dev/null; then
    # Remove disabled snap revisions
    snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | \
    while read -r name rev; do
        snap remove "$name" --revision="$rev" 2>/dev/null && \
            echo "  Removed snap: $name rev $rev" || true
    done

    # Clear snap cache
    rm -rf /var/lib/snapd/cache/* 2>/dev/null || true

    SNAP_SIZE=$(du -sh /snap 2>/dev/null | awk '{print $1}')
    log "Snap cleaned — current size: $SNAP_SIZE"
else
    warn "Snap not installed — skipping"
fi

# ── 5. Old kernels ────────────────────────────────────────────
info "Removing old kernels..."
CURRENT=$(uname -r)
echo "  Keeping current kernel: $CURRENT"
OLD_KERNELS=$(dpkg -l 'linux-image-*' 2>/dev/null | grep "^ii" | \
    grep -v "$CURRENT" | grep -v "linux-image-generic" | \
    awk '{print $2}')
if [[ -n "$OLD_KERNELS" ]]; then
    echo "$OLD_KERNELS" | xargs apt-get purge -y 2>/dev/null || true
    log "Old kernels removed"
else
    log "No old kernels to remove"
fi

# ── 6. /var/lib/docker cleanup (if Docker installed) ─────────
if command -v docker &>/dev/null; then
    info "Cleaning Docker cache..."
    docker system prune -af --volumes 2>/dev/null || true
    log "Docker cleaned"
fi

# ── 7. Temp files ─────────────────────────────────────────────
info "Cleaning temp files..."
rm -rf /tmp/*.deb /tmp/*.tar.gz /tmp/*.zip 2>/dev/null || true
rm -rf /var/tmp/*.deb 2>/dev/null || true
log "Temp files cleaned"

# ── 8. Thumbnail/crash caches ────────────────────────────────
info "Clearing crash reports and thumbnails..."
rm -rf /var/crash/* 2>/dev/null || true
rm -rf /home/*/.cache/thumbnails/* 2>/dev/null || true
log "Crash reports cleared"

# ── Check /var breakdown ─────────────────────────────────────
echo ""
info "What's inside /var now:"
du -sh /var/* 2>/dev/null | sort -rh | head -10

# ── Final result ─────────────────────────────────────────────
FREE_AFTER=$(df -h / | tail -1 | awk '{print $4}')
FREE_AFTER_MB=$(df / | tail -1 | awk '{print int($4/1024)}')

echo ""
echo -e "${BOLD}${GREEN}"
echo "========================================================"
echo "  Cleanup Complete"
echo "========================================================"
echo -e "${NC}"
printf "  %-20s %s\n" "Free before:" "$FREE_BEFORE"
printf "  %-20s %s\n" "Free after:"  "$FREE_AFTER"
echo ""

df -h /
echo ""

if [[ "$FREE_AFTER_MB" -gt 2000 ]]; then
    echo -e "${GREEN}Enough space to install Kong. Run:${NC}"
    echo "  sudo bash kongo-pre-requisites.sh"
elif [[ "$FREE_AFTER_MB" -gt 500 ]]; then
    echo -e "${YELLOW}Marginal space (${FREE_AFTER_MB}MB). May be enough. Run:${NC}"
    echo "  sudo bash kongo-pre-requisites.sh"
else
    echo -e "${YELLOW}${BOLD}Still low (${FREE_AFTER_MB}MB). Check /var breakdown above.${NC}"
    echo ""
    echo "If /var/lib/... is the culprit, check:"
    echo "  du -sh /var/lib/* | sort -rh | head -10"
    echo ""
    echo "To resize the VirtualBox disk instead:"
    echo "  1. Power off VM"
    echo "  2. VirtualBox → File → Virtual Media Manager → select disk → resize"
    echo "  3. Boot VM and run: sudo growpart /dev/sda 1 && sudo resize2fs /dev/sda1"
fi
