#!/bin/bash
# =============================================================================
#  RabbitMQ Exporter — Fix 203/EXEC Error
#  Error   : status=203/EXEC means binary cannot be executed
#  Causes  : wrong permissions / wrong arch / corrupted binary
#  Usage   : sudo bash rmq_exec_fix.sh
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
EXPORTER_VERSION="0.29.0"
EXPORTER_PORT="9419"
EXPORTER_BINARY="/usr/local/bin/rabbitmq_exporter"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Fix: status=203/EXEC — Binary Cannot Execute      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# STEP 1 — Diagnose binary
# =============================================================================
echo -e "${BOLD}${CYAN}━━━  DIAGNOSE BINARY  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Binary details:"
ls -la "${EXPORTER_BINARY}" 2>/dev/null || warn "Binary NOT found at ${EXPORTER_BINARY}"

info "Binary type:"
file "${EXPORTER_BINARY}" 2>/dev/null || warn "Cannot determine file type"

info "System architecture:"
uname -m
dpkg --print-architecture

info "Try running binary directly:"
"${EXPORTER_BINARY}" --help 2>&1 | head -3 || warn "Binary execution failed"

echo ""

# =============================================================================
# STEP 2 — Stop old service and remove broken binary
# =============================================================================
echo -e "${BOLD}${CYAN}━━━  CLEANUP  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Stopping service ..."
systemctl stop rabbitmq_exporter 2>/dev/null || true
pkill -f rabbitmq_exporter 2>/dev/null || true
sleep 2

info "Removing old binary ..."
rm -f "${EXPORTER_BINARY}"
rm -f /tmp/rabbitmq_exporter*.tar.gz
rm -rf /tmp/rabbitmq_exporter-*
success "Cleanup done"

# =============================================================================
# STEP 3 — Re-download binary fresh
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  FRESH DOWNLOAD  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

ARCH=$(uname -m)
info "System arch: ${ARCH}"

# Map arch to download arch
if [[ "${ARCH}" == "x86_64" ]]; then
    DL_ARCH="amd64"
elif [[ "${ARCH}" == "aarch64" ]]; then
    DL_ARCH="arm64"
else
    DL_ARCH="amd64"
fi

info "Download arch: ${DL_ARCH}"

TARBALL="rabbitmq_exporter-${EXPORTER_VERSION}.linux-${DL_ARCH}.tar.gz"
URL="https://github.com/kbudde/rabbitmq_exporter/releases/download/v${EXPORTER_VERSION}/${TARBALL}"

info "Downloading from: ${URL}"
cd /tmp
wget --progress=bar:force --timeout=60 -O "${TARBALL}" "${URL}" \
    || { error "Download failed"; exit 1; }

info "Verifying download ..."
ls -lh "/tmp/${TARBALL}"
file "/tmp/${TARBALL}"

info "Extracting ..."
tar -xzf "${TARBALL}"

EXTRACT_DIR=$(tar -tzf "${TARBALL}" | head -1 | cut -d/ -f1)
info "Extracted to: /tmp/${EXTRACT_DIR}"
ls -la "/tmp/${EXTRACT_DIR}/"

info "Installing binary ..."
cp "/tmp/${EXTRACT_DIR}/rabbitmq_exporter" "${EXPORTER_BINARY}"
chmod 755 "${EXPORTER_BINARY}"
chown root:root "${EXPORTER_BINARY}"

info "Verify installed binary:"
ls -la "${EXPORTER_BINARY}"
file "${EXPORTER_BINARY}"

info "Test binary execution:"
"${EXPORTER_BINARY}" --help 2>&1 | head -3 \
    && success "Binary executes correctly ✅" \
    || { error "Binary still cannot execute"; file "${EXPORTER_BINARY}"; exit 1; }

# Cleanup
rm -rf "/tmp/${TARBALL}" "/tmp/${EXTRACT_DIR}"

# =============================================================================
# STEP 4 — Rewrite service file
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  REWRITE SERVICE  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Writing service file ..."
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
TimeoutStartSec=90

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
success "Service file updated"

# =============================================================================
# STEP 5 — Make sure management plugin and user are ready
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  FIX RABBITMQ  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Enabling management plugin ..."
rabbitmq-plugins enable rabbitmq_management > /dev/null 2>&1
success "Management plugin enabled"

info "Restarting RabbitMQ ..."
systemctl restart rabbitmq-server
sleep 6

info "Fixing admin user ..."
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
    [[ "${CODE}" == "200" ]] && { success "Management API ready ✅"; break; }
    echo "  attempt ${i}/20 — HTTP ${CODE}"; sleep 3
done

# =============================================================================
# STEP 6 — Start service
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  START SERVICE  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Starting rabbitmq_exporter ..."
systemctl start rabbitmq_exporter
sleep 6

info "Service status:"
systemctl status rabbitmq_exporter --no-pager -l | head -15
echo ""

# =============================================================================
# STEP 7 — Verification
# =============================================================================
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
check "Exporter /metrics working" "curl -sf http://localhost:${EXPORTER_PORT}/metrics"                              "rabbitmq_"
check "Queue metrics present"     "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue"        "rabbitmq_queue"
check "Node metrics present"      "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"         "rabbitmq_node"

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
    echo -e "${YELLOW}${BOLD}║      STILL ISSUES — Share output above              ║${NC}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "  Management UI  →  http://${IP}:15672   (${RMQ_USER} / ${RMQ_PASS})"
echo -e "  Exporter       →  http://${IP}:${EXPORTER_PORT}/metrics"
echo -e "  Total metrics  →  ${MCOUNT}"
echo ""
