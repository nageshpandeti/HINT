#!/bin/bash
# =============================================================================
#  RabbitMQ Exporter — Stop & Remove Script
#  Ubuntu 22.04
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || error "Run as root:  sudo bash $0"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   RabbitMQ Exporter — Stop & Remove             ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# STEP 1 — Stop the service
# =============================================================================
info "Stopping rabbitmq_exporter service ..."
systemctl stop rabbitmq_exporter 2>/dev/null \
    && success "Service stopped" \
    || info "Service was not running"

# =============================================================================
# STEP 2 — Disable the service
# =============================================================================
info "Disabling rabbitmq_exporter service ..."
systemctl disable rabbitmq_exporter 2>/dev/null \
    && success "Service disabled" \
    || info "Service was not enabled"

# =============================================================================
# STEP 3 — Remove systemd service file
# =============================================================================
info "Removing systemd service file ..."
if [[ -f /etc/systemd/system/rabbitmq_exporter.service ]]; then
    rm -f /etc/systemd/system/rabbitmq_exporter.service
    success "Service file removed"
else
    info "Service file not found — skipping"
fi

# =============================================================================
# STEP 4 — Reload systemd
# =============================================================================
info "Reloading systemd daemon ..."
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true
success "Systemd reloaded"

# =============================================================================
# STEP 5 — Remove binary
# =============================================================================
info "Removing exporter binary ..."
if [[ -f /usr/local/bin/rabbitmq_exporter ]]; then
    rm -f /usr/local/bin/rabbitmq_exporter
    success "Binary removed: /usr/local/bin/rabbitmq_exporter"
else
    info "Binary not found — skipping"
fi

# =============================================================================
# STEP 6 — Remove system user
# =============================================================================
info "Removing system user 'rabbitmq_exporter' ..."
if id rabbitmq_exporter &>/dev/null; then
    userdel rabbitmq_exporter 2>/dev/null
    success "User removed"
else
    info "User not found — skipping"
fi

# =============================================================================
# STEP 7 — Verify everything is gone
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  VERIFICATION                                    ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

PASS=0; FAIL=0

check_removed() {
    local NAME="$1" CHECK="$2"
    if eval "${CHECK}" > /dev/null 2>&1; then
        echo -e "  ${RED}✘${NC}  ${NAME} — still exists!"
        FAIL=$((FAIL+1))
    else
        echo -e "  ${GREEN}✔${NC}  ${NAME} — removed"
        PASS=$((PASS+1))
    fi
}

check_removed "Service file gone" \
    "[[ -f /etc/systemd/system/rabbitmq_exporter.service ]]"

check_removed "Binary gone" \
    "[[ -f /usr/local/bin/rabbitmq_exporter ]]"

check_removed "System user gone" \
    "id rabbitmq_exporter"

check_removed "Service not active" \
    "systemctl is-active --quiet rabbitmq_exporter"

check_removed "Port 9419 not listening" \
    "ss -tlnp | grep -q ':9419'"

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "  Removed : ${GREEN}${BOLD}${PASS}${NC}   Remaining : ${RED}${BOLD}${FAIL}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

echo ""
if [[ ${FAIL} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   RabbitMQ Exporter Fully Removed  ✓            ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
else
    echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║   Some items could not be removed — check above  ║${NC}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
fi

echo ""
info "RabbitMQ itself is still running (not touched)"
info "To verify:  systemctl status rabbitmq-server"
echo ""
