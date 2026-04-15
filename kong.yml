cat > ~/kong-setup.sh << 'SCRIPT'
#!/bin/bash

echo "================================================"
echo "   Kong Gateway - Full Setup Script"
echo "================================================"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

VM_IP=$(hostname -I | awk '{print $1}')
echo -e "${YELLOW}VM IP: $VM_IP${NC}"

mkdir -p ~/kong-ansible && cd ~/kong-ansible

# ─── Inventory ───
cat > inventory.ini << 'EOF'
[local]
localhost ansible_connection=local
EOF

# ─── Playbook ───
cat > install-kong.yml << 'EOF'
---
- name: Install Kong Gateway OSS
  hosts: local
  become: yes

  vars:
    kong_version: "3.6.1"

  tasks:

    - name: Install dependencies
      apt:
        name:
          - curl
          - wget
          - gnupg
          - apt-transport-https
          - lsb-release
          - unzip
          - perl
        state: present
        update_cache: yes

    - name: Download Kong .deb package
      get_url:
        url: "https://packages.konghq.com/public/gateway-36/deb/ubuntu/pool/focal/main/k/ko/kong_3.6.1/kong_3.6.1_amd64.deb"
        dest: /tmp/kong.deb
        timeout: 120

    - name: Install Kong package
      apt:
        deb: /tmp/kong.deb
        state: present

    - name: Create Kong config directory
      file:
        path: /etc/kong
        state: directory
        mode: '0755'

    - name: Configure Kong (DB-less mode for testing)
      copy:
        dest: /etc/kong/kong.conf
        content: |
          # Kong Configuration - DB-less mode (no database needed)
          database = off
          declarative_config = /etc/kong/kong.yml

          # Proxy settings
          proxy_listen = 0.0.0.0:8000, 0.0.0.0:8443 ssl
          admin_listen = 0.0.0.0:8001, 0.0.0.0:8444 ssl

          # Logging
          log_level = info
          proxy_access_log = /var/log/kong/access.log
          proxy_error_log = /var/log/kong/error.log
          admin_access_log = /var/log/kong/admin_access.log
          admin_error_log = /var/log/kong/admin_error.log

    - name: Create Kong declarative config
      copy:
        dest: /etc/kong/kong.yml
        content: |
          _format_version: "3.0"
          _transform: true

          services:
            - name: example-service
              url: https://httpbin.org
              routes:
                - name: example-route
                  paths:
                    - /test

    - name: Create Kong log directory
      file:
        path: /var/log/kong
        state: directory
        owner: kong
        group: kong
        mode: '0755'
      ignore_errors: yes

    - name: Create log directory (fallback)
      file:
        path: /var/log/kong
        state: directory
        mode: '0777'

    - name: Run Kong migrations (DB-less skips this)
      shell: kong check /etc/kong/kong.conf
      register: kong_check
      ignore_errors: yes

    - name: Show Kong check result
      debug:
        msg: "{{ kong_check.stdout }}"
      ignore_errors: yes

    - name: Create Kong systemd service
      copy:
        dest: /etc/systemd/system/kong.service
        content: |
          [Unit]
          Description=Kong Gateway
          After=network.target

          [Service]
          Type=forking
          PIDFile=/usr/local/kong/pids/nginx.pid
          ExecStartPre=/usr/local/bin/kong prepare -p /usr/local/kong
          ExecStart=/usr/local/bin/kong start -c /etc/kong/kong.conf
          ExecReload=/usr/local/bin/kong reload -c /etc/kong/kong.conf
          ExecStop=/usr/local/bin/kong stop
          Restart=on-failure
          RestartSec=5s

          [Install]
          WantedBy=multi-user.target

    - name: Reload systemd
      systemd:
        daemon_reload: yes

    - name: Start Kong
      systemd:
        name: kong
        state: started
        enabled: yes

    - name: Wait for Kong Admin API
      wait_for:
        port: 8001
        host: 0.0.0.0
        delay: 5
        timeout: 60

    - name: Verify Kong is running
      uri:
        url: http://127.0.0.1:8001
        method: GET
        status_code: 200
      register: kong_status

    - name: Show Kong version info
      debug:
        msg: "{{ kong_status.json.version }}"
      ignore_errors: yes

    - name: Show access info
      debug:
        msg:
          - "✅ Kong Gateway is UP!"
          - "Admin API:  http://{{ ansible_default_ipv4.address }}:8001"
          - "Proxy:      http://{{ ansible_default_ipv4.address }}:8000"
          - "Test route: http://{{ ansible_default_ipv4.address }}:8000/test"
EOF

echo -e "${YELLOW}[Running Ansible Playbook...]${NC}"
ansible-playbook -i inventory.ini install-kong.yml

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   ✅ KONG GATEWAY SETUP COMPLETE!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}Access Kong from your HOST browser:${NC}"
echo ""
echo -e "  🔧 Admin API:   ${GREEN}http://$VM_IP:8001${NC}"
echo -e "  🌐 Proxy:       ${GREEN}http://$VM_IP:8000${NC}"
echo -e "  📊 Status:      ${GREEN}http://$VM_IP:8001/status${NC}"
echo -e "  🛣️  Routes:      ${GREEN}http://$VM_IP:8001/routes${NC}"
echo -e "  🔌 Services:    ${GREEN}http://$VM_IP:8001/services${NC}"
echo -e "  🔑 Plugins:     ${GREEN}http://$VM_IP:8001/plugins${NC}"
echo ""
echo -e "${YELLOW}Test the example route:${NC}"
echo -e "  curl http://$VM_IP:8000/test"
echo ""
echo -e "${GREEN}================================================${NC}"

SCRIPT

chmod +x ~/kong-setup.sh
bash ~/kong-setup.sh
