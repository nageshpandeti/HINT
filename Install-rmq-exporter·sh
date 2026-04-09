#!/bin/bash
# =============================================================================
#  RabbitMQ Exporter - Install & Test Script
#  Target OS  : Ubuntu 22.04 LTS (VirtualBox)
#  Includes   : RabbitMQ + Management Plugin + kbudde exporter (port 9419)
#  NO Prometheus required
# =============================================================================
set -euo pipefail

# ── Colours ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Config ──────────────────────────────────────────────────────────────────
RMQ_USER="admin"
RMQ_PASS="admin123"
RMQ_VHOST="/"
EXPORTER_VERSION="1.0.0"
EXPORTER_PORT="9419"
EXPORTER_BINARY="/usr/local/bin/rabbitmq_exporter"
EXPORTER_SERVICE="/etc/systemd/system/rabbitmq_exporter.service"

# ── Root check ──────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || error "Please run as root:  sudo bash $0"

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   RabbitMQ + Exporter Installer  (Ubuntu 22.04) ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# =============================================================================
# STEP 1 – System packages
# =============================================================================
info "Updating package index …"
apt-get update -qq

info "Installing prerequisites …"
apt-get install -y -qq \
    curl wget gnupg apt-transport-https \
    ca-certificates lsb-release software-properties-common

# =============================================================================
# STEP 2 – Erlang
# =============================================================================
info "Adding Erlang repository …"
curl -fsSL https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc \
    | gpg --dearmor -o /usr/share/keyrings/erlang-solutions.gpg

echo "deb [signed-by=/usr/share/keyrings/erlang-solutions.gpg] \
https://packages.erlang-solutions.com/ubuntu jammy contrib" \
    > /etc/apt/sources.list.d/erlang.list

apt-get update -qq
info "Installing Erlang …"
apt-get install -y -qq erlang
success "Erlang installed"

# =============================================================================
# STEP 3 – RabbitMQ Server
# =============================================================================
info "Adding RabbitMQ repository …"
curl -fsSL https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey \
    | gpg --dearmor -o /usr/share/keyrings/rabbitmq-archive-keyring.gpg

cat > /etc/apt/sources.list.d/rabbitmq.list <<EOF
deb [signed-by=/usr/share/keyrings/rabbitmq-archive-keyring.gpg] \
https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/ jammy main
EOF

apt-get update -qq
info "Installing RabbitMQ …"
apt-get install -y -qq rabbitmq-server

systemctl enable --now rabbitmq-server
sleep 3
systemctl is-active rabbitmq-server \
    && success "RabbitMQ is running" \
    || error "RabbitMQ failed to start — check: journalctl -u rabbitmq-server -n 30"

# =============================================================================
# STEP 4 – Enable Management Plugin (required by exporter)
# =============================================================================
info "Enabling rabbitmq_management plugin …"
rabbitmq-plugins enable rabbitmq_management
success "Management plugin enabled  →  port 15672"

# =============================================================================
# STEP 5 – Create admin user
# =============================================================================
info "Setting up admin user '${RMQ_USER}' …"
rabbitmqctl delete_user guest 2>/dev/null || true
rabbitmqctl add_user "${RMQ_USER}" "${RMQ_PASS}" 2>/dev/null \
    || rabbitmqctl change_password "${RMQ_USER}" "${RMQ_PASS}"
rabbitmqctl set_user_tags "${RMQ_USER}" administrator
rabbitmqctl set_permissions -p "${RMQ_VHOST}" "${RMQ_USER}" ".*" ".*" ".*"
success "User '${RMQ_USER}' created with administrator role"

# Wait for management API
info "Waiting for management API to be ready …"
for i in {1..20}; do
    curl -s -u "${RMQ_USER}:${RMQ_PASS}" \
        http://localhost:15672/api/overview > /dev/null 2>&1 && break
    sleep 2
done

# =============================================================================
# STEP 6 – Download kbudde rabbitmq_exporter binary
# =============================================================================
info "Downloading rabbitmq_exporter v${EXPORTER_VERSION} …"
TARBALL="rabbitmq_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz"
URL="https://github.com/kbudde/rabbitmq_exporter/releases/download/v${EXPORTER_VERSION}/${TARBALL}"

cd /tmp
wget -q --show-progress "${URL}" -O "${TARBALL}" \
    || error "Download failed. Check: https://github.com/kbudde/rabbitmq_exporter/releases"

EXTRACTED=$(tar -tzf "${TARBALL}" | head -1 | cut -d/ -f1)
tar -xzf "${TARBALL}"
install -m 755 "${EXTRACTED}/rabbitmq_exporter" "${EXPORTER_BINARY}"
rm -rf "${TARBALL}" "${EXTRACTED}"
success "Binary installed at ${EXPORTER_BINARY}"

# =============================================================================
# STEP 7 – Systemd service
# =============================================================================
info "Creating systemd service …"
useradd --system --no-create-home --shell /bin/false rabbitmq_exporter 2>/dev/null || true

cat > "${EXPORTER_SERVICE}" <<EOF
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
systemctl enable --now rabbitmq_exporter
sleep 3
systemctl is-active rabbitmq_exporter \
    && success "rabbitmq_exporter service is running" \
    || error "Service failed — check: journalctl -u rabbitmq_exporter -n 30"

# =============================================================================
# STEP 8 – Firewall (ufw)
# =============================================================================
if ufw status 2>/dev/null | grep -q "Status: active"; then
    info "Opening ports in ufw …"
    ufw allow 5672/tcp  comment "RabbitMQ AMQP"      > /dev/null
    ufw allow 15672/tcp comment "RabbitMQ Management" > /dev/null
    ufw allow 9419/tcp  comment "RMQ Exporter"        > /dev/null
    success "Firewall ports opened: 5672, 15672, 9419"
else
    warn "ufw not active — skipping firewall"
fi

# =============================================================================
# STEP 9 – Tests (no Prometheus needed)
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  RUNNING LOCAL TESTS (curl only)${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"

PASS=0; FAIL=0

check() {
    local name="$1"; local cmd="$2"; local expect="$3"
    local out
    out=$(eval "$cmd" 2>&1 || true)
    if echo "$out" | grep -q "${expect}"; then
        echo -e "  ${GREEN}✔${NC}  ${name}"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✘${NC}  ${name}"
        echo -e "      expected : '${expect}'"
        echo -e "      got      : $(echo "$out" | head -2)"
        FAIL=$((FAIL+1))
    fi
}

echo ""
echo -e "  ${BOLD}RabbitMQ Core${NC}"
check "AMQP port 5672 listening" \
    "ss -tlnp | grep 5672" "5672"

check "Management API health" \
    "curl -s -u ${RMQ_USER}:${RMQ_PASS} http://localhost:15672/api/healthchecks/node" \
    "ok"

check "Management UI HTTP 200" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:15672" "200"

echo ""
echo -e "  ${BOLD}RabbitMQ Exporter (port ${EXPORTER_PORT})${NC}"
check "Exporter /metrics endpoint reachable" \
    "curl -s http://localhost:${EXPORTER_PORT}/metrics" \
    "rabbitmq_"

check "Exporter exposes queue metrics" \
    "curl -s http://localhost:${EXPORTER_PORT}/metrics | grep -m1 rabbitmq_queue" \
    "rabbitmq_queue"

check "Exporter exposes node metrics" \
    "curl -s http://localhost:${EXPORTER_PORT}/metrics | grep -m1 rabbitmq_node" \
    "rabbitmq_node"

check "Exporter exposes overview metrics" \
    "curl -s http://localhost:${EXPORTER_PORT}/metrics | grep -m1 rabbitmq_overview" \
    "rabbitmq_overview"

echo ""
echo -e "  ${BOLD}Services${NC}"
check "rabbitmq-server service active" \
    "systemctl is-active rabbitmq-server" "active"

check "rabbitmq_exporter service active" \
    "systemctl is-active rabbitmq_exporter" "active"

# Results
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "  Passed : ${GREEN}${BOLD}${PASS}${NC}   Failed : ${RED}${BOLD}${FAIL}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"

# =============================================================================
# STEP 10 – Summary
# =============================================================================
IP=$(hostname -I | awk '{print $1}')
METRIC_COUNT=$(curl -s "http://localhost:${EXPORTER_PORT}/metrics" 2>/dev/null \
    | grep -v "^#" | wc -l || echo "?")

echo ""
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║       INSTALLATION COMPLETE  🐇                 ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  RabbitMQ Management UI"
echo -e "    URL      →  http://${IP}:15672"
echo -e "    Login    →  ${RMQ_USER} / ${RMQ_PASS}"
echo ""
echo -e "  RabbitMQ Exporter"
echo -e "    Metrics  →  http://${IP}:${EXPORTER_PORT}/metrics"
echo -e "    Total metrics exposed: ${METRIC_COUNT}"
echo ""
echo -e "  Quick test commands:"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep -c ''"
echo ""
echo -e "  Service commands:"
echo -e "    systemctl status rabbitmq_exporter"
echo -e "    journalctl -u rabbitmq_exporter -f"
echo -e "    systemctl restart rabbitmq_exporter"
echo ""
info "When ready to add Prometheus, point it at:  ${IP}:${EXPORTER_PORT}"
