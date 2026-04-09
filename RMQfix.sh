#!/bin/bash
# =============================================================================
#  RabbitMQ Exporter — Deep Fix Script
#  Usage : sudo bash rmq_deepfix.sh
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0"; exit 1; }

RMQ_USER="admin"
RMQ_PASS="admin123"
EXPORTER_PORT="9419"
EXPORTER_BINARY="/usr/local/bin/rabbitmq_exporter"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   RabbitMQ Exporter — Deep Fix                      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# STEP 1 — Show exact logs
# =============================================================================
echo -e "${BOLD}${CYAN}━━━  EXACT LOGS  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Exporter journal logs:"
journalctl -u rabbitmq_exporter -n 30 --no-pager
echo ""

info "RabbitMQ journal logs:"
journalctl -u rabbitmq-server -n 15 --no-pager
echo ""

info "All listening ports:"
ss -tlnp
echo ""

info "Binary check:"
ls -la "${EXPORTER_BINARY}" 2>/dev/null || warn "Binary not found at ${EXPORTER_BINARY}"
file "${EXPORTER_BINARY}" 2>/dev/null || true
echo ""

info "Test binary directly:"
timeout 5 "${EXPORTER_BINARY}" --help 2>&1 | head -5 || warn "Binary test failed"
echo ""

info "RabbitMQ users:"
rabbitmqctl list_users 2>/dev/null
echo ""

info "RabbitMQ plugins:"
rabbitmq-plugins list -e 2>/dev/null
echo ""

info "Test management API directly:"
curl -v -u "${RMQ_USER}:${RMQ_PASS}" \
    http://localhost:15672/api/overview 2>&1 | tail -10
echo ""

# =============================================================================
# STEP 2 — Kill any stuck exporter processes
# =============================================================================
echo -e "${BOLD}${CYAN}━━━  CLEANUP  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Killing any stuck rabbitmq_exporter processes ..."
pkill -f rabbitmq_exporter 2>/dev/null || true
sleep 2

info "Stopping service ..."
systemctl stop rabbitmq_exporter 2>/dev/null || true
sleep 2
success "Cleanup done"

# =============================================================================
# STEP 3 — Restart RabbitMQ cleanly
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  RESTART RABBITMQ  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Restarting RabbitMQ server ..."
systemctl restart rabbitmq-server
sleep 6

info "Re-enabling management plugin ..."
rabbitmq-plugins enable rabbitmq_management
sleep 4

info "Checking RabbitMQ status ..."
systemctl is-active rabbitmq-server \
    && success "RabbitMQ is running" \
    || { error "RabbitMQ not running"; journalctl -u rabbitmq-server -n 20 --no-pager; exit 1; }

# =============================================================================
# STEP 4 — Fix admin user
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  FIX ADMIN USER  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Waiting for RabbitMQ to be fully ready ..."
for i in $(seq 1 15); do
    if rabbitmqctl status > /dev/null 2>&1; then
        success "RabbitMQ is ready"
        break
    fi
    echo "  waiting ... ${i}/15"
    sleep 3
done

info "Setting up admin user ..."
rabbitmqctl delete_user guest 2>/dev/null || true
rabbitmqctl add_user "${RMQ_USER}" "${RMQ_PASS}" 2>/dev/null \
    || rabbitmqctl change_password "${RMQ_USER}" "${RMQ_PASS}"
rabbitmqctl set_user_tags "${RMQ_USER}" administrator
rabbitmqctl set_permissions -p "/" "${RMQ_USER}" ".*" ".*" ".*"
success "Admin user ready"

info "Waiting for management API ..."
for i in $(seq 1 20); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${RMQ_USER}:${RMQ_PASS}" \
        http://localhost:15672/api/overview 2>/dev/null || echo "000")
    if [[ "${CODE}" == "200" ]]; then
        success "Management API ready (HTTP 200)"
        break
    fi
    echo "  attempt ${i}/20 — HTTP ${CODE}"
    sleep 3
done

# =============================================================================
# STEP 5 — Test binary directly before starting service
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  TEST BINARY DIRECTLY  ━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Running exporter binary directly for 8 seconds ..."
RABBIT_URL="http://localhost:15672" \
RABBIT_USER="${RMQ_USER}" \
RABBIT_PASSWORD="${RMQ_PASS}" \
PUBLISH_PORT="${EXPORTER_PORT}" \
RABBIT_CAPABILITIES="bert,no_sort" \
RABBIT_EXPORTERS="exchange,node,overview,queue" \
OUTPUT_FORMAT="TTY" \
LOG_LEVEL="info" \
timeout 8 "${EXPORTER_BINARY}" &

EXPORTER_PID=$!
sleep 5

info "Testing metrics while binary runs directly ..."
DIRECT_TEST=$(curl -sf "http://localhost:${EXPORTER_PORT}/metrics" 2>/dev/null || echo "FAILED")

if echo "${DIRECT_TEST}" | grep -q "rabbitmq_"; then
    success "Binary works fine when run directly ✅"
    BINARY_OK=true
else
    warn "Binary test result: ${DIRECT_TEST:0:100}"
    BINARY_OK=false
fi

kill ${EXPORTER_PID} 2>/dev/null || true
sleep 2

# =============================================================================
# STEP 6 — Rewrite systemd service
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  REWRITE SYSTEMD SERVICE  ━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Writing new service file (running as root to avoid permission issues) ..."
cat > /etc/systemd/system/rabbitmq_exporter.service << EOF
[Unit]
Description=RabbitMQ Prometheus Exporter
After=network.target rabbitmq-server.service
Wants=rabbitmq-server.service

[Service]
User=root
Group=root
Type=simple
Restart=always
RestartSec=10s
TimeoutStartSec=60

Environment="RABBIT_URL=http://localhost:15672"
Environment="RABBIT_USER=${RMQ_USER}"
Environment="RABBIT_PASSWORD=${RMQ_PASS}"
Environment="PUBLISH_PORT=${EXPORTER_PORT}"
Environment="RABBIT_CAPABILITIES=bert,no_sort"
Environment="RABBIT_EXPORTERS=exchange,node,overview,queue"
Environment="OUTPUT_FORMAT=TTY"
Environment="LOG_LEVEL=info"

ExecStartPre=/bin/sleep 5
ExecStart=${EXPORTER_BINARY}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
success "Service file updated"

info "Starting rabbitmq_exporter service ..."
systemctl start rabbitmq_exporter
sleep 8

info "Service status:"
systemctl status rabbitmq_exporter --no-pager -l | head -15
echo ""

# =============================================================================
# STEP 7 — Final verification
# =============================================================================
echo -e "${BOLD}${CYAN}━━━  FINAL VERIFICATION  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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

check "rabbitmq-server active"    "systemctl is-active rabbitmq-server"    "active"
check "rabbitmq_exporter active"  "systemctl is-active rabbitmq_exporter"  "active"
check "Port 5672  listening"      "ss -tlnp | grep ':5672'"                "5672"
check "Port 15672 listening"      "ss -tlnp | grep ':15672'"               "15672"
check "Port 9419  listening"      "ss -tlnp | grep ':9419'"                "9419"
check "Management API health"     "curl -sf -u ${RMQ_USER}:${RMQ_PASS} http://localhost:15672/api/healthchecks/node" "ok"
check "Exporter /metrics working" "curl -sf http://localhost:${EXPORTER_PORT}/metrics" "rabbitmq_"
check "Queue metrics present"     "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue" "rabbitmq_queue"
check "Node metrics present"      "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"  "rabbitmq_node"

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
    echo -e "${GREEN}${BOLD}║      ALL FIXED — RabbitMQ Exporter Ready  🐇        ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}${BOLD}║      STILL ISSUES — Collect logs below              ║${NC}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Run these and share output:${NC}"
    echo -e "    journalctl -u rabbitmq_exporter -n 30 --no-pager"
    echo -e "    journalctl -u rabbitmq-server -n 30 --no-pager"
fi

echo ""
echo -e "  Management UI  →  http://${IP}:15672   (${RMQ_USER} / ${RMQ_PASS})"
echo -e "  Exporter       →  http://${IP}:${EXPORTER_PORT}/metrics"
echo -e "  Total metrics  →  ${MCOUNT}"
echo ""
