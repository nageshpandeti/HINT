cat > ~/fluentbit-setup.sh << 'SCRIPT'
#!/bin/bash

echo "================================================"
echo "   Fluent Bit - Full Setup Script"
echo "================================================"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get VM IP
VM_IP=$(hostname -I | awk '{print $1}')
echo -e "${YELLOW}VM IP: $VM_IP${NC}"

# ─── STEP 1: Create Ansible Directory ───
echo -e "\n${YELLOW}[1/5] Creating project directory...${NC}"
mkdir -p ~/fluentbit-ansible && cd ~/fluentbit-ansible

# ─── STEP 2: Create Inventory ───
echo -e "${YELLOW}[2/5] Creating inventory...${NC}"
cat > inventory.ini << 'EOF'
[local]
localhost ansible_connection=local
EOF

# ─── STEP 3: Create Playbook ───
echo -e "${YELLOW}[3/5] Creating Ansible playbook...${NC}"
cat > install-fluentbit.yml << 'EOF'
---
- name: Install and Configure Fluent Bit
  hosts: local
  become: yes

  tasks:

    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install dependencies
      apt:
        name:
          - curl
          - gnupg
          - apt-transport-https
        state: present

    - name: Add Fluent Bit GPG key
      shell: |
        curl https://packages.fluentbit.io/fluentbit.key | gpg --dearmor -o /usr/share/keyrings/fluentbit-keyring.gpg
      args:
        creates: /usr/share/keyrings/fluentbit-keyring.gpg

    - name: Get Ubuntu codename
      command: lsb_release -cs
      register: ubuntu_codename

    - name: Add Fluent Bit repository
      apt_repository:
        repo: "deb [signed-by=/usr/share/keyrings/fluentbit-keyring.gpg] https://packages.fluentbit.io/ubuntu/{{ ubuntu_codename.stdout }} {{ ubuntu_codename.stdout }} main"
        state: present
        filename: fluent-bit

    - name: Install Fluent Bit
      apt:
        name: fluent-bit
        state: present
        update_cache: yes

    - name: Configure Fluent Bit
      copy:
        dest: /etc/fluent-bit/fluent-bit.conf
        content: |
          [SERVICE]
              Flush         1
              Daemon        Off
              Log_Level     info
              HTTP_Server   On
              HTTP_Listen   0.0.0.0
              HTTP_Port     2020

          [INPUT]
              Name          cpu
              Tag           cpu.metrics
              Interval_Sec  1

          [INPUT]
              Name          mem
              Tag           mem.metrics
              Interval_Sec  1

          [INPUT]
              Name          disk
              Tag           disk.metrics
              Interval_Sec  5

          [INPUT]
              Name          netif
              Tag           net.metrics
              Interface     eth0
              Interval_Sec  5

          [OUTPUT]
              Name          stdout
              Match         *

    - name: Start and enable Fluent Bit
      systemd:
        name: fluent-bit
        state: restarted
        enabled: yes
        daemon_reload: yes

    - name: Wait for Fluent Bit HTTP server
      wait_for:
        port: 2020
        host: 0.0.0.0
        delay: 3
        timeout: 30

    - name: Verify Fluent Bit health
      uri:
        url: http://127.0.0.1:2020/api/v1/health
        method: GET
        status_code: 200
      register: health

    - name: Show result
      debug:
        msg:
          - "✅ Fluent Bit is UP and HEALTHY!"
          - "Status: {{ health.status }}"
EOF

# ─── STEP 4: Run Playbook ───
echo -e "${YELLOW}[4/5] Running Ansible playbook...${NC}"
ansible-playbook -i inventory.ini install-fluentbit.yml

# ─── STEP 5: Show Access Info ───
echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}   ✅ FLUENT BIT SETUP COMPLETE!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Access Fluent Bit from your HOST browser:${NC}"
echo ""
echo -e "  🌐 Main:     ${GREEN}http://$VM_IP:2020${NC}"
echo -e "  ❤️  Health:   ${GREEN}http://$VM_IP:2020/api/v1/health${NC}"
echo -e "  📊 Metrics:  ${GREEN}http://$VM_IP:2020/api/v1/metrics${NC}"
echo -e "  ⏱️  Uptime:   ${GREEN}http://$VM_IP:2020/api/v1/uptime${NC}"
echo -e "  🔌 Plugins:  ${GREEN}http://$VM_IP:2020/api/v1/plugins${NC}"
echo ""
echo -e "${YELLOW}Check status inside VM:${NC}"
echo -e "  sudo systemctl status fluent-bit"
echo -e "  sudo journalctl -u fluent-bit -f"
echo ""
echo -e "${GREEN}================================================${NC}"

SCRIPT

chmod +x ~/fluentbit-setup.sh
bash ~/fluentbit-setup.sh
