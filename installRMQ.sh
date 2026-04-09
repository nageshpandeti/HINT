#!/bin/bash
# =============================================================================
#  RabbitMQ + Exporter Installer — Ubuntu 22.04
#  Version : 4.0
#  Fixes   : Broken packages, Erlang version conflict, RabbitMQ install failure
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
echo -e "${BOLD}║   RabbitMQ + Exporter Installer  (Ubuntu 22.04) ║${NC}"
echo -e "${BOLD}║   Version 4.0  — Full Fix                        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

RMQ_USER="admin"
RMQ_PASS="admin123"
EXPORTER_VERSION="1.0.0"
EXPORTER_PORT="9419"
EXPORTER_BINARY="/usr/local/bin/rabbitmq_exporter"

# =============================================================================
# STEP 1 — Full cleanup of any previous broken install
# =============================================================================
info "Cleaning up previous broken installs …"

systemctl stop rabbitmq-server    2>/dev/null || true
systemctl stop rabbitmq_exporter  2>/dev/null || true

# Remove broken RabbitMQ
apt-get remove  --purge -y -qq rabbitmq-server 2>/dev/null || true
apt-get autoremove -y -qq 2>/dev/null || true

# Remove ALL old repo files that may conflict
rm -f /etc/apt/sources.list.d/erlang.list
rm -f /etc/apt/sources.list.d/rabbitmq.list
rm -f /usr/share/keyrings/erlang-solutions.gpg
rm -f /usr/share/keyrings/rabbitmq-archive-keyring.gpg

# Fix any held/broken packages
apt-get install -f -y -qq 2>/dev/null || true
dpkg --configure -a 2>/dev/null || true

apt-get update -qq
success "Cleanup done"

# =============================================================================
# STEP 2 — Prerequisites
# =============================================================================
info "Installing prerequisites …"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl wget gnupg apt-transport-https \
    ca-certificates lsb-release socat logrotate
success "Prerequisites installed"

# =============================================================================
# STEP 3 — Install Erlang 25 from RabbitMQ's own Erlang repo
#           (matches RabbitMQ 3.12.x perfectly on Ubuntu 22.04)
# =============================================================================
info "Adding RabbitMQ team Erlang repository (Launchpad) …"

curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xf77f15818fc4d36e2d9c4f2ada7d7e6dcc1c0b11" \
    | gpg --dearmor \
    | tee /usr/share/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg > /dev/null

cat > /etc/apt/sources.list.d/rabbitmq-erlang.list <<'EOF'
## Provides RabbitMQ-compatible Erlang 25.x for Ubuntu 22.04 (jammy)
deb [arch=amd64 signed-by=/usr/share/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg] https://ppa1.rabbitmq.com/rabbitmq/rabbitmq-erlang/deb/ubuntu jammy main
deb-src [signed-by=/usr/share/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg] https://ppa1.rabbitmq.com/rabbitmq/rabbitmq-erlang/deb/ubuntu jammy main
EOF

apt-get update -qq

info "Installing Erlang 25 (RabbitMQ-compatible) …"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    erlang-base \
    erlang-asn1 \
    erlang-crypto \
    erlang-eldap \
    erlang-ftp \
    erlang-inets \
    erlang-mnesia \
    erlang-os-mon \
    erlang-parsetools \
    erlang-public-key \
    erlang-runtime-tools \
    erlang-snmp \
    erlang-ssl \
    erlang-syntax-tools \
    erlang-tftp \
    erlang-tools \
    erlang-xmerl

success "Erlang installed: $(erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().' 2>/dev/null || echo 'ok')"

# =============================================================================
# STEP 4 — RabbitMQ Server from official repo
# =============================================================================
info "Adding RabbitMQ Server repository …"

curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x0a9af2115f4687bd29803a206b73a36e6026dfca" \
    | gpg --dearmor \
    | tee /usr/share/keyrings/com.github.rabbitmq.signing.gpg > /dev/null

cat > /etc/apt/sources.list.d/rabbitmq.list <<'EOF'
## RabbitMQ Server for Ubuntu 22.04 (jammy)
deb [arch=amd64 signed-by=/usr/share/keyrings/com.github.rabbitmq.signing.gpg] https://ppa1.rabbitmq.com/rabbitmq/rabbitmq-server/deb/ubuntu jammy main
deb-src [signed-by=/usr/share/keyrings/com.github.rabbitmq.signing.gpg] https://ppa1.rabbitmq.com/rabbitmq/rabbitmq-server/deb/ubuntu jammy main
EOF

apt-get update -qq

info "Installing RabbitMQ Server …"
DEBIAN_FRONTEND=noninteractive apt-get install -y rabbitmq-server

success "RabbitMQ Server installed"

# =============================================================================
# STEP 5 — Start RabbitMQ
# =============================================================================
info "Enabling and starting RabbitMQ …"
systemctl daemon-reload
systemctl enable rabbitmq-server
systemctl start  rabbitmq-server
sleep 5

if systemctl is-active --quiet rabbitmq-server; then
    success "RabbitMQ is running  ✓"
else
    journalctl -u rabbitmq-server -n 20 --no-pager
    error "RabbitMQ failed to start — see logs above"
fi

# =============================================================================
# STEP 6 — Enable Management Plugin
# =============================================================================
info "Enabling management plugin …"
rabbitmq-plugins enable rabbitmq_management
success "Management plugin active on port 15672"

# =============================================================================
# STEP 7 — Create admin user
# =============================================================================
info "Creating admin user …"
rabbitmqctl delete_user guest 2>/dev/null || true
rabbitmqctl add_user "${RMQ_USER}" "${RMQ_PASS}" 2>/dev/null \
    || rabbitmqctl change_password "${RMQ_USER}" "${RMQ_PASS}"
rabbitmqctl set_user_tags "${RMQ_USER}" administrator
rabbitmqctl set_permissions -p "/" "${RMQ_USER}" ".*" ".*" ".*"
success "User '${RMQ_USER}' ready"

info "Waiting for Management API …"
for i in $(seq 1 20); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${RMQ_USER}:${RMQ_PASS}" \
        http://localhost:15672/api/overview 2>/dev/null || echo "000")
    [[ "${CODE}" == "200" ]] && { success "Management API ready"; break; }
    sleep 2
done

# =============================================================================
# STEP 8 — Download kbudde rabbitmq_exporter
# =============================================================================
info "Downloading rabbitmq_exporter v${EXPORTER_VERSION} …"

TARBALL="rabbitmq_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz"
URL="https://github.com/kbudde/rabbitmq_exporter/releases/download/v${EXPORTER_VERSION}/${TARBALL}"

cd /tmp
rm -f "${TARBALL}"
wget --progress=bar:force --timeout=60 -O "${TARBALL}" "${URL}" \
    || error "Download failed — check internet connectivity"

EXTRACTED_DIR=$(tar -tzf "${TARBALL}" | head -1 | cut -d/ -f1)
tar -xzf "${TARBALL}"
install -m 755 "${EXTRACTED_DIR}/rabbitmq_exporter" "${EXPORTER_BINARY}"
rm -rf "/tmp/${TARBALL}" "/tmp/${EXTRACTED_DIR}"
success "Exporter binary installed → ${EXPORTER_BINARY}"

# =============================================================================
# STEP 9 — Systemd service
# =============================================================================
info "Creating systemd service …"
useradd --system --no-create-home --shell /bin/false rabbitmq_exporter 2>/dev/null || true

cat > /etc/systemd/system/rabbitmq_exporter.service <<EOF
[Unit]
Description=RabbitMQ Prometheus Exporter
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
    success "rabbitmq_exporter service running  ✓"
else
    journalctl -u rabbitmq_exporter -n 20 --no-pager
    error "Exporter failed — see logs above"
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
fi

# =============================================================================
# STEP 11 — Tests
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
check "AMQP       5672 listening"  "ss -tlnp | grep ':5672'"  "5672"
check "Management 15672 listening" "ss -tlnp | grep ':15672'" "15672"
check "Exporter   9419 listening"  "ss -tlnp | grep ':9419'"  "9419"

echo ""
echo -e "  ${BOLD}── Metrics ───────────────────────────────────────${NC}"
check "Management API /healthchecks/node" \
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
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed${NC} : ${BOLD}${PASS}${NC}   ${RED}Failed${NC} : ${BOLD}${FAIL}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# =============================================================================
# STEP 12 — Summary
# =============================================================================
IP=$(hostname -I | awk '{print $1}')
MCOUNT=$(curl -sf "http://localhost:${EXPORTER_PORT}/metrics" \
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
echo -e "    Total metrics : ${MCOUNT}"
echo ""
echo -e "  ${BOLD}Quick test commands:${NC}"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep -v '^#' | wc -l"
echo ""
echo -e "  ${BOLD}Service logs:${NC}"
echo -e "    journalctl -u rabbitmq_exporter -f"
echo -e "    journalctl -u rabbitmq-server -f"
echo ""
