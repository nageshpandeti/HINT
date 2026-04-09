#!/bin/bash
# =============================================================================
#  RabbitMQ Exporter — All In One Script
#  Includes : Uninstall + Install Go + Build Exporter + Service + Test
#  Target   : Ubuntu 22.04 (VirtualBox)
#  Usage    : sudo bash rmq_allinone.sh
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

[[ $EUID -eq 0 ]] || error "Run as root: sudo bash $0"

# ── Config ───────────────────────────────────────────────────────────────────
RMQ_USER="admin"
RMQ_PASS="admin123"
EXPORTER_PORT="9419"
EXPORTER_BINARY="/usr/local/bin/rabbitmq_exporter"
GOPATH_DIR="/root/go"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   RabbitMQ Exporter — All In One Setup                  ║${NC}"
echo -e "${BOLD}║   Uninstall → Build from Source → Service → Test        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  OS     : $(lsb_release -ds 2>/dev/null)"
echo -e "  Kernel : $(uname -r)"
echo -e "  Arch   : $(uname -m)"
echo ""

# =============================================================================
# PHASE 1 — UNINSTALL OLD EXPORTER
# =============================================================================
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PHASE 1 — Uninstall Old Exporter${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Stopping rabbitmq_exporter service ..."
systemctl stop    rabbitmq_exporter 2>/dev/null || true
systemctl disable rabbitmq_exporter 2>/dev/null || true

info "Removing service file ..."
rm -f /etc/systemd/system/rabbitmq_exporter.service
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

info "Removing binary ..."
rm -f "${EXPORTER_BINARY}"

info "Removing system user ..."
userdel rabbitmq_exporter 2>/dev/null || true

info "Cleaning temp files ..."
rm -f /tmp/rabbitmq_exporter*.tar.gz
rm -rf /tmp/rabbitmq_exporter-*
rm -rf "${GOPATH_DIR}/src/github.com/kbudde/rabbitmq_exporter"

success "PHASE 1 COMPLETE — Old exporter removed"

# =============================================================================
# PHASE 2 — VERIFY RABBITMQ
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PHASE 2 — Verify & Fix RabbitMQ${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Checking RabbitMQ service ..."
if ! systemctl is-active --quiet rabbitmq-server; then
    info "Starting RabbitMQ ..."
    systemctl start rabbitmq-server
    sleep 5
fi
systemctl is-active --quiet rabbitmq-server \
    && success "RabbitMQ is running" \
    || error "RabbitMQ is not running — install RabbitMQ first"

info "Enabling management plugin ..."
rabbitmq-plugins enable rabbitmq_management > /dev/null 2>&1
success "Management plugin enabled"

info "Restarting RabbitMQ ..."
systemctl restart rabbitmq-server
sleep 6
success "RabbitMQ restarted"

info "Setting up admin user ..."
rabbitmqctl delete_user guest 2>/dev/null || true
rabbitmqctl add_user "${RMQ_USER}" "${RMQ_PASS}" 2>/dev/null \
    || rabbitmqctl change_password "${RMQ_USER}" "${RMQ_PASS}"
rabbitmqctl set_user_tags "${RMQ_USER}" administrator
rabbitmqctl set_permissions -p "/" "${RMQ_USER}" ".*" ".*" ".*"
success "Admin user '${RMQ_USER}' ready"

info "Waiting for Management API on port 15672 ..."
for i in $(seq 1 20); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${RMQ_USER}:${RMQ_PASS}" \
        http://localhost:15672/api/overview 2>/dev/null || echo "000")
    [[ "${CODE}" == "200" ]] && { success "Management API ready ✅"; break; }
    echo -n "  waiting ... ${i}/20"$'\r'
    sleep 3
done
echo ""

success "PHASE 2 COMPLETE — RabbitMQ ready"

# =============================================================================
# PHASE 3 — INSTALL GO + BUILD EXPORTER FROM SOURCE
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PHASE 3 — Install Go & Build Exporter from Source${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Updating apt ..."
apt-get update -qq

info "Installing Go and Git ..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq golang git
success "Go installed: $(go version)"

export HOME=/root
export GOPATH="${GOPATH_DIR}"
export PATH="${PATH}:/usr/local/go/bin:${GOPATH_DIR}/bin"

info "Cloning rabbitmq_exporter source ..."
mkdir -p "${GOPATH_DIR}/src/github.com/kbudde"
cd "${GOPATH_DIR}/src/github.com/kbudde"
git clone --depth=1 https://github.com/kbudde/rabbitmq_exporter.git \
    || error "Git clone failed — check internet"
cd rabbitmq_exporter
success "Source cloned"

info "Downloading Go dependencies ..."
go mod download
success "Dependencies ready"

info "Building binary (this takes ~2 minutes) ..."
go build -o "${EXPORTER_BINARY}" .
success "Build complete"

info "Setting permissions ..."
chmod 755 "${EXPORTER_BINARY}"
chown root:root "${EXPORTER_BINARY}"

info "Binary details:"
ls -la "${EXPORTER_BINARY}"
file "${EXPORTER_BINARY}"
echo ""

info "Testing binary ..."
"${EXPORTER_BINARY}" --help > /dev/null 2>&1
EXIT_CODE=$?
if [[ ${EXIT_CODE} -le 1 ]]; then
    success "Binary runs correctly ✅"
else
    "${EXPORTER_BINARY}" 2>&1 | head -5
    error "Binary cannot run — exit code ${EXIT_CODE}"
fi

success "PHASE 3 COMPLETE — Binary built and ready"

# =============================================================================
# PHASE 4 — CREATE SYSTEMD SERVICE
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PHASE 4 — Create Systemd Service${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Writing systemd service file ..."
cat > /etc/systemd/system/rabbitmq_exporter.service << EOF
[Unit]
Description=RabbitMQ Prometheus Exporter
Documentation=https://github.com/kbudde/rabbitmq_exporter
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

info "Reloading systemd ..."
systemctl daemon-reload

info "Enabling service ..."
systemctl enable rabbitmq_exporter

info "Starting service ..."
systemctl start rabbitmq_exporter
sleep 6

info "Service status:"
systemctl status rabbitmq_exporter --no-pager -l | head -10
echo ""

systemctl is-active --quiet rabbitmq_exporter \
    && success "PHASE 4 COMPLETE — Service running ✅" \
    || { journalctl -u rabbitmq_exporter -n 20 --no-pager; error "Service failed"; }

# =============================================================================
# PHASE 5 — LOCAL TESTS
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PHASE 5 — Local Tests${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PASS=0; FAIL=0

check() {
    local NAME="$1" CMD="$2" EXPECT="$3" OUT
    OUT=$(eval "${CMD}" 2>&1 || true)
    if echo "${OUT}" | grep -q "${EXPECT}"; then
        echo -e "  ${GREEN}✔${NC}  ${NAME}"; PASS=$((PASS+1))
    else
        echo -e "  ${RED}✘${NC}  ${NAME}"
        echo -e "       Got : $(echo "${OUT}" | head -1)"
        FAIL=$((FAIL+1))
    fi
}

echo -e "  ${BOLD}── Services ──────────────────────────────────────────────${NC}"
check "rabbitmq-server active"    "systemctl is-active rabbitmq-server"    "active"
check "rabbitmq_exporter active"  "systemctl is-active rabbitmq_exporter"  "active"

echo ""
echo -e "  ${BOLD}── Ports ─────────────────────────────────────────────────${NC}"
check "AMQP       5672  open"     "ss -tlnp | grep ':5672'"                "5672"
check "Management 15672 open"     "ss -tlnp | grep ':15672'"               "15672"
check "Exporter   9419  open"     "ss -tlnp | grep ':9419'"                "9419"

echo ""
echo -e "  ${BOLD}── API & Metrics ─────────────────────────────────────────${NC}"
check "Management API health"     "curl -sf -u ${RMQ_USER}:${RMQ_PASS} http://localhost:15672/api/healthchecks/node" "ok"
check "Exporter /metrics working" "curl -sf http://localhost:${EXPORTER_PORT}/metrics"                               "rabbitmq_"
check "Queue metrics present"     "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue"         "rabbitmq_queue"
check "Node  metrics present"     "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"          "rabbitmq_node"
check "Up    metric  present"     "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_up"            "rabbitmq_up"

MCOUNT=$(curl -sf "http://localhost:${EXPORTER_PORT}/metrics" \
    | grep -v "^#" | wc -l 2>/dev/null || echo "0")

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
echo -e "  Passed : ${GREEN}${BOLD}${PASS}${NC}   Failed : ${RED}${BOLD}${FAIL}${NC}   Total metrics : ${GREEN}${BOLD}${MCOUNT}${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"

# =============================================================================
# FINAL SUMMARY
# =============================================================================
IP=$(hostname -I | awk '{print $1}')
echo ""
if [[ ${FAIL} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║      ALL DONE — RabbitMQ Exporter Ready  🐇             ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}${BOLD}║      COMPLETED WITH ISSUES — Check above                ║${NC}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "  ${BOLD}Access URLs:${NC}"
echo -e "    Exporter    →  http://${IP}:${EXPORTER_PORT}/metrics"
echo -e "    Mgmt UI     →  http://${IP}:15672"
echo -e "    Login       →  ${RMQ_USER} / ${RMQ_PASS}"
echo -e "    Metrics     →  ${MCOUNT} total"
echo ""
echo -e "  ${BOLD}Quick test commands:${NC}"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep -v '^#' | wc -l"
echo ""
echo -e "  ${BOLD}Service commands:${NC}"
echo -e "    systemctl status  rabbitmq_exporter"
echo -e "    systemctl restart rabbitmq_exporter"
echo -e "    journalctl -u rabbitmq_exporter -f"
echo ""
