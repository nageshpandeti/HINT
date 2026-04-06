#!/bin/bash

# =============================================================
#  End-to-End Script: Install Ansible + HashiCorp Vault
#  OS: Ubuntu 22.04 (Jammy)
#  Usage: chmod +x setup_vault.sh && sudo ./setup_vault.sh
# =============================================================

set -e  # Exit immediately on any error

# ── Colors for output ─────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Must run as root ──────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  error "Please run as root: sudo ./setup_vault.sh"
fi

# =============================================================
# STEP 1: Update System
# =============================================================
log "Step 1: Updating system packages..."
apt-get update -y
apt-get upgrade -y
log "System updated."

# =============================================================
# STEP 2: Install Ansible
# =============================================================
log "Step 2: Installing Ansible..."
apt-get install -y software-properties-common curl gnupg wget unzip
add-apt-repository --yes --update ppa:ansible/ansible
apt-get install -y ansible
log "Ansible installed: $(ansible --version | head -1)"

# =============================================================
# STEP 3: Write Ansible Inventory
# =============================================================
log "Step 3: Creating Ansible inventory..."
mkdir -p /opt/vault-ansible

cat > /opt/vault-ansible/inventory.ini <<'EOF'
[vault_servers]
localhost ansible_connection=local
EOF

log "Inventory created at /opt/vault-ansible/inventory.ini"

# =============================================================
# STEP 4: Write Ansible Playbook
# =============================================================
log "Step 4: Creating Ansible playbook..."

cat > /opt/vault-ansible/install_vault.yml <<'EOF'
---
- name: Download and Install HashiCorp Vault on Ubuntu 22.04
  hosts: vault_servers
  become: yes

  vars:
    vault_config_dir: "/etc/vault.d"
    vault_data_dir: "/var/vault/data"

  tasks:

    # ── Dependencies ────────────────────────────────────────
    - name: Install required packages
      ansible.builtin.apt:
        name:
          - curl
          - gnupg
          - wget
          - unzip
          - software-properties-common
        state: present
        update_cache: yes

    # ── Download HashiCorp GPG key via URL ──────────────────
    - name: Download HashiCorp GPG key from URL
      ansible.builtin.get_url:
        url: https://apt.releases.hashicorp.com/gpg
        dest: /tmp/hashicorp.gpg
        mode: '0644'

    - name: Add HashiCorp GPG key to trusted keyring
      ansible.builtin.shell: |
        gpg --dearmor < /tmp/hashicorp.gpg > /usr/share/keyrings/hashicorp-archive-keyring.gpg
      args:
        creates: /usr/share/keyrings/hashicorp-archive-keyring.gpg

    # ── Add HashiCorp APT Repository via URL ────────────────
    - name: Add HashiCorp APT repository
      ansible.builtin.apt_repository:
        repo: "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com jammy main"
        filename: hashicorp
        state: present

    - name: Update APT cache after adding repo
      ansible.builtin.apt:
        update_cache: yes

    # ── Install Vault ────────────────────────────────────────
    - name: Install HashiCorp Vault
      ansible.builtin.apt:
        name: vault
        state: present

    # ── Create directories ───────────────────────────────────
    - name: Create Vault config directory
      ansible.builtin.file:
        path: "{{ vault_config_dir }}"
        state: directory
        owner: vault
        group: vault
        mode: '0755'

    - name: Create Vault data directory
      ansible.builtin.file:
        path: "{{ vault_data_dir }}"
        state: directory
        owner: vault
        group: vault
        mode: '0750'

    # ── Write Vault config ───────────────────────────────────
    - name: Deploy Vault configuration
      ansible.builtin.copy:
        dest: "{{ vault_config_dir }}/vault.hcl"
        owner: vault
        group: vault
        mode: '0640'
        content: |
          ui            = true
          disable_mlock = true

          storage "file" {
            path = "{{ vault_data_dir }}"
          }

          listener "tcp" {
            address     = "0.0.0.0:8200"
            tls_disable = true
          }

    # ── Enable & Start Vault service ─────────────────────────
    - name: Enable and start Vault service
      ansible.builtin.systemd:
        name: vault
        enabled: yes
        state: started
        daemon_reload: yes

    # ── Verify ───────────────────────────────────────────────
    - name: Get Vault version
      ansible.builtin.command: vault version
      register: vault_ver
      changed_when: false

    - name: Show Vault version
      ansible.builtin.debug:
        msg: "{{ vault_ver.stdout }}"

    - name: Check Vault service status
      ansible.builtin.command: systemctl is-active vault
      register: vault_svc
      changed_when: false

    - name: Show Vault service status
      ansible.builtin.debug:
        msg: "Vault service is [ {{ vault_svc.stdout }} ]"
EOF

log "Playbook created at /opt/vault-ansible/install_vault.yml"

# =============================================================
# STEP 5: Run the Ansible Playbook
# =============================================================
log "Step 5: Running Ansible playbook to install Vault..."
cd /opt/vault-ansible
ansible-playbook -i inventory.ini install_vault.yml

# =============================================================
# STEP 6: Final Verification
# =============================================================
log "Step 6: Final verification..."

export VAULT_ADDR='http://127.0.0.1:8200'

sleep 2  # Give service a moment to settle

VAULT_STATUS=$(systemctl is-active vault 2>/dev/null || echo "inactive")

echo ""
echo "=============================================="
echo -e "  ${GREEN}HashiCorp Vault Installation Complete!${NC}"
echo "=============================================="
echo ""
echo -e "  Vault Version   : $(vault version)"
echo -e "  Service Status  : ${GREEN}${VAULT_STATUS}${NC}"
echo -e "  Vault UI        : http://127.0.0.1:8200/ui"
echo -e "  Config File     : /etc/vault.d/vault.hcl"
echo -e "  Data Directory  : /var/vault/data"
echo ""
echo "=============================================="
echo "  NEXT STEPS - Initialize Vault (run once):"
echo "=============================================="
echo ""
echo "  export VAULT_ADDR='http://127.0.0.1:8200'"
echo "  vault operator init"
echo ""
echo "  --> Save the 5 Unseal Keys & Root Token!"
echo ""
echo "  vault operator unseal  # run 3 times"
echo "  vault login <Root_Token>"
echo ""
echo "=============================================="
