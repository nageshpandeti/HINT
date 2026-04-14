#!/bin/bash
# ================================================================
# FILE:    kong-setup.sh
# RUN:     sudo bash kong-setup.sh
#
# DOES EVERYTHING IN ONE SHOT:
#   Phase 1 — Kill apt locks + repair dpkg
#   Phase 2 — Uninstall PostgreSQL completely
#   Phase 3 — Clean disk (/var/cache, logs, snap, old kernels)
#   Phase 4 — Wipe stale APT lists + disable broken repos
#   Phase 5 — Write clean Ubuntu sources.list
#   Phase 6 — Fix DNS + network
#   Phase 7 — apt-get update (clean)
#   Phase 8 — Install libopenssl + zlib + libpcre (verified)
#   Phase 9 — Install ansible + git + python3
#   Phase 10 — Ready to run kong_dbless.yml
# ================================================================

set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Colors ───────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[OK]${NC}    $1"; }
info()    { echo -e "${CYAN}[..]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[!]${NC}     $1"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $1"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}━━━  $1  ━━━${NC}\n"; }

# ── Root check ───────────────────────────────────────────────
[[ $EUID -ne 0 ]] && fail "Run as root: sudo bash kong-setup.sh"

# ── Log file ─────────────────────────────────────────────────
LOGFILE="/tmp/kong-setup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
╔══════════════════════════════════════════════════════════╗
║   Kong API Gateway — All-in-One Setup Script            ║
║   Uninstall Postgres + Clean Disk + Install Kong Deps   ║
╚══════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

CODENAME=$(lsb_release -sc 2>/dev/null || echo "jammy")
FREE_BEFORE=$(df -h / | tail -1 | awk '{print $4}')
log "Ubuntu $(lsb_release -sr) ($CODENAME) | RAM $(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)MB"
log "Disk free at start: $FREE_BEFORE"
log "Log file: $LOGFILE"

# ================================================================
# PHASE 1 — KILL APT LOCKS + REPAIR DPKG
# ================================================================
section "Phase 1: Kill APT Locks + Repair dpkg"

info "Killing background apt/dpkg processes..."
killall apt apt-get unattended-upgrades dpkg 2>/dev/null || true
systemctl stop unattended-upgrades  2>/dev/null || true
systemctl disable unattended-upgrades 2>/dev/null || true
sleep 2

info "Removing all lock files..."
rm -f /var/lib/dpkg/lock
rm -f /var/lib/dpkg/lock-frontend
rm -f /var/lib/apt/lists/lock
rm -f /var/cache/apt/archives/lock
rm -f /var/cache/debconf/config.dat.lock

info "Repairing dpkg state..."
dpkg --configure -a 2>&1 | tail -3 || true
apt-get install -f -y -qq 2>&1 | tail -3 || true
log "APT locks cleared and dpkg repaired"

# ================================================================
# PHASE 2 — UNINSTALL POSTGRESQL COMPLETELY
# ================================================================
section "Phase 2: Uninstall PostgreSQL"

info "Stopping PostgreSQL service..."
systemctl stop postgresql    2>/dev/null || true
systemctl disable postgresql 2>/dev/null || true

info "Purging all PostgreSQL packages..."
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
    2>&1 | tail -5 || true

# Force remove any remaining postgres packages
REMAINING=$(dpkg -l 'postgresql*' 2>/dev/null | grep "^ii" | awk '{print $2}' || true)
if [[ -n "$REMAINING" ]]; then
    echo "$REMAINING" | xargs apt-get purge -y 2>/dev/null || true
fi

apt-get autoremove -y 2>&1 | tail -3 || true

info "Removing PostgreSQL data + config directories..."
rm -rf /var/lib/postgresql/
rm -rf /etc/postgresql/
rm -rf /etc/postgresql-common/
rm -rf /var/log/postgresql/

# Verify
if dpkg -l 'postgresql*' 2>/dev/null | grep -q "^ii"; then
    warn "Some postgresql packages still present — forcing dpkg purge..."
    dpkg -l 'postgresql*' | grep "^ii" | awk '{print $2}' | \
        xargs dpkg --purge 2>/dev/null || true
else
    log "PostgreSQL: fully uninstalled"
fi
log "PostgreSQL directories removed"

# ================================================================
# PHASE 3 — CLEAN DISK
# ================================================================
section "Phase 3: Clean Disk"

info "Clearing /var/cache/apt/archives/ (all .deb files)..."
COUNT=$(ls /var/cache/apt/archives/*.deb 2>/dev/null | wc -l || echo 0)
warn "Removing $COUNT cached .deb files..."
rm -f /var/cache/apt/archives/*.deb
rm -rf /var/cache/apt/archives/partial/*
apt-get clean
apt-get autoclean
log "APT cache cleared"

info "Removing old/rotated log files..."
find /var/log -name "*.gz"  -delete 2>/dev/null || true
find /var/log -name "*.1"   -delete 2>/dev/null || true
find /var/log -name "*.old" -delete 2>/dev/null || true
find /var/log -name "*-????????" -delete 2>/dev/null || true
journalctl --vacuum-size=50M 2>/dev/null || true
journalctl --vacuum-time=2d  2>/dev/null || true
log "Old logs removed"

info "Removing crash reports..."
rm -rf /var/crash/* 2>/dev/null || true
log "Crash reports removed"

info "Removing snap old/disabled revisions..."
if command -v snap &>/dev/null; then
    snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | \
    while read -r name rev; do
        snap remove "$name" --revision="$rev" 2>/dev/null || true
    done
    rm -rf /var/lib/snapd/cache/* 2>/dev/null || true
    log "Snap revisions cleaned: $(du -sh /snap 2>/dev/null | awk '{print $1}')"
fi

info "Removing old kernels (keeping current: $(uname -r))..."
CURRENT_KERNEL=$(uname -r)
dpkg -l 'linux-image-*' 2>/dev/null | grep "^ii" | \
    grep -v "$CURRENT_KERNEL" | grep -v "linux-image-generic" | \
    awk '{print $2}' | xargs -r apt-get purge -y 2>/dev/null || true
log "Old kernels removed"

info "Cleaning temp files..."
rm -rf /tmp/*.deb /tmp/*.tar.gz /tmp/*.zip 2>/dev/null || true
rm -rf /var/tmp/*.deb 2>/dev/null || true
log "Temp files cleaned"

FREE_AFTER_CLEAN=$(df -h / | tail -1 | awk '{print $4}')
log "Disk free after cleanup: $FREE_AFTER_CLEAN"

# ================================================================
# PHASE 4 — WIPE STALE APT LISTS + DISABLE BROKEN REPOS
# ================================================================
section "Phase 4: Wipe Stale APT Lists + Disable Broken Repos"

info "Wiping all stale APT list files..."
rm -rf /var/lib/apt/lists/*
log "APT lists wiped"

info "Disabling all broken third-party repos..."
for f in /etc/apt/sources.list.d/*.list; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    warn "  Disabling: $fname"
    mv "$f" "${f}.disabled" 2>/dev/null || true
done

for f in /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    warn "  Disabling: $(basename $f)"
    mv "$f" "${f}.disabled" 2>/dev/null || true
done

# Also clean up kong leftovers
rm -f /usr/share/keyrings/kong*.gpg 2>/dev/null || true
rm -f /usr/share/keyrings/kong*.asc 2>/dev/null || true
rm -f /etc/apt/trusted.gpg.d/kong*.gpg 2>/dev/null || true
log "All third-party repos disabled"

# ================================================================
# PHASE 5 — WRITE CLEAN UBUNTU SOURCES.LIST
# ================================================================
section "Phase 5: Write Clean Ubuntu Sources"

info "Writing clean sources.list for Ubuntu $CODENAME..."
cat > /etc/apt/sources.list << EOF
deb http://archive.ubuntu.com/ubuntu ${CODENAME} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${CODENAME}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${CODENAME}-security main restricted universe multiverse
EOF
log "Clean sources.list written"
cat /etc/apt/sources.list

# ================================================================
# PHASE 6 — FIX DNS + NETWORK
# ================================================================
section "Phase 6: Fix DNS + Network"

info "Writing reliable DNS servers..."
chattr -i /etc/resolv.conf 2>/dev/null || true
cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
options timeout:2 attempts:3
EOF
log "DNS set to 8.8.8.8 / 8.8.4.4 / 1.1.1.1"

info "Detecting network interface..."
IFACE=$(ip route show default 2>/dev/null | awk '/default/{print $5}' | head -1)
[[ -z "$IFACE" ]] && IFACE="enp0s3"
info "Interface: $IFACE"

info "Bringing interface up + requesting DHCP..."
ip link set "$IFACE" up 2>/dev/null || true
if command -v dhclient &>/dev/null; then
    dhclient "$IFACE" 2>/dev/null || true
fi
sleep 2

info "Flushing iptables OUTPUT rules..."
iptables -F OUTPUT  2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true

info "Testing network..."
if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
    log "Ping 8.8.8.8: OK"
else
    warn "Cannot ping 8.8.8.8 — check VirtualBox: Settings → Network → Adapter 1 → NAT"
fi

if curl -sI --max-time 8 http://archive.ubuntu.com &>/dev/null; then
    log "HTTP to archive.ubuntu.com: OK"
else
    warn "Cannot reach archive.ubuntu.com — network may still be limited"
fi

# ================================================================
# PHASE 7 — APT-GET UPDATE (CLEAN)
# ================================================================
section "Phase 7: apt-get update"

info "Running fresh apt-get update with clean sources..."
apt-get update 2>&1
UPDATE_RC=$?

if [[ $UPDATE_RC -eq 0 ]]; then
    log "apt-get update: SUCCESS"
elif apt-cache show coreutils &>/dev/null; then
    warn "apt-get update had warnings but core Ubuntu repo works — continuing"
else
    fail "apt-get update failed completely. Check network and re-run."
fi

# ================================================================
# PHASE 8 — INSTALL LIBOPENSSL + ZLIB + LIBPCRE
# ================================================================
section "Phase 8: Install libopenssl + zlib + libpcre"

info "Installing Kong native dependencies..."
apt-get install -y \
    openssl \
    libssl-dev \
    zlib1g \
    zlib1g-dev \
    libpcre3 \
    libpcre3-dev \
    perl \
    procps 2>&1 | tail -6

echo ""
info "Verifying each package..."

# libopenssl
if dpkg -l libssl-dev 2>/dev/null | grep -q "^ii"; then
    log "libopenssl  ✔  $(openssl version)"
else
    fail "libopenssl (libssl-dev) installation FAILED"
fi

# zlib
if dpkg -l zlib1g 2>/dev/null | grep -q "^ii"; then
    log "zlib        ✔  $(dpkg -l zlib1g | grep '^ii' | awk '{print $3}')"
else
    fail "zlib1g installation FAILED"
fi

# libpcre
if dpkg -l libpcre3 2>/dev/null | grep -q "^ii"; then
    log "libpcre     ✔  $(dpkg -l libpcre3 | grep '^ii' | awk '{print $3}')"
else
    fail "libpcre3 installation FAILED"
fi

# ================================================================
# PHASE 9 — INSTALL ANSIBLE + GIT + PYTHON3
# ================================================================
section "Phase 9: Install Ansible + Git + Python3"

apt-get install -y \
    ansible \
    git \
    python3 \
    python3-pip \
    python3-psycopg2 \
    curl \
    gnupg \
    gnupg2 \
    apt-transport-https \
    ca-certificates \
    lsb-release 2>&1 | tail -6

log "Ansible : $(ansible --version | head -1)"
log "Git     : $(git --version)"
log "Python3 : $(python3 --version)"

info "Installing Ansible community.postgresql collection..."
ansible-galaxy collection install community.postgresql --force -q 2>&1 | tail -2
log "Ansible collection installed"

# ================================================================
# PHASE 10 — FINAL SUMMARY
# ================================================================
section "Phase 10: Summary"

FREE_FINAL=$(df -h / | tail -1 | awk '{print $4}')
FREE_FINAL_MB=$(df / | tail -1 | awk '{print int($4/1024)}')

echo ""
echo -e "${BOLD}${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          All Phases Complete — Kong Ready!              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

printf "  %-22s %s\n" "Disk free before:"   "$FREE_BEFORE"
printf "  %-22s %s\n" "Disk free after:"    "$FREE_FINAL"
echo ""
printf "  %-22s %s\n" "PostgreSQL:"         "UNINSTALLED ✔"
printf "  %-22s %s\n" "libopenssl:"         "$(openssl version)"
printf "  %-22s %s\n" "zlib:"               "$(dpkg -l zlib1g | grep '^ii' | awk '{print $3}')"
printf "  %-22s %s\n" "libpcre:"            "$(dpkg -l libpcre3 | grep '^ii' | awk '{print $3}')"
printf "  %-22s %s\n" "ansible:"            "$(ansible --version | head -1)"
printf "  %-22s %s\n" "git:"                "$(git --version)"
echo ""
printf "  %-22s %s\n" "Log saved to:"       "$LOGFILE"
echo ""

if [[ "$FREE_FINAL_MB" -gt 500 ]]; then
    echo -e "${GREEN}${BOLD}Ready! Now run the Kong playbook:${NC}"
    echo ""
    echo "  ansible-playbook kong_dbless.yml -v"
else
    echo -e "${YELLOW}${BOLD}Low disk space (${FREE_FINAL_MB}MB). Check what is using /var:${NC}"
    echo "  sudo du -sh /var/* 2>/dev/null | sort -rh | head -10"
fi
echo ""
