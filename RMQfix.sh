#!/bin/bash
# =============================================================================
#  RabbitMQ Exporter — Diagnose & Fix Script
#  Usage : sudo bash rmq_fix.sh
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
echo -e "${BOLD}║   RabbitMQ Exporter — Diagnose & Fix                ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# STEP 1 — Diagnose current state
# =============================================================================
echo -e "${BOLD}${CYAN}━━━  DIAGNOSIS  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "RabbitMQ service status:"
systemctl status rabbitmq-server --no-pager -l | tail -5
echo ""

info "Exporter service status:"
systemctl status rabbitmq_exporter --no-pager -l | tail -5
echo ""

info "Exporter last 15 log lines:"
journalctl -u rabbitmq_exporter -n 15 --no-pager
echo ""

info "Listening ports:"
ss -tlnp | grep -E '5672|15672|9419' || warn "No ports found on 5672/15672/9419"
echo ""

info "Enabled plugins:"
rabbitmq-plugins list -e 2>/dev/null | grep -E 'management|prometheus' || warn "Could not list plugins"
echo ""

# =============================================================================
# STEP 2 — Fix RabbitMQ management plugin
# =============================================================================
echo -e "${BOLD}${CYAN}━━━  FIXES  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Enabling management plugin ..."
rabbitmq-plugins enable rabbitmq_management
sleep 3
success "Management plugin enabled"

info "Restarting RabbitMQ ..."
systemctl restart rabbitmq-server
sleep 5

if systemctl is-active --quiet rabbitmq-server; then
    success "RabbitMQ restarted OK"
else
    error "RabbitMQ failed to restart"
    journalctl -u rabbitmq-server -n 20 --no-pager
    exit 1
fi

# =============================================================================
# STEP 3 — Fix admin user
# =============================================================================
info "Ensuring admin user exists ..."
sleep 3

# Check if user exists
if rabbitmqctl list_users 2>/dev/null | grep -q "^${RMQ_USER}"; then
    info "User '${RMQ_USER}' exists — resetting password ..."
    rabbitmqctl change_password "${RMQ_USER}" "${RMQ_PASS}"
else
    info "Creating user '${RMQ_USER}' ..."
    rabbitmqctl delete_user guest 2>/dev/null || true
    rabbitmqctl add_user "${RMQ_USER}" "${RMQ_PASS}"
fi

rabbitmqctl set_user_tags "${RMQ_USER}" administrator
rabbitmqctl set_permissions -p "/" "${RMQ_USER}" ".*" ".*" ".*"
success "User '${RMQ_USER}' ready"

# =============================================================================
# STEP 4 — Wait for management API
# =============================================================================
info "Waiting for management API on port 15672 ..."
for i in $(seq 1 20); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${RMQ_USER}:${RMQ_PASS}" \
        http://localhost:15672/api/overview 2>/dev/null || echo "000")
    if [[ "${CODE}" == "200" ]]; then
        success "Management API is UP (HTTP 200)"
        break
    fi
    echo -n "  attempt ${i}/20 (got ${CODE}) ... "
    sleep 3
done
echo ""

# =============================================================================
# STEP 5 — Fix exporter service
# =============================================================================
info "Stopping exporter ..."
systemctl stop rabbitmq_exporter 2>/dev/null || true
sleep 2

info "Rewriting exporter service with correct settings ..."
cat > /etc/systemd/system/rabbitmq_exporter.service << EOF
[Unit]
Description=RabbitMQ Prometheus Exporter
After=network.target rabbitmq-server.service
Wants=rabbitmq-server.service

[Service]
User=root
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

systemctl daemon-reload
sleep 1

info "Starting exporter ..."
systemctl start rabbitmq_exporter
sleep 5

if systemctl is-active --quiet rabbitmq_exporter; then
    success "rabbitmq_exporter is running"
else
    error "Exporter still failing — logs:"
    journalctl -u rabbitmq_exporter -n 30 --no-pager
    exit 1
fi

# =============================================================================
# STEP 6 — Verify
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  VERIFICATION  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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
    echo -e "${YELLOW}${BOLD}║      STILL SOME ISSUES — Check logs above            ║${NC}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "  Management UI  →  http://${IP}:15672   (${RMQ_USER} / ${RMQ_PASS})"
echo -e "  Exporter       →  http://${IP}:${EXPORTER_PORT}/metrics"
echo -e "  Total metrics  →  ${MCOUNT}"
echo ""
echo -e "  ${BOLD}Debug commands:${NC}"
echo -e "    journalctl -u rabbitmq_exporter -f"
echo -e "    journalctl -u rabbitmq-server -f"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | head -20"
echo ""
