#!/bin/bash
# =============================================================================
#  RabbitMQ Exporter — All In One Setup
#  Phases  : Uninstall → RabbitMQ Fix → Install Go 1.22.3 → Build → Service → Test
#  Usage   : sudo bash rmq_allinone.sh
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

RMQ_USER="admin"
RMQ_PASS="admin123"
EXPORTER_PORT="9419"
EXPORTER_BINARY="/usr/local/bin/rabbitmq_exporter"
GO_VERSION="1.22.3"
GOPATH_DIR="/root/go"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   RabbitMQ Exporter — All In One Setup                  ║${NC}"
echo -e "${BOLD}║   Go ${GO_VERSION} + Build from Source + Systemd + Tests   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  OS     : $(lsb_release -ds 2>/dev/null)"
echo -e "  Kernel : $(uname -r)"
echo -e "  Arch   : $(uname -m)"
echo ""

# =============================================================================
# PHASE 1 — UNINSTALL
# =============================================================================
echo -e "${BOLD}${CYAN}━━━  PHASE 1 — Uninstall Old Exporter  ━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
systemctl stop    rabbitmq_exporter 2>/dev/null || true
systemctl disable rabbitmq_exporter 2>/dev/null || true
rm -f /etc/systemd/system/rabbitmq_exporter.service
rm -f "${EXPORTER_BINARY}"
rm -rf "${GOPATH_DIR}/src/github.com/kbudde"
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true
success "Old exporter removed"

# =============================================================================
# PHASE 2 — RABBITMQ CHECK
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  PHASE 2 — Verify RabbitMQ  ━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

systemctl is-active --quiet rabbitmq-server || systemctl start rabbitmq-server
sleep 3
systemctl is-active --quiet rabbitmq-server \
    && success "RabbitMQ running" \
    || error "RabbitMQ not running"

rabbitmq-plugins enable rabbitmq_management > /dev/null 2>&1
systemctl restart rabbitmq-server
sleep 6

rabbitmqctl delete_user guest 2>/dev/null || true
rabbitmqctl add_user "${RMQ_USER}" "${RMQ_PASS}" 2>/dev/null \
    || rabbitmqctl change_password "${RMQ_USER}" "${RMQ_PASS}"
rabbitmqctl set_user_tags "${RMQ_USER}" administrator
rabbitmqctl set_permissions -p "/" "${RMQ_USER}" ".*" ".*" ".*"
success "Admin user ready"

info "Waiting for Management API ..."
for i in $(seq 1 20); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${RMQ_USER}:${RMQ_PASS}" \
        http://localhost:15672/api/overview 2>/dev/null || echo "000")
    [[ "${CODE}" == "200" ]] && { success "Management API ready ✅"; break; }
    sleep 3
done

# =============================================================================
# PHASE 3 — INSTALL LATEST GO
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  PHASE 3 — Install Go ${GO_VERSION}  ━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Remove old Go
apt-get remove -y -qq golang golang-go 2>/dev/null || true
rm -rf /usr/local/go

# Detect arch
[[ "$(uname -m)" == "x86_64" ]] && GO_ARCH="amd64" || GO_ARCH="arm64"

GO_TARBALL="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"

info "Downloading Go ${GO_VERSION} ..."
wget -q --show-progress -O "/tmp/${GO_TARBALL}" "${GO_URL}" \
    || error "Go download failed"

info "Installing Go ..."
tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
rm -f "/tmp/${GO_TARBALL}"

export PATH="/usr/local/go/bin:${PATH}"
export GOPATH="${GOPATH_DIR}"
export HOME=/root

success "Go installed: $(go version)"

# =============================================================================
# PHASE 4 — BUILD EXPORTER
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  PHASE 4 — Build Exporter from Source  ━━━━━━━━━━━━━━━${NC}"
echo ""

apt-get install -y -qq git

mkdir -p "${GOPATH_DIR}/src/github.com/kbudde"
cd "${GOPATH_DIR}/src/github.com/kbudde"
rm -rf rabbitmq_exporter

info "Cloning source ..."
git clone --depth=1 https://github.com/kbudde/rabbitmq_exporter.git \
    || error "Clone failed"
cd rabbitmq_exporter
success "Cloned"

info "Downloading dependencies ..."
go mod download
success "Dependencies ready"

info "Building binary (~2 minutes) ..."
go build -o "${EXPORTER_BINARY}" .

[[ -f "${EXPORTER_BINARY}" ]] \
    && success "Binary built ✅" \
    || error "Build failed — binary not created"

chmod 755 "${EXPORTER_BINARY}"
chown root:root "${EXPORTER_BINARY}"

info "Binary:"
ls -la "${EXPORTER_BINARY}"
file "${EXPORTER_BINARY}"

info "Testing binary ..."
"${EXPORTER_BINARY}" --help > /dev/null 2>&1
[[ $? -le 1 ]] && success "Binary works ✅" || error "Binary cannot run"

# =============================================================================
# PHASE 5 — SYSTEMD SERVICE
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  PHASE 5 — Systemd Service  ━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

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
sleep 6

systemctl status rabbitmq_exporter --no-pager | head -8
echo ""

systemctl is-active --quiet rabbitmq_exporter \
    && success "Service running ✅" \
    || { journalctl -u rabbitmq_exporter -n 20 --no-pager; error "Service failed"; }

# =============================================================================
# PHASE 6 — TESTS
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━  PHASE 6 — Local Tests  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PASS=0; FAIL=0
check() {
    local NAME="$1" CMD="$2" EXPECT="$3" OUT
    OUT=$(eval "${CMD}" 2>&1 || true)
    if echo "${OUT}" | grep -q "${EXPECT}"; then
        echo -e "  ${GREEN}✔${NC}  ${NAME}"; PASS=$((PASS+1))
    else
        echo -e "  ${RED}✘${NC}  ${NAME}"; echo -e "       Got : $(echo "${OUT}" | head -1)"; FAIL=$((FAIL+1))
    fi
}

echo -e "  ${BOLD}── Services ──${NC}"
check "rabbitmq-server active"    "systemctl is-active rabbitmq-server"   "active"
check "rabbitmq_exporter active"  "systemctl is-active rabbitmq_exporter" "active"

echo ""
echo -e "  ${BOLD}── Ports ──${NC}"
check "Port 5672  open"  "ss -tlnp | grep ':5672'"  "5672"
check "Port 15672 open"  "ss -tlnp | grep ':15672'" "15672"
check "Port 9419  open"  "ss -tlnp | grep ':9419'"  "9419"

echo ""
echo -e "  ${BOLD}── Metrics ──${NC}"
check "Management API health"     "curl -sf -u ${RMQ_USER}:${RMQ_PASS} http://localhost:15672/api/healthchecks/node" "ok"
check "Exporter /metrics working" "curl -sf http://localhost:${EXPORTER_PORT}/metrics"                               "rabbitmq_"
check "Queue metrics present"     "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue"         "rabbitmq_queue"
check "Node  metrics present"     "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"          "rabbitmq_node"
check "Up    metric  present"     "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_up"            "rabbitmq_up"

MCOUNT=$(curl -sf "http://localhost:${EXPORTER_PORT}/metrics" | grep -v "^#" | wc -l 2>/dev/null || echo "0")
IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
echo -e "  Passed : ${GREEN}${BOLD}${PASS}${NC}   Failed : ${RED}${BOLD}${FAIL}${NC}   Metrics : ${GREEN}${BOLD}${MCOUNT}${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"

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
echo -e "  Exporter  →  http://${IP}:${EXPORTER_PORT}/metrics"
echo -e "  Mgmt UI   →  http://${IP}:15672   (${RMQ_USER} / ${RMQ_PASS})"
echo -e "  Metrics   →  ${MCOUNT} total"
echo ""
echo -e "  ${BOLD}Test commands:${NC}"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep -v '^#' | wc -l"
echo ""
echo -e "  ${BOLD}Service commands:${NC}"
echo -e "    systemctl status  rabbitmq_exporter"
echo -e "    journalctl -u rabbitmq_exporter -f"
echo ""
