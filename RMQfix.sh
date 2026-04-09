#!/bin/bash
# =============================================================================
#  RabbitMQ Exporter — Direct Binary Install Fix
#  Error   : No such file or directory at /usr/local/bin/rabbitmq_exporter
#  Usage   : sudo bash rmq_binary_fix.sh
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || error "Run as root: sudo bash $0"

RMQ_USER="admin"
RMQ_PASS="admin123"
EXPORTER_PORT="9419"
EXPORTER_BINARY="/usr/local/bin/rabbitmq_exporter"
VERSION="0.29.0"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Fix: Binary Not Found — Direct Install             ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# STEP 1 — Stop service
# =============================================================================
info "Stopping service ..."
systemctl stop rabbitmq_exporter 2>/dev/null || true
systemctl disable rabbitmq_exporter 2>/dev/null || true
sleep 2
success "Service stopped"

# =============================================================================
# STEP 2 — Clean temp files
# =============================================================================
info "Cleaning old temp files ..."
rm -f /tmp/rabbitmq_exporter*.tar.gz
rm -rf /tmp/rabbitmq_exporter-*
rm -f "${EXPORTER_BINARY}"
success "Cleaned"

# =============================================================================
# STEP 3 — Download fresh binary
# =============================================================================
info "Downloading rabbitmq_exporter v${VERSION} ..."

TARBALL="rabbitmq_exporter-${VERSION}.linux-amd64.tar.gz"
URL="https://github.com/kbudde/rabbitmq_exporter/releases/download/v${VERSION}/${TARBALL}"

cd /tmp
wget -q --show-progress -O "${TARBALL}" "${URL}" \
    || error "Download failed"

info "Download complete. Verifying ..."
ls -lh "/tmp/${TARBALL}"
file "/tmp/${TARBALL}"

# =============================================================================
# STEP 4 — Extract and install binary
# =============================================================================
info "Extracting ..."
tar -xzf "${TARBALL}" -C /tmp/

info "Looking for binary ..."
BINARY_PATH=$(find /tmp -name "rabbitmq_exporter" -type f 2>/dev/null | head -1)
echo "  Found at: ${BINARY_PATH}"

[[ -z "${BINARY_PATH}" ]] && error "Binary not found after extraction"

info "Installing to ${EXPORTER_BINARY} ..."
cp "${BINARY_PATH}" "${EXPORTER_BINARY}"
chmod 755 "${EXPORTER_BINARY}"
chown root:root "${EXPORTER_BINARY}"

success "Binary installed"

info "Verify binary exists:"
ls -la "${EXPORTER_BINARY}"
file "${EXPORTER_BINARY}"

# =============================================================================
# STEP 5 — Test binary directly
# =============================================================================
info "Testing binary directly ..."
"${EXPORTER_BINARY}" --help > /dev/null 2>&1 \
    && success "Binary runs correctly ✅" \
    || error "Binary still cannot run"

# =============================================================================
# STEP 6 — Clean temp
# =============================================================================
rm -f "/tmp/${TARBALL}"
rm -rf /tmp/rabbitmq_exporter-*
success "Temp files cleaned"

# =============================================================================
# STEP 7 — Rewrite and start service
# =============================================================================
info "Writing systemd service ..."
cat > /etc/systemd/system/rabbitmq_exporter.service << EOF
[Unit]
Description=RabbitMQ Prometheus Exporter
After=network.target rabbitmq-server.service
Wants=rabbitmq-server.service

[Service]
User=root
Group=root
Type=simple
Restart=on-failure
RestartSec=10s

Environment="RABBIT_URL=http://localhost:15672"
Environment="RABBIT_USER=${RMQ_USER}"
Environment="RABBIT_PASSWORD=${RMQ_PASS}"
Environment="PUBLISH_PORT=${EXPORTER_PORT}"
Environment="RABBIT_CAPABILITIES=bert,no_sort"
Environment="RABBIT_EXPORTERS=exchange,node,overview,queue"
Environment="OUTPUT_FORMAT=TTY"
Environment="LOG_LEVEL=info"

ExecStart=${EXPORTER_BINARY}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rabbitmq_exporter
systemctl start rabbitmq_exporter
sleep 5

if systemctl is-active --quiet rabbitmq_exporter; then
    success "rabbitmq_exporter service running ✅"
else
    echo ""
    journalctl -u rabbitmq_exporter -n 20 --no-pager
    error "Service still failing — see logs above"
fi

# =============================================================================
# STEP 8 — Final tests
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  FINAL TESTS                                     ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

PASS=0; FAIL=0

check() {
    local NAME="$1" CMD="$2" EXPECT="$3" OUT
    OUT=$(eval "${CMD}" 2>&1 || true)
    if echo "${OUT}" | grep -q "${EXPECT}"; then
        echo -e "  ${GREEN}✔${NC}  ${NAME}"; PASS=$((PASS+1))
    else
        echo -e "  ${RED}✘${NC}  ${NAME}"
        echo -e "       Got: $(echo "${OUT}" | head -1)"
        FAIL=$((FAIL+1))
    fi
}

check "rabbitmq-server active"   "systemctl is-active rabbitmq-server"   "active"
check "rabbitmq_exporter active" "systemctl is-active rabbitmq_exporter" "active"
check "Port 5672  listening"     "ss -tlnp | grep ':5672'"               "5672"
check "Port 15672 listening"     "ss -tlnp | grep ':15672'"              "15672"
check "Port 9419  listening"     "ss -tlnp | grep ':9419'"               "9419"
check "Management API health"    "curl -sf -u ${RMQ_USER}:${RMQ_PASS} http://localhost:15672/api/healthchecks/node" "ok"
check "Exporter metrics working" "curl -sf http://localhost:${EXPORTER_PORT}/metrics"                               "rabbitmq_"
check "Queue metrics present"    "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue"         "rabbitmq_queue"
check "Node metrics present"     "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"          "rabbitmq_node"

MCOUNT=$(curl -sf "http://localhost:${EXPORTER_PORT}/metrics" \
    | grep -v "^#" | wc -l 2>/dev/null || echo "0")
IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "  Passed : ${GREEN}${BOLD}${PASS}${NC}   Failed : ${RED}${BOLD}${FAIL}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

if [[ ${FAIL} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║      ALL DONE — RabbitMQ Exporter Ready  🐇         ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║      STILL ISSUES — Share output above              ║${NC}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "  Management UI  →  http://${IP}:15672   (${RMQ_USER} / ${RMQ_PASS})"
echo -e "  Exporter       →  http://${IP}:${EXPORTER_PORT}/metrics"
echo -e "  Total metrics  →  ${MCOUNT}"
echo ""
