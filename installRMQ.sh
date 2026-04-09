#!/bin/bash
# =============================================================================
#  RabbitMQ + Exporter Installer — Ubuntu 22.04
#  Version : 3.0 (Fixed - No erlang-solutions repo)
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

# ── Root check ─────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Please run as root:  sudo bash $0"
fi

# ── Config ──────────────────────────────────────────────────────────────────
RMQ_USER="admin"
RMQ_PASS="admin123"
EXPORTER_VERSION="1.0.0"
EXPORTER_PORT="9419"
EXPORTER_BINARY="/usr/local/bin/rabbitmq_exporter"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   RabbitMQ + Exporter Installer  (Ubuntu 22.04) ║${NC}"
echo -e "${BOLD}║   Version 3.0  — No erlang-solutions repo        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# STEP 1 — Clean up any old/broken erlang-solutions repo entries
# =============================================================================
info "Cleaning up any old Erlang repo entries …"
rm -f /etc/apt/sources.list.d/erlang.list
rm -f /usr/share/keyrings/erlang-solutions.gpg
apt-get update -qq 2>/dev/null || true
success "Old repo entries removed"

# =============================================================================
# STEP 2 — System update & prerequisites
# =============================================================================
info "Updating package index …"
apt-get update -qq

info "Installing prerequisites …"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl \
    wget \
    gnupg \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    software-properties-common
success "Prerequisites installed"

# =============================================================================
# STEP 3 — Erlang via Ubuntu universe (NO external repo needed)
# =============================================================================
info "Enabling Ubuntu universe repository …"
add-apt-repository -y universe > /dev/null 2>&1 || true
apt-get update -qq

info "Installing Erlang from Ubuntu universe …"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq erlang
success "Erlang installed: $(erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().' 2>/dev/null || echo 'ok')"

# =============================================================================
# STEP 4 — RabbitMQ Server
# =============================================================================
info "Adding RabbitMQ GPG key …"
curl -fsSL https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey \
    | gpg --dearmor \
    | tee /usr/share/keyrings/rabbitmq-archive-keyring.gpg > /dev/null
success "GPG key saved"

info "Adding RabbitMQ repository …"
cat > /etc/apt/sources.list.d/rabbitmq.list <<EOF
deb [signed-by=/usr/share/keyrings/rabbitmq-archive-keyring.gpg] https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/ jammy main
EOF

apt-get update -qq

info "Installing RabbitMQ Server …"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rabbitmq-server
success "RabbitMQ Server installed"

info "Starting RabbitMQ service …"
systemctl enable rabbitmq-server > /dev/null 2>&1
systemctl start  rabbitmq-server
sleep 5

if systemctl is-active --quiet rabbitmq-server; then
    success "RabbitMQ is running"
else
    error "RabbitMQ failed to start — run: journalctl -u rabbitmq-server -n 50"
fi

# =============================================================================
# STEP 5 — Enable Management Plugin
# =============================================================================
info "Enabling rabbitmq_management plugin …"
rabbitmq-plugins enable rabbitmq_management > /dev/null 2>&1
success "Management plugin enabled on port 15672"

# =============================================================================
# STEP 6 — Create admin user
# =============================================================================
info "Creating admin user '${RMQ_USER}' …"
rabbitmqctl delete_user guest 2>/dev/null || true
rabbitmqctl add_user "${RMQ_USER}" "${RMQ_PASS}" 2>/dev/null \
    || rabbitmqctl change_password "${RMQ_USER}" "${RMQ_PASS}"
rabbitmqctl set_user_tags "${RMQ_USER}" administrator
rabbitmqctl set_permissions -p "/" "${RMQ_USER}" ".*" ".*" ".*"
success "User '${RMQ_USER}' created with administrator role"

info "Waiting for Management API to be ready …"
for i in $(seq 1 20); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${RMQ_USER}:${RMQ_PASS}" \
        http://localhost:15672/api/overview 2>/dev/null || echo "000")
    if [[ "${HTTP_CODE}" == "200" ]]; then
        success "Management API is ready"
        break
    fi
    sleep 2
done

# =============================================================================
# STEP 7 — Download kbudde rabbitmq_exporter
# =============================================================================
info "Downloading rabbitmq_exporter v${EXPORTER_VERSION} …"

TARBALL="rabbitmq_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz"
DOWNLOAD_URL="https://github.com/kbudde/rabbitmq_exporter/releases/download/v${EXPORTER_VERSION}/${TARBALL}"

cd /tmp
rm -f "${TARBALL}"

wget --progress=bar:force \
     --timeout=60 \
     -O "${TARBALL}" \
     "${DOWNLOAD_URL}" 2>&1 || error "Download failed — check internet connectivity"

info "Extracting binary …"
EXTRACTED_DIR=$(tar -tzf "${TARBALL}" | head -1 | cut -d/ -f1)
tar -xzf "${TARBALL}"
install -m 755 "${EXTRACTED_DIR}/rabbitmq_exporter" "${EXPORTER_BINARY}"
rm -rf "/tmp/${TARBALL}" "/tmp/${EXTRACTED_DIR}"
success "Binary installed at ${EXPORTER_BINARY}"

# =============================================================================
# STEP 8 — Create dedicated system user
# =============================================================================
info "Creating system user for exporter …"
if ! id rabbitmq_exporter &>/dev/null; then
    useradd --system --no-create-home --shell /bin/false rabbitmq_exporter
fi
success "System user 'rabbitmq_exporter' ready"

# =============================================================================
# STEP 9 — Systemd service
# =============================================================================
info "Creating systemd service …"
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

systemctl daemon-reload
systemctl enable rabbitmq_exporter > /dev/null 2>&1
systemctl start  rabbitmq_exporter
sleep 3

if systemctl is-active --quiet rabbitmq_exporter; then
    success "rabbitmq_exporter service is running"
else
    error "Exporter failed — run: journalctl -u rabbitmq_exporter -n 30"
fi

# =============================================================================
# STEP 10 — Firewall
# =============================================================================
if ufw status 2>/dev/null | grep -q "Status: active"; then
    info "Opening firewall ports …"
    ufw allow 5672/tcp  > /dev/null 2>&1
    ufw allow 15672/tcp > /dev/null 2>&1
    ufw allow 9419/tcp  > /dev/null 2>&1
    success "Ports opened: 5672, 15672, 9419"
else
    warn "ufw not active — skipping firewall rules"
fi

# =============================================================================
# STEP 11 — Local Tests
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  RUNNING LOCAL TESTS (no Prometheus needed)      ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

PASS=0
FAIL=0

check() {
    local NAME="$1"
    local CMD="$2"
    local EXPECT="$3"
    local OUT
    OUT=$(eval "${CMD}" 2>&1 || true)
    if echo "${OUT}" | grep -q "${EXPECT}"; then
        echo -e "  ${GREEN}✔${NC}  ${NAME}"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✘${NC}  ${NAME}"
        echo -e "       Expected : '${EXPECT}'"
        echo -e "       Got      : $(echo "${OUT}" | head -1)"
        FAIL=$((FAIL + 1))
    fi
}

echo -e "  ${BOLD}── Services ────────────────────────────────────${NC}"
check "rabbitmq-server is active" \
    "systemctl is-active rabbitmq-server" \
    "active"

check "rabbitmq_exporter is active" \
    "systemctl is-active rabbitmq_exporter" \
    "active"

echo ""
echo -e "  ${BOLD}── Ports ───────────────────────────────────────${NC}"
check "AMQP port 5672 listening" \
    "ss -tlnp | grep ':5672'" \
    "5672"

check "Management port 15672 listening" \
    "ss -tlnp | grep ':15672'" \
    "15672"

check "Exporter port 9419 listening" \
    "ss -tlnp | grep ':9419'" \
    "9419"

echo ""
echo -e "  ${BOLD}── API & Metrics ────────────────────────────────${NC}"
check "Management API health OK" \
    "curl -sf -u ${RMQ_USER}:${RMQ_PASS} http://localhost:15672/api/healthchecks/node" \
    "ok"

check "Exporter /metrics endpoint reachable" \
    "curl -sf http://localhost:${EXPORTER_PORT}/metrics" \
    "rabbitmq_"

check "Queue metrics present" \
    "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep -m1 'rabbitmq_queue'" \
    "rabbitmq_queue"

check "Node metrics present" \
    "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep -m1 'rabbitmq_node'" \
    "rabbitmq_node"

check "Overview metrics present" \
    "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep -m1 'rabbitmq_overview'" \
    "rabbitmq_overview"

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed${NC} : ${BOLD}${PASS}${NC}   ${RED}Failed${NC} : ${BOLD}${FAIL}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# =============================================================================
# STEP 12 — Final Summary
# =============================================================================
IP=$(hostname -I | awk '{print $1}')
METRIC_COUNT=$(curl -sf "http://localhost:${EXPORTER_PORT}/metrics" \
    | grep -v "^#" | wc -l 2>/dev/null || echo "?")

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║         INSTALLATION COMPLETE  🐇               ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}RabbitMQ Management UI${NC}"
echo -e "    URL   →  http://${IP}:15672"
echo -e "    Login →  ${RMQ_USER} / ${RMQ_PASS}"
echo ""
echo -e "  ${BOLD}RabbitMQ Exporter${NC}"
echo -e "    URL   →  http://${IP}:${EXPORTER_PORT}/metrics"
echo -e "    Total metrics exposed : ${METRIC_COUNT}"
echo ""
echo -e "  ${BOLD}Test commands (run any time):${NC}"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep -v '^#' | wc -l"
echo ""
echo -e "  ${BOLD}Service management:${NC}"
echo -e "    systemctl status  rabbitmq_exporter"
echo -e "    systemctl restart rabbitmq_exporter"
echo -e "    journalctl -u rabbitmq_exporter -f"
echo ""
info "To add Prometheus later → scrape  ${IP}:${EXPORTER_PORT}"
echo ""
