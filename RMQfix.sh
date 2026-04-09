#!/bin/bash
# =============================================================================
#  RabbitMQ Exporter — Install via Go (bypasses binary compatibility issues)
#  Usage : sudo bash rmq_go_install.sh
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

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   RabbitMQ Exporter — Install via Go Build          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# STEP 1 — System info
# =============================================================================
info "System info:"
echo "  OS     : $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
echo "  Kernel : $(uname -r)"
echo "  Arch   : $(uname -m)"
echo "  Bits   : $(getconf LONG_BIT)"
echo ""

# =============================================================================
# STEP 2 — Stop old service
# =============================================================================
info "Stopping old service ..."
systemctl stop rabbitmq_exporter 2>/dev/null || true
rm -f "${EXPORTER_BINARY}"
success "Cleaned"

# =============================================================================
# STEP 3 — Install Go
# =============================================================================
info "Installing Go ..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq golang git
success "Go installed: $(go version)"

# =============================================================================
# STEP 4 — Build rabbitmq_exporter from source
# =============================================================================
info "Building rabbitmq_exporter from source ..."

export HOME=/root
export GOPATH=/root/go
export PATH=$PATH:/usr/local/go/bin

mkdir -p "${GOPATH}/src/github.com/kbudde"
cd "${GOPATH}/src/github.com/kbudde"

# Clone source
rm -rf rabbitmq_exporter
git clone --depth=1 https://github.com/kbudde/rabbitmq_exporter.git
cd rabbitmq_exporter

info "Downloading Go dependencies ..."
go mod download

info "Building binary (this takes 1-2 minutes) ..."
go build -o "${EXPORTER_BINARY}" .

success "Build complete"

# =============================================================================
# STEP 5 — Verify binary
# =============================================================================
info "Verifying binary ..."
ls -la "${EXPORTER_BINARY}"
file "${EXPORTER_BINARY}"
chmod 755 "${EXPORTER_BINARY}"

info "Testing binary ..."
"${EXPORTER_BINARY}" --help > /dev/null 2>&1
EXIT_CODE=$?
[[ ${EXIT_CODE} -le 1 ]] \
    && success "Binary works ✅" \
    || error "Binary still failing (exit ${EXIT_CODE})"

# =============================================================================
# STEP 6 — Systemd service
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

systemctl is-active --quiet rabbitmq_exporter \
    && success "rabbitmq_exporter service running ✅" \
    || { journalctl -u rabbitmq_exporter -n 20 --no-pager; error "Service failed"; }

# =============================================================================
# STEP 7 — Tests
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
        echo -e "  ${RED}✘${NC}  ${NAME}"; echo -e "       Got: $(echo "${OUT}" | head -1)"; FAIL=$((FAIL+1))
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

MCOUNT=$(curl -sf "http://localhost:${EXPORTER_PORT}/metrics" | grep -v "^#" | wc -l 2>/dev/null || echo "0")
IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "  Passed : ${GREEN}${BOLD}${PASS}${NC}   Failed : ${RED}${BOLD}${FAIL}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

if [[ ${FAIL} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   ALL DONE — RabbitMQ Exporter Ready  🐇            ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║   STILL ISSUES — Share output above                 ║${NC}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "  Management UI  →  http://${IP}:15672   (${RMQ_USER} / ${RMQ_PASS})"
echo -e "  Exporter       →  http://${IP}:${EXPORTER_PORT}/metrics"
echo -e "  Total metrics  →  ${MCOUNT}"
echo ""
