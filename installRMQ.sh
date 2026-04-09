#!/bin/bash
# =============================================================================
#  RabbitMQ Exporter — Full Setup Script
#  Includes: Uninstall + Install Ansible + Run Ansible Playbook + Test
#  Target  : Ubuntu 22.04
#  Usage   : sudo bash rmq_exporter_setup.sh
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

# ── Config ───────────────────────────────────────────────────────────────────
RMQ_USER="admin"
RMQ_PASS="admin123"
RMQ_URL="http://localhost:15672"
EXPORTER_VERSION="0.29.0"
EXPORTER_PORT="9419"
EXPORTER_BINARY="/usr/local/bin/rabbitmq_exporter"
EXPORTER_USER="rabbitmq_exporter"
WORK_DIR="/tmp/rmq_ansible"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   RabbitMQ Exporter — Full Setup (Ansible)          ║${NC}"
echo -e "${BOLD}║   Uninstall → Install Ansible → Deploy → Test       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# PHASE 1 — UNINSTALL OLD EXPORTER
# =============================================================================
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PHASE 1 — Uninstall Old Exporter${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

info "Stopping rabbitmq_exporter service ..."
systemctl stop rabbitmq_exporter 2>/dev/null && success "Service stopped" || info "Service was not running"

info "Disabling rabbitmq_exporter service ..."
systemctl disable rabbitmq_exporter 2>/dev/null && success "Service disabled" || info "Service was not enabled"

info "Removing systemd service file ..."
rm -f /etc/systemd/system/rabbitmq_exporter.service
success "Service file removed"

info "Reloading systemd ..."
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true
success "Systemd reloaded"

info "Removing exporter binary ..."
rm -f "${EXPORTER_BINARY}"
success "Binary removed"

info "Removing system user ..."
userdel rabbitmq_exporter 2>/dev/null && success "User removed" || info "User did not exist"

echo ""
success "PHASE 1 COMPLETE — Old exporter removed"

# =============================================================================
# PHASE 2 — INSTALL ANSIBLE
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PHASE 2 — Install Ansible${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if command -v ansible-playbook &>/dev/null; then
    success "Ansible already installed: $(ansible --version | head -1)"
else
    info "Updating package index ..."
    apt-get update -qq

    info "Installing Ansible ..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ansible
    success "Ansible installed: $(ansible --version | head -1)"
fi

# =============================================================================
# PHASE 3 — CREATE ANSIBLE FILES
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PHASE 3 — Create Ansible Playbook & Inventory${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

mkdir -p "${WORK_DIR}"

# ── inventory.ini ─────────────────────────────────────────────────────────
info "Creating inventory.ini ..."
cat > "${WORK_DIR}/inventory.ini" << 'EOF'
[all]
localhost ansible_connection=local
EOF
success "inventory.ini created"

# ── playbook.yml ──────────────────────────────────────────────────────────
info "Creating playbook.yml ..."
cat > "${WORK_DIR}/playbook.yml" << PLAYBOOK
---
- name: Install RabbitMQ Exporter
  hosts: all
  become: true

  vars:
    rmq_user:              "${RMQ_USER}"
    rmq_pass:              "${RMQ_PASS}"
    rmq_url:               "${RMQ_URL}"
    exporter_version:      "${EXPORTER_VERSION}"
    exporter_port:         "${EXPORTER_PORT}"
    exporter_binary:       "${EXPORTER_BINARY}"
    exporter_user:         "${EXPORTER_USER}"
    exporter_tarball:      "rabbitmq_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz"
    exporter_download_url: "https://github.com/kbudde/rabbitmq_exporter/releases/download/v${EXPORTER_VERSION}/rabbitmq_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz"
    exporter_extract_dir:  "/tmp/rabbitmq_exporter-${EXPORTER_VERSION}.linux-amd64"

  tasks:

    - name: Install required packages
      apt:
        name: [ curl, wget ]
        state: present
        update_cache: true

    - name: Check RabbitMQ is running
      shell: systemctl is-active rabbitmq-server
      register: rmq_status
      changed_when: false
      failed_when: rmq_status.stdout != "active"

    - name: Show RabbitMQ status
      debug:
        msg: "RabbitMQ is {{ rmq_status.stdout }} ✅"

    - name: Create rabbitmq_exporter system user
      user:
        name:        "{{ exporter_user }}"
        system:      true
        shell:       /bin/false
        create_home: false
        state:       present

    - name: Download rabbitmq_exporter v{{ exporter_version }}
      get_url:
        url:     "{{ exporter_download_url }}"
        dest:    "/tmp/{{ exporter_tarball }}"
        mode:    "0644"
        timeout: 60

    - name: Extract tarball
      unarchive:
        src:        "/tmp/{{ exporter_tarball }}"
        dest:       "/tmp/"
        remote_src: true

    - name: Install binary
      copy:
        src:        "{{ exporter_extract_dir }}/rabbitmq_exporter"
        dest:       "{{ exporter_binary }}"
        owner:      root
        group:      root
        mode:       "0755"
        remote_src: true

    - name: Remove temp files
      file:
        path:  "{{ item }}"
        state: absent
      loop:
        - "/tmp/{{ exporter_tarball }}"
        - "{{ exporter_extract_dir }}"

    - name: Create systemd service file
      copy:
        dest:  /etc/systemd/system/rabbitmq_exporter.service
        owner: root
        group: root
        mode:  "0644"
        content: |
          [Unit]
          Description=RabbitMQ Prometheus Exporter v{{ exporter_version }}
          After=network.target rabbitmq-server.service
          Wants=rabbitmq-server.service

          [Service]
          User={{ exporter_user }}
          Group={{ exporter_user }}
          Type=simple
          Restart=on-failure
          RestartSec=5s
          Environment="RABBIT_URL={{ rmq_url }}"
          Environment="RABBIT_USER={{ rmq_user }}"
          Environment="RABBIT_PASSWORD={{ rmq_pass }}"
          Environment="PUBLISH_PORT={{ exporter_port }}"
          Environment="RABBIT_CAPABILITIES=bert,no_sort"
          Environment="RABBIT_EXPORTERS=exchange,node,overview,queue"
          Environment="OUTPUT_FORMAT=TTY"
          Environment="LOG_LEVEL=info"
          ExecStart={{ exporter_binary }}

          [Install]
          WantedBy=multi-user.target

    - name: Reload systemd
      systemd:
        daemon_reload: true

    - name: Enable and start rabbitmq_exporter
      systemd:
        name:    rabbitmq_exporter
        state:   started
        enabled: true

    - name: Wait for port {{ exporter_port }}
      wait_for:
        host:    localhost
        port:    "{{ exporter_port }}"
        timeout: 30

    - name: Allow port in ufw
      ufw:
        rule:    allow
        port:    "{{ exporter_port }}"
        proto:   tcp
      ignore_errors: true

    - name: "TEST 1 — Service active"
      shell: systemctl is-active rabbitmq_exporter
      register: t1
      changed_when: false
      failed_when:  t1.stdout != "active"

    - name: "TEST 2 — Metrics endpoint"
      uri:
        url:            "http://localhost:{{ exporter_port }}/metrics"
        return_content: true
        status_code:    200
      register: metrics_out

    - name: "TEST 3 — Queue metrics"
      assert:
        that:        "'rabbitmq_queue' in metrics_out.content"
        success_msg: "Queue metrics found ✅"
        fail_msg:    "Queue metrics NOT found ❌"

    - name: "TEST 4 — Node metrics"
      assert:
        that:        "'rabbitmq_node' in metrics_out.content"
        success_msg: "Node metrics found ✅"
        fail_msg:    "Node metrics NOT found ❌"

    - name: "TEST 5 — Management API"
      uri:
        url:              "http://localhost:15672/api/healthchecks/node"
        user:             "{{ rmq_user }}"
        password:         "{{ rmq_pass }}"
        force_basic_auth: true
        status_code:      200

    - name: Count total metrics
      shell: "curl -s http://localhost:{{ exporter_port }}/metrics | grep -v '^#' | wc -l"
      register: metric_count
      changed_when: false

    - name: Final Summary
      debug:
        msg:
          - "================================================"
          - "  RabbitMQ Exporter Ready 🐇"
          - "================================================"
          - "  Metrics URL   : http://{{ ansible_host }}:{{ exporter_port }}/metrics"
          - "  Management UI : http://{{ ansible_host }}:15672"
          - "  Login         : {{ rmq_user }} / {{ rmq_pass }}"
          - "  Total metrics : {{ metric_count.stdout }}"
          - "================================================"
PLAYBOOK

success "playbook.yml created"

# =============================================================================
# PHASE 4 — RUN ANSIBLE PLAYBOOK
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PHASE 4 — Running Ansible Playbook${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cd "${WORK_DIR}"

info "Running ansible-playbook ..."
echo ""

ansible-playbook playbook.yml \
    -i inventory.ini \
    --connection=local \
    -v

ANSIBLE_EXIT=$?

# =============================================================================
# PHASE 5 — FINAL VERIFICATION
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PHASE 5 — Final Verification${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PASS=0; FAIL=0

check() {
    local NAME="$1" CMD="$2" EXPECT="$3" OUT
    OUT=$(eval "${CMD}" 2>&1 || true)
    if echo "${OUT}" | grep -q "${EXPECT}"; then
        echo -e "  ${GREEN}✔${NC}  ${NAME}"; PASS=$((PASS+1))
    else
        echo -e "  ${RED}✘${NC}  ${NAME}"; FAIL=$((FAIL+1))
    fi
}

check "rabbitmq-server active"    "systemctl is-active rabbitmq-server"   "active"
check "rabbitmq_exporter active"  "systemctl is-active rabbitmq_exporter" "active"
check "Port 5672  listening"      "ss -tlnp | grep ':5672'"               "5672"
check "Port 15672 listening"      "ss -tlnp | grep ':15672'"              "15672"
check "Port 9419  listening"      "ss -tlnp | grep ':9419'"               "9419"
check "Metrics endpoint working"  "curl -sf http://localhost:${EXPORTER_PORT}/metrics" "rabbitmq_"
check "Queue metrics present"     "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue" "rabbitmq_queue"
check "Node metrics present"      "curl -sf http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_node"  "rabbitmq_node"

MCOUNT=$(curl -sf "http://localhost:${EXPORTER_PORT}/metrics" | grep -v "^#" | wc -l 2>/dev/null || echo "0")
IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "  Passed : ${GREEN}${BOLD}${PASS}${NC}   Failed : ${RED}${BOLD}${FAIL}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

echo ""
if [[ ${ANSIBLE_EXIT} -eq 0 && ${FAIL} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║      ALL DONE — RabbitMQ Exporter Ready  🐇         ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}${BOLD}║      COMPLETED WITH SOME ISSUES — Check above       ║${NC}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "  Management UI  →  http://${IP}:15672   (${RMQ_USER} / ${RMQ_PASS})"
echo -e "  Exporter       →  http://${IP}:${EXPORTER_PORT}/metrics"
echo -e "  Total metrics  →  ${MCOUNT}"
echo ""
echo -e "  ${BOLD}Useful commands:${NC}"
echo -e "    systemctl status rabbitmq_exporter"
echo -e "    journalctl -u rabbitmq_exporter -f"
echo -e "    curl -s http://localhost:${EXPORTER_PORT}/metrics | grep rabbitmq_queue"
echo ""
