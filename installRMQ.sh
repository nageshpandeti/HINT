---
# =============================================================================
#  Ansible Playbook — RabbitMQ Exporter Install + Test
#  Target  : Ubuntu 22.04 (VirtualBox - localhost)
#  Method  : Install Go 1.22.3 + Build from Source
#  Run     : sudo ansible-playbook rmq_exporter_final.yml
# =============================================================================

- name: RabbitMQ Exporter — Install and Test
  hosts: localhost
  connection: local
  become: true

  vars:
    rmq_user:          "admin"
    rmq_pass:          "admin123"
    rmq_url:           "http://localhost:15672"
    exporter_port:     "9419"
    exporter_binary:   "/usr/local/bin/rabbitmq_exporter"
    go_version:        "1.22.3"
    go_arch:           "amd64"
    gopath_dir:        "/root/go"
    go_install_dir:    "/usr/local"
    src_dir:           "/root/go/src/github.com/kbudde/rabbitmq_exporter"

  tasks:

# =============================================================================
#  BLOCK 1 — UNINSTALL OLD EXPORTER
# =============================================================================

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

    - name: "[UNINSTALL] Remove service file"
      file:
        path:  /etc/systemd/system/rabbitmq_exporter.service
        state: absent

    - name: "[UNINSTALL] Remove binary"
      file:
        path:  "{{ exporter_binary }}"
        state: absent

    - name: "[UNINSTALL] Remove source directory"
      file:
        path:  "{{ src_dir }}"
        state: absent

    - name: "[UNINSTALL] Reload systemd"
      systemd:
        daemon_reload: true

    - name: "[UNINSTALL] Done"
      debug:
        msg: "Old exporter removed ✅"

# =============================================================================
#  BLOCK 2 — VERIFY RABBITMQ
# =============================================================================

    - name: "[RABBITMQ] Check service is active"
      shell: systemctl is-active rabbitmq-server
      register: rmq_check
      changed_when: false
      failed_when:  rmq_check.stdout != "active"

    - name: "[RABBITMQ] Enable management plugin"
      shell: rabbitmq-plugins enable rabbitmq_management
      changed_when: false
      ignore_errors: true

    - name: "[RABBITMQ] Restart RabbitMQ"
      systemd:
        name:  rabbitmq-server
        state: restarted

    - name: "[RABBITMQ] Wait for port 15672"
      wait_for:
        host:    localhost
        port:    15672
        timeout: 60

    - name: "[RABBITMQ] Create admin user"
      shell: |
        rabbitmqctl delete_user guest 2>/dev/null || true
        rabbitmqctl add_user {{ rmq_user }} {{ rmq_pass }} 2>/dev/null \
          || rabbitmqctl change_password {{ rmq_user }} {{ rmq_pass }}
        rabbitmqctl set_user_tags {{ rmq_user }} administrator
        rabbitmqctl set_permissions -p "/" {{ rmq_user }} ".*" ".*" ".*"
      changed_when: false

    - name: "[RABBITMQ] Wait for Management API"
      uri:
        url:              "http://localhost:15672/api/overview"
        user:             "{{ rmq_user }}"
        password:         "{{ rmq_pass }}"
        force_basic_auth: true
        status_code:      200
      register: api_result
      retries:  10
      delay:    5
      until:    api_result.status == 200

    - name: "[RABBITMQ] Management API is ready"
      debug:
        msg: "RabbitMQ Management API is UP ✅"

# =============================================================================
#  BLOCK 3 — INSTALL GO 1.22.3
# =============================================================================

    - name: "[GO] Remove old Go from apt"
      apt:
        name:  "{{ item }}"
        state: absent
      loop:
        - golang
        - golang-go
      ignore_errors: true

    - name: "[GO] Remove old Go directory"
      file:
        path:  /usr/local/go
        state: absent

    - name: "[GO] Install wget and git"
      apt:
        name:
          - wget
          - git
        state:        present
        update_cache: true

    - name: "[GO] Download Go {{ go_version }}"
      get_url:
        url:     "https://go.dev/dl/go{{ go_version }}.linux-{{ go_arch }}.tar.gz"
        dest:    "/tmp/go{{ go_version }}.linux-{{ go_arch }}.tar.gz"
        mode:    "0644"
        timeout: 120

    - name: "[GO] Install Go {{ go_version }}"
      unarchive:
        src:        "/tmp/go{{ go_version }}.linux-{{ go_arch }}.tar.gz"
        dest:       "{{ go_install_dir }}"
        remote_src: true

    - name: "[GO] Remove Go tarball"
      file:
        path:  "/tmp/go{{ go_version }}.linux-{{ go_arch }}.tar.gz"
        state: absent

    - name: "[GO] Verify Go version"
      shell: /usr/local/go/bin/go version
      register: go_ver
      changed_when: false

    - name: "[GO] Go version"
      debug:
        msg: "{{ go_ver.stdout }}"

# =============================================================================
#  BLOCK 4 — BUILD EXPORTER FROM SOURCE
# =============================================================================

    - name: "[BUILD] Create source directory"
      file:
        path:  "/root/go/src/github.com/kbudde"
        state: directory
        mode:  "0755"

    - name: "[BUILD] Clone rabbitmq_exporter"
      git:
        repo:  "https://github.com/kbudde/rabbitmq_exporter.git"
        dest:  "{{ src_dir }}"
        depth: 1
        force: true

    - name: "[BUILD] Download Go dependencies"
      shell: |
        export HOME=/root
        export GOPATH={{ gopath_dir }}
        export PATH=/usr/local/go/bin:$PATH
        cd {{ src_dir }}
        go mod download
      changed_when: false

    - name: "[BUILD] Build binary (~2 minutes)"
      shell: |
        export HOME=/root
        export GOPATH={{ gopath_dir }}
        export PATH=/usr/local/go/bin:$PATH
        cd {{ src_dir }}
        go build -o {{ exporter_binary }} .
      changed_when: false

    - name: "[BUILD] Set binary permissions"
      file:
        path:  "{{ exporter_binary }}"
        owner: root
        group: root
        mode:  "0755"

    - name: "[BUILD] Verify binary exists"
      stat:
        path: "{{ exporter_binary }}"
      register: bin_stat
      failed_when: not bin_stat.stat.exists

    - name: "[BUILD] Test binary runs"
      shell: "{{ exporter_binary }} --help"
      register: bin_test
      changed_when: false
      failed_when:  bin_test.rc > 1

    - name: "[BUILD] Binary is ready"
      debug:
        msg: "Binary built and working ✅"

# =============================================================================
#  BLOCK 5 — SYSTEMD SERVICE
# =============================================================================

    - name: "[SERVICE] Create systemd service file"
      copy:
        dest:  /etc/systemd/system/rabbitmq_exporter.service
        owner: root
        group: root
        mode:  "0644"
        content: |
          [Unit]
          Description=RabbitMQ Prometheus Exporter
          Documentation=https://github.com/kbudde/rabbitmq_exporter
          After=network.target rabbitmq-server.service
          Wants=rabbitmq-server.service

          [Service]
          User=root
          Group=root
          Type=simple
          Restart=on-failure
          RestartSec=10s
          TimeoutStartSec=90

          Environment="RABBIT_URL={{ rmq_url }}"
          Environment="RABBIT_USER={{ rmq_user }}"
          Environment="RABBIT_PASSWORD={{ rmq_pass }}"
          Environment="PUBLISH_PORT={{ exporter_port }}"
          Environment="RABBIT_CAPABILITIES=bert,no_sort"
          Environment="RABBIT_EXPORTERS=exchange,node,overview,queue"
          Environment="OUTPUT_FORMAT=TTY"
          Environment="LOG_LEVEL=info"

          ExecStart={{ exporter_binary }}
          StandardOutput=journal
          StandardError=journal

          [Install]
          WantedBy=multi-user.target

    - name: "[SERVICE] Reload systemd"
      systemd:
        daemon_reload: true

    - name: "[SERVICE] Enable and start rabbitmq_exporter"
      systemd:
        name:    rabbitmq_exporter
        state:   started
        enabled: true

    - name: "[SERVICE] Wait for exporter port {{ exporter_port }}"
      wait_for:
        host:    localhost
        port:    "{{ exporter_port }}"
        timeout: 30

    - name: "[SERVICE] Exporter is running"
      debug:
        msg: "rabbitmq_exporter is running on port {{ exporter_port }} ✅"

# =============================================================================
#  BLOCK 6 — TESTS
# =============================================================================

    - name: "[TEST 1] rabbitmq-server is active"
      shell: systemctl is-active rabbitmq-server
      register: t1
      changed_when: false
      failed_when:  t1.stdout != "active"

    - name: "[TEST 1] PASS — rabbitmq-server active"
      debug:
        msg: "rabbitmq-server is {{ t1.stdout }} ✅"

    - name: "[TEST 2] rabbitmq_exporter is active"
      shell: systemctl is-active rabbitmq_exporter
      register: t2
      changed_when: false
      failed_when:  t2.stdout != "active"

    - name: "[TEST 2] PASS — rabbitmq_exporter active"
      debug:
        msg: "rabbitmq_exporter is {{ t2.stdout }} ✅"

    - name: "[TEST 3] Port 5672 is listening"
      wait_for:
        host:    localhost
        port:    5672
        timeout: 10

    - name: "[TEST 3] PASS — Port 5672 open"
      debug:
        msg: "AMQP port 5672 is listening ✅"

    - name: "[TEST 4] Port 15672 is listening"
      wait_for:
        host:    localhost
        port:    15672
        timeout: 10

    - name: "[TEST 4] PASS — Port 15672 open"
      debug:
        msg: "Management port 15672 is listening ✅"

    - name: "[TEST 5] Port 9419 is listening"
      wait_for:
        host:    localhost
        port:    "{{ exporter_port }}"
        timeout: 10

    - name: "[TEST 5] PASS — Port 9419 open"
      debug:
        msg: "Exporter port {{ exporter_port }} is listening ✅"

    - name: "[TEST 6] Management API health check"
      uri:
        url:              "http://localhost:15672/api/healthchecks/node"
        user:             "{{ rmq_user }}"
        password:         "{{ rmq_pass }}"
        force_basic_auth: true
        status_code:      200
      register: t6

    - name: "[TEST 6] PASS — Management API healthy"
      debug:
        msg: "Management API health → HTTP {{ t6.status }} ✅"

    - name: "[TEST 7] Exporter /metrics endpoint"
      uri:
        url:            "http://localhost:{{ exporter_port }}/metrics"
        return_content: true
        status_code:    200
      register: metrics

    - name: "[TEST 7] PASS — Metrics endpoint reachable"
      debug:
        msg: "Exporter /metrics → HTTP {{ metrics.status }} ✅"

    - name: "[TEST 8] Queue metrics present"
      assert:
        that:        "'rabbitmq_queue' in metrics.content"
        success_msg: "Queue metrics found ✅"
        fail_msg:    "Queue metrics NOT found ❌"

    - name: "[TEST 9] Node metrics present"
      assert:
        that:        "'rabbitmq_node' in metrics.content"
        success_msg: "Node metrics found ✅"
        fail_msg:    "Node metrics NOT found ❌"

    - name: "[TEST 10] rabbitmq_up metric present"
      assert:
        that:        "'rabbitmq_up' in metrics.content"
        success_msg: "rabbitmq_up found ✅"
        fail_msg:    "rabbitmq_up NOT found ❌"

    - name: "Count total metrics"
      shell: "curl -s http://localhost:{{ exporter_port }}/metrics | grep -v '^#' | wc -l"
      register: metric_count
      changed_when: false

# =============================================================================
#  BLOCK 7 — SUMMARY
# =============================================================================

    - name: "FINAL SUMMARY"
      debug:
        msg:
          - "========================================================"
          - "  RabbitMQ Exporter — All Tests Passed  🐇"
          - "========================================================"
          - "  Binary          : {{ exporter_binary }}"
          - "  Total metrics   : {{ metric_count.stdout }}"
          - "========================================================"
          - "  ACCESS URLS:"
          - "  Exporter  → http://{{ ansible_default_ipv4.address }}:{{ exporter_port }}/metrics"
          - "  Mgmt UI   → http://{{ ansible_default_ipv4.address }}:15672"
          - "  Login     → {{ rmq_user }} / {{ rmq_pass }}"
          - "========================================================"
          - "  TEST COMMANDS:"
          - "  curl -s http://localhost:{{ exporter_port }}/metrics | grep rabbitmq_queue"
          - "  curl -s http://localhost:{{ exporter_port }}/metrics | grep rabbitmq_node"
          - "  curl -s http://localhost:{{ exporter_port }}/metrics | grep -v '^#' | wc -l"
          - "========================================================"
          - "  SERVICE COMMANDS:"
          - "  systemctl status  rabbitmq_exporter"
          - "  systemctl restart rabbitmq_exporter"
          - "  journalctl -u rabbitmq_exporter -f"
          - "========================================================"
