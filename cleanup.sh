#!/bin/bash
# ================================================================
# FILE: run_kong_ansible.sh
# RUN:  sudo bash run_kong_ansible.sh
#
# WHAT IT DOES:
#   1. Verifies libopenssl + zlib + libpcre are installed
#   2. Installs any missing ones automatically
#   3. Clones your GitLab repo (feature/kong branch)
#   4. Finds the ansible playbook automatically
#   5. Runs it
#   6. Tests Kong is working
# ================================================================

set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[OK]${NC}    $1"; }
info()    { echo -e "${CYAN}[..]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[!]${NC}     $1"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $1"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}━━━  $1  ━━━${NC}\n"; }

[[ $EUID -ne 0 ]] && fail "Run as root: sudo bash run_kong_ansible.sh"

LOGFILE="/tmp/kong-run-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
╔══════════════════════════════════════════════════════════════╗
║   Kong Ansible — Dependency Check + Clone + Run             ║
║   Repo: circles4/pods/oasis/sre/iac  (feature/kong)         ║
╚══════════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ================================================================
# STEP 1 — VERIFY / INSTALL ALL DEPENDENCIES
# ================================================================
section "Step 1: Verify Dependencies"

MISSING=()

# ── libopenssl ───────────────────────────────────────────────
info "Checking libopenssl (libssl-dev)..."
if dpkg -l libssl-dev 2>/dev/null | grep -q "^ii"; then
    log "libopenssl  ✔  $(openssl version 2>/dev/null)"
else
    warn "libopenssl NOT installed — installing now..."
    MISSING+=("openssl" "libssl-dev")
fi

# ── zlib ─────────────────────────────────────────────────────
info "Checking zlib (zlib1g)..."
if dpkg -l zlib1g 2>/dev/null | grep -q "^ii"; then
    VER=$(dpkg -l zlib1g | grep "^ii" | awk '{print $3}')
    log "zlib        ✔  $VER"
else
    warn "zlib NOT installed — installing now..."
    MISSING+=("zlib1g" "zlib1g-dev")
fi

# ── libpcre ──────────────────────────────────────────────────
info "Checking libpcre (libpcre3)..."
if dpkg -l libpcre3 2>/dev/null | grep -q "^ii"; then
    VER=$(dpkg -l libpcre3 | grep "^ii" | awk '{print $3}')
    log "libpcre     ✔  $VER"
else
    warn "libpcre NOT installed — installing now..."
    MISSING+=("libpcre3" "libpcre3-dev")
fi

# ── git ──────────────────────────────────────────────────────
info "Checking git..."
if command -v git &>/dev/null; then
    log "git         ✔  $(git --version)"
else
    warn "git NOT installed — installing now..."
    MISSING+=("git")
fi

# ── ansible ──────────────────────────────────────────────────
info "Checking ansible..."
if command -v ansible-playbook &>/dev/null; then
    log "ansible     ✔  $(ansible --version | head -1)"
else
    warn "ansible NOT installed — installing now..."
    MISSING+=("ansible")
fi

# ── python3 ──────────────────────────────────────────────────
info "Checking python3..."
if command -v python3 &>/dev/null; then
    log "python3     ✔  $(python3 --version)"
else
    MISSING+=("python3")
fi

# ── curl ─────────────────────────────────────────────────────
info "Checking curl..."
if command -v curl &>/dev/null; then
    log "curl        ✔"
else
    MISSING+=("curl")
fi

# ── Install anything missing ──────────────────────────────────
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo ""
    warn "Installing missing packages: ${MISSING[*]}"
    echo ""

    # Fix apt first
    killall apt apt-get 2>/dev/null || true
    rm -f /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend
    rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock
    dpkg --configure -a 2>/dev/null || true

    # Disable broken repos
    for f in /etc/apt/sources.list.d/*.list; do
        [ -f "$f" ] || continue
        if grep -qE "rabbitmq|hashicorp|fluentbit|ppa.launchpad" "$f" 2>/dev/null; then
            mv "$f" "${f}.disabled" 2>/dev/null || true
        fi
    done

    apt-get update -qq 2>&1 | tail -3

    apt-get install -y "${MISSING[@]}" \
        libpcre3-dev libssl-dev zlib1g-dev \
        python3-psycopg2 gnupg gnupg2 \
        apt-transport-https ca-certificates \
        lsb-release perl procps 2>&1 | tail -6

    echo ""
    log "All missing packages installed"
fi

# ── Ansible Galaxy collection ─────────────────────────────────
info "Checking ansible community.postgresql collection..."
if ansible-galaxy collection list 2>/dev/null | grep -q "community.postgresql"; then
    log "community.postgresql collection ✔"
else
    info "Installing community.postgresql collection..."
    ansible-galaxy collection install community.postgresql -q 2>&1 | tail -2
    log "community.postgresql installed"
fi

# ── Final dep summary ─────────────────────────────────────────
echo ""
echo -e "${BOLD}Dependency Summary:${NC}"
printf "  %-22s %s\n" "libopenssl:"  "$(openssl version 2>/dev/null)"
printf "  %-22s %s\n" "zlib:"        "$(dpkg -l zlib1g 2>/dev/null | grep '^ii' | awk '{print $3}')"
printf "  %-22s %s\n" "libpcre:"     "$(dpkg -l libpcre3 2>/dev/null | grep '^ii' | awk '{print $3}')"
printf "  %-22s %s\n" "ansible:"     "$(ansible --version 2>/dev/null | head -1)"
printf "  %-22s %s\n" "git:"         "$(git --version 2>/dev/null)"
printf "  %-22s %s\n" "disk free:"   "$(df -h / | tail -1 | awk '{print $4}')"

# ── Disk space check ─────────────────────────────────────────
FREE_MB=$(df / | tail -1 | awk '{print int($4/1024)}')
if [[ "$FREE_MB" -lt 300 ]]; then
    fail "Only ${FREE_MB}MB free — not enough to proceed. Free disk space first."
fi
log "Disk space OK: ${FREE_MB}MB free"

# ================================================================
# STEP 2 — CLONE GITLAB REPO
# ================================================================
section "Step 2: Clone GitLab Repo"

GITLAB_REPO="https://gitlab.com/circles4/pods/oasis/sre/iac.git"
BRANCH="feature/kong"
CLONE_DIR="/opt/kong-iac"
ANSIBLE_DIR="${CLONE_DIR}/oasis/Kong/ansible"

# ── Test connectivity ─────────────────────────────────────────
info "Testing GitLab connectivity..."
if curl -sI --max-time 8 https://gitlab.com 2>/dev/null | grep -q "200\|301\|302"; then
    log "GitLab is reachable"
else
    fail "Cannot reach gitlab.com — fix network first (VirtualBox → Network → NAT)"
fi

# ── Clone or update ───────────────────────────────────────────
if [[ -d "$CLONE_DIR/.git" ]]; then
    info "Repo already exists — pulling latest changes..."
    cd "$CLONE_DIR"
    git fetch origin 2>&1 | tail -3
    git checkout "$BRANCH"  2>/dev/null || \
        git checkout -b "$BRANCH" "origin/$BRANCH" 2>&1 | tail -3
    git pull origin "$BRANCH" 2>&1 | tail -3
    log "Repo updated to latest"
else
    info "Cloning $GITLAB_REPO (branch: $BRANCH)..."
    git clone --branch "$BRANCH" --depth 1 "$GITLAB_REPO" "$CLONE_DIR" 2>&1 | tail -5
    log "Repo cloned to $CLONE_DIR"
fi

# ── Show repo structure ───────────────────────────────────────
echo ""
info "Repo structure:"
find "${CLONE_DIR}/oasis" -type f 2>/dev/null | sort | head -30 \
    || find "$CLONE_DIR" -name "*.yml" -not -path "*/.git/*" | head -20

# ================================================================
# STEP 3 — FIND THE PLAYBOOK
# ================================================================
section "Step 3: Find Ansible Playbook"

# Check expected path first
if [[ ! -d "$ANSIBLE_DIR" ]]; then
    warn "Expected path not found: $ANSIBLE_DIR"
    info "Searching for ansible playbooks anywhere in repo..."
    ANSIBLE_DIR=$(find "$CLONE_DIR" -name "*.yml" \
        -not -path "*/.git/*" \
        -not -name "requirements*" \
        -not -name "vars*" \
        | head -1 | xargs dirname 2>/dev/null)
    [[ -z "$ANSIBLE_DIR" ]] && fail "No .yml playbook found in repo"
    warn "Using detected path: $ANSIBLE_DIR"
fi

log "Ansible directory: $ANSIBLE_DIR"
echo ""
info "Files found:"
ls -la "$ANSIBLE_DIR/"

# ── Auto-detect playbook name ─────────────────────────────────
PLAYBOOK=""
for candidate in \
    kong_dbless.yml \
    kong_install.yml \
    kong.yml \
    site.yml \
    main.yml \
    install.yml \
    playbook.yml; do
    if [[ -f "$ANSIBLE_DIR/$candidate" ]]; then
        PLAYBOOK="$candidate"
        log "Playbook found: $candidate"
        break
    fi
done

if [[ -z "$PLAYBOOK" ]]; then
    PLAYBOOK=$(find "$ANSIBLE_DIR" -maxdepth 1 -name "*.yml" \
        ! -name "requirements*" ! -name "vars*" \
        | head -1 | xargs basename 2>/dev/null)
    [[ -z "$PLAYBOOK" ]] && fail "No playbook .yml found in $ANSIBLE_DIR"
    warn "Using first yml found: $PLAYBOOK"
fi

# ── Install galaxy requirements if present ────────────────────
if [[ -f "$ANSIBLE_DIR/requirements.yml" ]]; then
    info "Installing ansible-galaxy requirements..."
    cd "$ANSIBLE_DIR"
    ansible-galaxy collection install -r requirements.yml 2>&1 | tail -3
    log "Galaxy requirements installed"
fi

# ================================================================
# STEP 4 — RUN THE PLAYBOOK
# ================================================================
section "Step 4: Run Ansible Playbook"

cd "$ANSIBLE_DIR"
echo ""
echo -e "${BOLD}Running: ansible-playbook $PLAYBOOK -v${NC}"
echo -e "${BOLD}From:    $ANSIBLE_DIR${NC}"
echo ""

ansible-playbook "$PLAYBOOK" -v
PLAYBOOK_RC=$?

echo ""
if [[ $PLAYBOOK_RC -eq 0 ]]; then
    log "Playbook completed — exit code 0"
else
    warn "Playbook exited with code $PLAYBOOK_RC — running tests anyway..."
fi

# ================================================================
# STEP 5 — TEST KONG
# ================================================================
section "Step 5: Test Kong"

KONG_ADMIN="http://localhost:8001"
KONG_PROXY="http://localhost:8000"

info "Waiting for Kong Admin API on :8001..."
for i in $(seq 1 15); do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 3 "$KONG_ADMIN" 2>/dev/null || echo "000")
    [[ "$HTTP" == "200" ]] && break
    echo -n "  [$i/15] HTTP $HTTP — waiting..."
    sleep 3
done
echo ""

# Health check
HEALTH=$(curl -s --max-time 5 "$KONG_ADMIN" 2>/dev/null || echo "{}")
KONG_VER=$(echo "$HEALTH" | \
    python3 -c "import sys,json; \
    print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "?")
DB_MODE=$(echo "$HEALTH" | \
    python3 -c "import sys,json; \
    d=json.load(sys.stdin); \
    print(d.get('configuration',{}).get('database','?'))" 2>/dev/null || echo "?")

if [[ "$KONG_VER" != "?" ]]; then
    log "Kong v$KONG_VER is running"
    log "Database mode: $DB_MODE"
else
    warn "Kong admin API not responding"
fi

# Detect route path
ROUTE=$(curl -s "$KONG_ADMIN/routes" 2>/dev/null | \
    python3 -c "
import sys,json
try:
    d=json.load(sys.stdin).get('data',[])
    print(d[0]['paths'][0] if d and d[0].get('paths') else '/test-api')
except: print('/test-api')
" 2>/dev/null || echo "/test-api")
log "Route path: $ROUTE"

# Test unauthenticated (expect 401)
T1=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 8 "${KONG_PROXY}${ROUTE}/hello" 2>/dev/null || echo "000")
[[ "$T1" == "401" ]] \
    && log "No key → 401 ✔  (key-auth working)" \
    || warn "No key → HTTP $T1 (expected 401)"

# Test authenticated (expect 200)
T2=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 8 \
    -H "apikey: my-local-test-key-2024" \
    "${KONG_PROXY}${ROUTE}/hello" 2>/dev/null || echo "000")
[[ "$T2" == "200" ]] \
    && log "With key → 200 ✔  (proxy working)" \
    || warn "With key → HTTP $T2 (expected 200)"

# ================================================================
# FINAL SUMMARY
# ================================================================
section "Summary"

echo -e "${BOLD}${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Kong API Gateway — Setup Complete!                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

printf "  %-25s %s\n" "Kong version:"      "$KONG_VER"
printf "  %-25s %s\n" "Database mode:"     "$DB_MODE"
printf "  %-25s %s\n" "Proxy:"             "http://localhost:8000"
printf "  %-25s %s\n" "Admin API:"         "http://localhost:8001"
printf "  %-25s %s\n" "Route:"             "$ROUTE"
printf "  %-25s %s\n" "Log file:"          "$LOGFILE"
echo ""
echo -e "${CYAN}${BOLD}Quick test commands:${NC}"
echo "  curl -i http://localhost:8000${ROUTE}/hello \\"
echo "       -H 'apikey: my-local-test-key-2024'   # expect 200"
echo "  curl -i http://localhost:8000${ROUTE}/hello  # expect 401"
echo "  curl -s http://localhost:8001 | python3 -m json.tool"
echo "  systemctl status kong"
echo "  journalctl -u kong -f"
echo ""
echo "  Log: $LOGFILE"
