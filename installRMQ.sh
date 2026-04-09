#!/bin/bash
# =============================================================================
#  RabbitMQ Exporter ONLY — Ubuntu 22.04
#  Version      : 5.0
#  Fixes        : Correct exporter version v0.29.0 (v1.0.0 does not exist)
#  NOTE         : RabbitMQ is already installed — this script only installs
#                 the exporter binary + systemd service
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
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || error "Run as root:  sudo bash $0"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   RabbitMQ Exporter Installer    (Ubuntu 22.04) ║${NC}"
echo -e "${BOLD}║   Version 5.0  — Exporter only                  ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

RMQ_USER="admin"
RMQ_PASS="admin123"
EXPORTER_VERSION="0.29.0"
EXPORTER_PORT="9419"
EXPORTER_BINARY="/usr/local/bin/rabbitmq_exporter"

# =============================================================================
# STEP 1 — Verify RabbitMQ is running
# =============================================================================
info "Checking RabbitMQ status …"
if systemctl is-active --quiet rabbitmq-server; then
    success "RabbitMQ is already running — skipping install"
else
    error "RabbitMQ is NOT running. Start it first:  sudo systemctl start rabbitmq-server"
fi

# =============================================================================
# STEP 2 — Verify management plugin is enabled
# =============================================================================
info "Checking management plugin …"
if curl -sf -u "${RMQ_USER}:${RMQ_PASS}" \
    http://localhost:15672/api/overview > /dev/null 2>&1; then
    success "Management API is reachable on port 15672"
else
    warn "Management API not responding — enabling plugin now …"
    rabbitmq-plugins enable rabbitmq_management
    sleep 3
fi

# =============================================================================
# STEP 3 — Remove any old exporter binary/service
# =============================================================================
info "Cleaning up any old exporter install …"
systemctl stop  rabbitmq_exporter 2>/dev/null || true
systemctl disable rabbitmq_exporter 2>/dev/null || true
rm -f "${EXPORTER_BINARY}"
rm -f /etc/systemd/system/rabbitmq_exporter.service
systemctl daemon-reload 2>/dev/null || true
success "Old exporter removed"

# =============================================================================
# STEP 4 — Download correct exporter binary (v0.29.0)
# =============================================================================
info "Downloading rabbitmq_exporter v${EXPORTER_VERSION} …"

TARBALL="rabbitmq_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz"
URL="https://github.com/kbudde/rabbitmq_exporter/releases/download/v${EXPORTER_VERSION}/${TARBALL}"

info "URL: ${URL}"
cd /tmp
rm -f "${TARBALL}"

wget --progress=bar:force \
     --timeout=60 \
     -O "${TARBALL}" \
     "${URL}" || error "Download failed — check internet / URL"

info "Extracting …"
tar -xzf "${TARBALL}"

# Find the binary (may be in a subdir or directly in tarball)
BINARY_PATH=$(find /tmp -name "rabbitmq_exporter" -type f 2>/dev/null | head -1)
[[ -z "${BINARY_PATH}" ]] && error "Binary not found in extracted archive"

install -m 755 "${BINARY_PATH}" "${EXPORTER_BINARY}"
rm -rf "/tmp/${TARBALL}" "/tmp/rabbitmq_exporter-${EXPORTER_VERSION}.linux-amd64"
success "Binary installed → ${EXPORTER_BINARY}"

# Confirm binary works
${EXPORTER_BINARY} --version 2>/dev/null || true

# =============================================================================
# STEP 5 — Create dedicated system user
# =============================================================================
info "Creating system user …"
useradd --system --no-create-home --shell /bin/false rabbitmq_exporter 2>/dev/null || true
success "User 'rabbitmq_exporter' ready"

# =============================================================================
# STEP 6 — Create systemd service
# =============================================================================
info "Creating systemd service …"
cat > /etc/systemd/system/rabbitmq_exporter.service <<EOF
[Unit]
Description=RabbitMQ Prometheus Exporter v${EXPORTER_VERSION}
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

systemctl daemon-reload
systemctl enable rabbitmq_exporter
systemctl start  rabbitmq_exporter
sleep 3

if systemctl is-active --quiet rabbitmq_exporter; then
    success "rabbitmq_exporter service is running  ✓"
else
    echo ""
    journalctl -u rabbitmq_exporter -n 20 --no-pager
    error "Exporter failed — see logs above"
fi

# =============================================================================
# STEP 7 — Firewall
# =============================================================================
if ufw status 2>/dev/null | grep -q "Status: active"; then
    info "Opening port ${EXPORTER_PORT} in ufw …"
    ufw allow "${EXPORTER_PORT}"/tcp > /dev/null 2>&1
    success "Port ${EXPORTER_PORT} opened"
fi

# =============================================================================
# STEP 8 — Tests
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  RUNNING LOCAL TESTS                             ${NC}"
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
check "rabbitmq-server active"    "systemctl is-active rabbitmq-server"   "active"
check "rabbitmq_exporter active"  "systemctl is-active rabbitmq_exporter" "active"

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
    "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep -m1 rabbitmq_queue" \
    "rabbitmq_queue"

check "Node metrics present" \
    "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep -m1 rabbitmq_node" \
    "rabbitmq_node"

check "Overview metrics present" \
    "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep -m1 rabbitmq_overview" \
    "rabbitmq_overview"

echo ""
MCOUNT=$(curl -sf "http://localhost:${EXPORTER_PORT}/metrics" \
    | grep -v "^#" | wc -l 2>/dev/null || echo "0")
echo -e "  Total metrics exposed : ${GREEN}${BOLD}${MCOUNT}${NC}"

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed${NC} : ${BOLD}${PASS}${NC}   ${RED}Failed${NC} : ${BOLD}${FAIL}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# =============================================================================
# STEP 9 — Summary
# =============================================================================
IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║      EXPORTER INSTALLED SUCCESSFULLY  🐇         ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}RabbitMQ Management UI${NC}"
echo -e "    http://${IP}:15672   →  ${RMQ_USER} / ${RMQ_PASS}"
echo ""
echo -e "  ${BOLD}Exporter Metrics Endpoint${NC}"
echo -e "    http://${IP}:${EXPORTER_PORT}/metrics"
echo ""
echo -e "  ${BOLD}Quick curl tests:${NC}"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep -v '^#' | wc -l"
echo ""
echo -e "  ${BOLD}Service commands:${NC}"
echo -e "    systemctl status  rabbitmq_exporter"
echo -e "    systemctl restart rabbitmq_exporter"
echo -e "    journalctl -u rabbitmq_exporter -f"
echo ""
