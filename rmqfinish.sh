#!/bin/bash
# =============================================================================
#  RabbitMQ Exporter — Service Setup + Test
#  Run this if binary is already installed at /usr/local/bin/rabbitmq_exporter
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || error "Run as root:  sudo bash $0"

RMQ_USER="admin"
RMQ_PASS="admin123"
EXPORTER_PORT="9419"
EXPORTER_BINARY="/usr/local/bin/rabbitmq_exporter"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   RabbitMQ Exporter — Service Setup + Test      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# STEP 1 — Verify binary exists
# =============================================================================
info "Checking binary …"
[[ -f "${EXPORTER_BINARY}" ]] \
    && success "Binary found: ${EXPORTER_BINARY}" \
    || error "Binary not found at ${EXPORTER_BINARY} — run installRMQ_v5.sh first"

# =============================================================================
# STEP 2 — Create system user
# =============================================================================
info "Creating system user …"
useradd --system --no-create-home --shell /bin/false rabbitmq_exporter 2>/dev/null || true
success "User 'rabbitmq_exporter' ready"

# =============================================================================
# STEP 3 — Write systemd service
# =============================================================================
info "Writing systemd service file …"
cat > /etc/systemd/system/rabbitmq_exporter.service <<EOF
[Unit]
Description=RabbitMQ Prometheus Exporter
Documentation=https://github.com/kbudde/rabbitmq_exporter
After=network.target rabbitmq-server.service
Wants=rabbitmq-server.service

[Service]
User=rabbitmq_exporter
Group=rabbitmq_exporter
Type=simple
Restart=on-failure
RestartSec=5s

Environment="RABBIT_URL=http://localhost:15672"
Environment="RABBIT_USER=${RMQ_USER}"
Environment="RABBIT_PASSWORD=${RMQ_PASS}"
Environment="PUBLISH_PORT=${EXPORTER_PORT}"
Environment="RABBIT_CAPABILITIES=bert,no_sort"
Environment="RABBIT_EXPORTERS=exchange,node,overview,queue"
Environment="OUTPUT_FORMAT=TTY"
Environment="LOG_LEVEL=info"

ExecStart=${EXPORTER_BINARY}

[Install]
WantedBy=multi-user.target
EOF
success "Service file written"

# =============================================================================
# STEP 4 — Enable and start service
# =============================================================================
info "Reloading systemd …"
systemctl daemon-reload

info "Enabling service …"
systemctl enable rabbitmq_exporter

info "Starting service …"
systemctl start rabbitmq_exporter
sleep 4

if systemctl is-active --quiet rabbitmq_exporter; then
    success "rabbitmq_exporter is running  ✓"
else
    echo ""
    echo -e "${RED}Service failed. Logs:${NC}"
    journalctl -u rabbitmq_exporter -n 30 --no-pager
    error "Exporter failed to start"
fi

# =============================================================================
# STEP 5 — Firewall
# =============================================================================
if ufw status 2>/dev/null | grep -q "Status: active"; then
    info "Opening port ${EXPORTER_PORT} …"
    ufw allow "${EXPORTER_PORT}"/tcp > /dev/null 2>&1
    success "Port ${EXPORTER_PORT} opened"
fi

# =============================================================================
# STEP 6 — Tests
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  LOCAL TESTS                                     ${NC}"
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
        echo -e "       Expected : '${EXPECT}'"
        echo -e "       Got      : $(echo "${OUT}" | head -1)"
        FAIL=$((FAIL+1))
    fi
}

echo -e "  ${BOLD}── Services ──────────────────────────────────────${NC}"
check "rabbitmq-server active"   "systemctl is-active rabbitmq-server"   "active"
check "rabbitmq_exporter active" "systemctl is-active rabbitmq_exporter" "active"

echo ""
echo -e "  ${BOLD}── Ports ─────────────────────────────────────────${NC}"
check "AMQP       5672  listening" "ss -tlnp | grep ':5672'"  "5672"
check "Management 15672 listening" "ss -tlnp | grep ':15672'" "15672"
check "Exporter   9419  listening" "ss -tlnp | grep ':9419'"  "9419"

echo ""
echo -e "  ${BOLD}── API & Metrics ─────────────────────────────────${NC}"
check "Management API health" \
    "curl -sf -u ${RMQ_USER}:${RMQ_PASS} http://localhost:15672/api/healthchecks/node" "ok"

check "Exporter /metrics reachable" \
    "curl -sf http://localhost:${EXPORTER_PORT}/metrics" "rabbitmq_"

check "Queue metrics present" \
    "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep -m1 rabbitmq_queue" "rabbitmq_queue"

check "Node metrics present" \
    "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep -m1 rabbitmq_node" "rabbitmq_node"

check "Overview metrics present" \
    "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep -m1 rabbitmq_overview" "rabbitmq_overview"

echo ""
MCOUNT=$(curl -sf "http://localhost:${EXPORTER_PORT}/metrics" \
    | grep -v "^#" | wc -l 2>/dev/null || echo "0")
echo -e "  Total metrics exposed : ${GREEN}${BOLD}${MCOUNT}${NC}"

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed${NC} : ${BOLD}${PASS}${NC}   ${RED}Failed${NC} : ${BOLD}${FAIL}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# =============================================================================
# Summary
# =============================================================================
IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║      ALL DONE  🐇                               ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Management UI  →  http://${IP}:15672   (${RMQ_USER} / ${RMQ_PASS})"
echo -e "  Exporter       →  http://${IP}:${EXPORTER_PORT}/metrics"
echo -e "  Total metrics  →  ${MCOUNT}"
echo ""
echo -e "  ${BOLD}Test anytime:${NC}"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep -v '^#' | wc -l"
echo ""
echo -e "  ${BOLD}Logs:${NC}"
echo -e "    journalctl -u rabbitmq_exporter -f"
echo ""
