---
# =============================================================================
#  Ansible Playbook — RabbitMQ Exporter (Uninstall + Install + Test)
#  Target  : Ubuntu 22.04
#  File    : rmq_exporter_full.yml
#
#  Usage:
#    # Full run (uninstall + install + test)
#    ansible-playbook rmq_exporter_full.yml -i inventory.ini -K
#
#    # Only uninstall
#    ansible-playbook rmq_exporter_full.yml -i inventory.ini -K --tags uninstall
#
#    # Only install
#    ansible-playbook rmq_exporter_full.yml -i inventory.ini -K --tags install
#
#    # Only test
#    ansible-playbook rmq_exporter_full.yml -i inventory.ini -K --tags test
# =============================================================================

# =============================================================================
#  PLAY 1 — UNINSTALL
# =============================================================================
- name: "PLAY 1 — Uninstall RabbitMQ Exporter"
  hosts: all
  become: true
  tags: uninstall

  tasks:

    - name: "[UNINSTALL] Show start message"
      debug:
        msg:
          - "=============================================="
          - "  Uninstalling RabbitMQ Exporter ..."
          - "=============================================="

    - name: "[UNINSTALL] Stop rabbitmq_exporter service"
      systemd:
        name:  rabbitmq_exporter
        state: stopped
      ignore_errors: true

    - name: "[UNINSTALL] Disable rabbitmq_exporter service"
      systemd:
        name:    rabbitmq_exporter
        enabled: false
      ignore_errors: true

    - name: "[UNINSTALL] Remove systemd service file"
      file:
        path:  /etc/systemd/system/rabbitmq_exporter.service
        state: absent

    - name: "[UNINSTALL] Reload systemd daemon"
      systemd:
        daemon_reload: true

    - name: "[UNINSTALL] Reset failed units"
      shell: systemctl reset-failed 2>/dev/null || true
      changed_when: false

    - name: "[UNINSTALL] Remove exporter binary"
      file:
        path:  /usr/local/bin/rabbitmq_exporter
        state: absent

    - name: "[UNINSTALL] Remove system user rabbitmq_exporter"
      user:
        name:   rabbitmq_exporter
        state:  absent
        remove: true
      ignore_errors: true

    - name: "[UNINSTALL] Verify — service file removed"
      stat:
        path: /etc/systemd/system/rabbitmq_exporter.service
      register: svc_file

    - name: "[UNINSTALL] Verify — binary removed"
      stat:
        path: /usr/local/bin/rabbitmq_exporter
      register: bin_file

    - name: "[UNINSTALL] Verify — user removed"
      shell: id rabbitmq_exporter 2>/dev/null || echo "user not found"
      register: user_check
      changed_when: false

    - name: "[UNINSTALL] Summary"
      debug:
        msg:
          - "=============================================="
          - "  Uninstall Verification"
          - "=============================================="
          - "  Service file  : {{ 'EXISTS ❌' if svc_file.stat.exists else 'Removed ✅' }}"
          - "  Binary        : {{ 'EXISTS ❌' if bin_file.stat.exists else 'Removed ✅' }}"
          - "  System user   : {{ 'EXISTS ❌' if 'uid=' in user_check.stdout else 'Removed ✅' }}"
          - "=============================================="
          - "  RabbitMQ itself is NOT touched"
          - "=============================================="


# =============================================================================
#  PLAY 2 — INSTALL
# =============================================================================
- name: "PLAY 2 — Install RabbitMQ Exporter"
  hosts: all
  become: true
  tags: install

  vars:
    rmq_user:              "admin"
    rmq_pass:              "admin123"
    rmq_url:               "http://localhost:15672"
    exporter_version:      "0.29.0"
    exporter_port:         "9419"
    exporter_binary:       "/usr/local/bin/rabbitmq_exporter"
    exporter_user:         "rabbitmq_exporter"
    exporter_tarball:      "rabbitmq_exporter-{{ exporter_version }}.linux-amd64.tar.gz"
    exporter_download_url: "https://github.com/kbudde/rabbitmq_exporter/releases/download/v{{ exporter_version }}/{{ exporter_tarball }}"
    exporter_extract_dir:  "/tmp/rabbitmq_exporter-{{ exporter_version }}.linux-amd64"

  tasks:

    - name: "[INSTALL] Show start message"
      debug:
        msg:
          - "=============================================="
          - "  Installing RabbitMQ Exporter v{{ exporter_version }} ..."
          - "=============================================="

    # ── Prerequisites ─────────────────────────────────────────────────────
    - name: "[INSTALL] Update apt cache"
      apt:
        update_cache: true
        cache_valid_time: 3600

    - name: "[INSTALL] Install required packages"
      apt:
        name:
          - curl
          - wget
        state: present

    # ── Verify RabbitMQ ───────────────────────────────────────────────────
    - name: "[INSTALL] Check RabbitMQ service is running"
      shell: systemctl is-active rabbitmq-server
      register: rmq_check
      changed_when: false
      failed_when:  rmq_check.stdout != "active"

    - name: "[INSTALL] RabbitMQ status"
      debug:
        msg: "RabbitMQ is {{ rmq_check.stdout }} ✅"

    # ── System user ───────────────────────────────────────────────────────
    - name: "[INSTALL] Create rabbitmq_exporter system user"
      user:
        name:        "{{ exporter_user }}"
        system:      true
        shell:       /bin/false
        create_home: false
        comment:     "RabbitMQ Exporter Service User"
        state:       present

    # ── Download ──────────────────────────────────────────────────────────
    - name: "[INSTALL] Download rabbitmq_exporter v{{ exporter_version }}"
      get_url:
        url:     "{{ exporter_download_url }}"
        dest:    "/tmp/{{ exporter_tarball }}"
        mode:    "0644"
        timeout: 60

    # ── Extract & Install ─────────────────────────────────────────────────
    - name: "[INSTALL] Extract tarball"
      unarchive:
        src:        "/tmp/{{ exporter_tarball }}"
        dest:       "/tmp/"
        remote_src: true

    - name: "[INSTALL] Install binary to {{ exporter_binary }}"
      copy:
        src:        "{{ exporter_extract_dir }}/rabbitmq_exporter"
        dest:       "{{ exporter_binary }}"
        owner:      root
        group:      root
        mode:       "0755"
        remote_src: true

    # ── Cleanup ───────────────────────────────────────────────────────────
    - name: "[INSTALL] Remove temp files"
      file:
        path:  "{{ item }}"
        state: absent
      loop:
        - "/tmp/{{ exporter_tarball }}"
        - "{{ exporter_extract_dir }}"

    # ── Systemd service ───────────────────────────────────────────────────
    - name: "[INSTALL] Create systemd service file"
      copy:
        dest:  /etc/systemd/system/rabbitmq_exporter.service
        owner: root
        group: root
        mode:  "0644"
        content: |
          [Unit]
          Description=RabbitMQ Prometheus Exporter v{{ exporter_version }}
          Documentation=https://github.com/kbudde/rabbitmq_exporter
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

    - name: "[INSTALL] Reload systemd daemon"
      systemd:
        daemon_reload: true

    - name: "[INSTALL] Enable and start rabbitmq_exporter"
      systemd:
        name:    rabbitmq_exporter
        state:   started
        enabled: true

    - name: "[INSTALL] Wait for exporter port {{ exporter_port }} to be ready"
      wait_for:
        host:    localhost
        port:    "{{ exporter_port }}"
        timeout: 30

    # ── Firewall ──────────────────────────────────────────────────────────
    - name: "[INSTALL] Allow exporter port {{ exporter_port }} in ufw"
      ufw:
        rule:    allow
        port:    "{{ exporter_port }}"
        proto:   tcp
        comment: "RabbitMQ Exporter"
      ignore_errors: true


# =============================================================================
#  PLAY 3 — TEST
# =============================================================================
- name: "PLAY 3 — Test RabbitMQ Exporter"
  hosts: all
  become: true
  tags: test

  vars:
    rmq_user:     "admin"
    rmq_pass:     "admin123"
    exporter_port: "9419"

  tasks:

    - name: "[TEST] Show start message"
      debug:
        msg:
          - "=============================================="
          - "  Running Tests ..."
          - "=============================================="

    - name: "[TEST 1] rabbitmq-server service is active"
      shell: systemctl is-active rabbitmq-server
      register: t1
      changed_when: false
      failed_when:  t1.stdout != "active"

    - name: "[TEST 1] Result"
      debug:
        msg: "rabbitmq-server is {{ t1.stdout }} ✅"

    - name: "[TEST 2] rabbitmq_exporter service is active"
      shell: systemctl is-active rabbitmq_exporter
      register: t2
      changed_when: false
      failed_when:  t2.stdout != "active"

    - name: "[TEST 2] Result"
      debug:
        msg: "rabbitmq_exporter is {{ t2.stdout }} ✅"

    - name: "[TEST 3] AMQP port 5672 is listening"
      wait_for:
        host:    localhost
        port:    5672
        timeout: 10

    - name: "[TEST 3] Result"
      debug:
        msg: "Port 5672 is listening ✅"

    - name: "[TEST 4] Management port 15672 is listening"
      wait_for:
        host:    localhost
        port:    15672
        timeout: 10

    - name: "[TEST 4] Result"
      debug:
        msg: "Port 15672 is listening ✅"

    - name: "[TEST 5] Exporter port 9419 is listening"
      wait_for:
        host:    localhost
        port:    "{{ exporter_port }}"
        timeout: 10

    - name: "[TEST 5] Result"
      debug:
        msg: "Port {{ exporter_port }} is listening ✅"

    - name: "[TEST 6] Management API health check"
      uri:
        url:              "http://localhost:15672/api/healthchecks/node"
        user:             "{{ rmq_user }}"
        password:         "{{ rmq_pass }}"
        force_basic_auth: true
        status_code:      200
      register: t6

    - name: "[TEST 6] Result"
      debug:
        msg: "Management API health → {{ t6.status }} ✅"

    - name: "[TEST 7] Exporter /metrics endpoint reachable"
      uri:
        url:            "http://localhost:{{ exporter_port }}/metrics"
        return_content: true
        status_code:    200
      register: metrics_out

    - name: "[TEST 7] Result"
      debug:
        msg: "Exporter /metrics returned HTTP {{ metrics_out.status }} ✅"

    - name: "[TEST 8] Queue metrics present in output"
      assert:
        that:        "'rabbitmq_queue' in metrics_out.content"
        success_msg: "Queue metrics found ✅"
        fail_msg:    "Queue metrics NOT found ❌"

    - name: "[TEST 9] Node metrics present in output"
      assert:
        that:        "'rabbitmq_node' in metrics_out.content"
        success_msg: "Node metrics found ✅"
        fail_msg:    "Node metrics NOT found ❌"

    - name: "[TEST 10] RabbitMQ up metric present"
      assert:
        that:        "'rabbitmq_up' in metrics_out.content"
        success_msg: "rabbitmq_up metric found ✅"
        fail_msg:    "rabbitmq_up metric NOT found ❌"

    - name: "Count total metrics exposed"
      shell: "curl -s http://localhost:{{ exporter_port }}/metrics | grep -v '^#' | wc -l"
      register: metric_count
      changed_when: false

    # ── Final Summary ─────────────────────────────────────────────────────
    - name: "Final Summary"
      debug:
        msg:
          - "================================================"
          - "  RabbitMQ Exporter — All Tests Passed 🐇"
          - "================================================"
          - "  Exporter metrics  : http://{{ ansible_host }}:{{ exporter_port }}/metrics"
          - "  Management UI     : http://{{ ansible_host }}:15672"
          - "  Login             : {{ rmq_user }} / {{ rmq_pass }}"
          - "  Total metrics     : {{ metric_count.stdout }}"
          - "  Service status    : systemctl status rabbitmq_exporter"
          - "  Live logs         : journalctl -u rabbitmq_exporter -f"
          - "================================================"
