---
# redis_exporter_complete.yml
# Complete Ansible playbook: Install + Configure + Verify + Cleanup Redis & Redis Exporter
# Usage:
#   ansible-playbook redis_exporter_complete.yml
#   (runs locally on the same machine — no separate inventory needed)

- name: Complete Redis + Redis Exporter Setup, Verify and Cleanup
  hosts: localhost
  connection: local
  become: true

  vars:
    redis_exporter_version: "1.62.0"
    redis_exporter_arch: "amd64"
    redis_exporter_port: 9121
    redis_host: "127.0.0.1"
    redis_port: 6379
    redis_password: ""

  tasks:

    # ─────────────────────────────────────────
    # STEP 1 — SYSTEM UPDATE
    # ─────────────────────────────────────────
    - name: "[1/7] Update apt cache"
      apt:
        update_cache: true
        cache_valid_time: 3600

    - name: "[1/7] Install required system packages"
      apt:
        name:
          - curl
          - wget
          - tar
          - python3
        state: present

    # ─────────────────────────────────────────
    # STEP 2 — INSTALL REDIS
    # ─────────────────────────────────────────
    - name: "[2/7] Install Redis server and tools"
      apt:
        name:
          - redis-server
          - redis-tools
        state: present

    - name: "[2/7] Ensure Redis config allows local connections"
      lineinfile:
        path: /etc/redis/redis.conf
        regexp: "^bind "
        line: "bind 127.0.0.1 ::1"
        backup: true

    - name: "[2/7] Enable and start Redis service"
      systemd:
        name: redis-server
        enabled: true
        state: started
        daemon_reload: true

    - name: "[2/7] Wait for Redis port to be ready"
      wait_for:
        host: "{{ redis_host }}"
        port: "{{ redis_port }}"
        timeout: 30

    - name: "[2/7] Ping Redis to confirm it is up"
      command: redis-cli ping
      register: redis_ping
      changed_when: false
      failed_when: redis_ping.stdout != "PONG"

    - name: "[2/7] Show Redis ping result"
      debug:
        msg: "Redis responded with: {{ redis_ping.stdout }}"

    # ─────────────────────────────────────────
    # STEP 3 — SEED TEST DATA INTO REDIS
    # ─────────────────────────────────────────
    - name: "[3/7] Set a test string key"
      command: redis-cli SET test_key "hello_from_ansible"
      changed_when: true

    - name: "[3/7] Increment a counter key"
      command: redis-cli INCR hit_counter
      changed_when: true

    - name: "[3/7] Push items to a list"
      command: redis-cli LPUSH test_list alpha beta gamma
      changed_when: true

    - name: "[3/7] Set a key with TTL (60 seconds)"
      command: redis-cli SET expiring_key "bye" EX 60
      changed_when: true

    - name: "[3/7] Add items to a set"
      command: redis-cli SADD test_set "one" "two" "three"
      changed_when: true

    - name: "[3/7] Confirm test keys exist"
      command: redis-cli KEYS "*"
      register: redis_keys
      changed_when: false

    - name: "[3/7] Show seeded keys"
      debug:
        msg: "Keys in Redis: {{ redis_keys.stdout_lines }}"

    # ─────────────────────────────────────────
    # STEP 4 — INSTALL REDIS EXPORTER
    # ─────────────────────────────────────────
    - name: "[4/7] Set exporter tarball filename"
      set_fact:
        exporter_tarball: "redis_exporter-v{{ redis_exporter_version }}.linux-{{ redis_exporter_arch }}.tar.gz"
        exporter_dir: "redis_exporter-v{{ redis_exporter_version }}.linux-{{ redis_exporter_arch }}"

    - name: "[4/7] Download Redis Exporter tarball"
      get_url:
        url: "https://github.com/oliver006/redis_exporter/releases/download/v{{ redis_exporter_version }}/{{ exporter_tarball }}"
        dest: "/tmp/{{ exporter_tarball }}"
        mode: "0644"

    - name: "[4/7] Extract Redis Exporter"
      unarchive:
        src: "/tmp/{{ exporter_tarball }}"
        dest: /tmp/
        remote_src: true

    - name: "[4/7] Install Redis Exporter binary to /usr/local/bin"
      copy:
        src: "/tmp/{{ exporter_dir }}/redis_exporter"
        dest: /usr/local/bin/redis_exporter
        mode: "0755"
        remote_src: true

    - name: "[4/7] Verify Redis Exporter binary exists"
      stat:
        path: /usr/local/bin/redis_exporter
      register: exporter_bin
      failed_when: not exporter_bin.stat.exists

    - name: "[4/7] Create Redis Exporter systemd service (no auth)"
      copy:
        dest: /etc/systemd/system/redis_exporter.service
        mode: "0644"
        content: |
          [Unit]
          Description=Redis Exporter
          After=network.target redis-server.service

          [Service]
          User=nobody
          ExecStart=/usr/local/bin/redis_exporter \
            --redis.addr=redis://{{ redis_host }}:{{ redis_port }} \
            --web.listen-address=0.0.0.0:{{ redis_exporter_port }}
          Restart=on-failure
          RestartSec=5s

          [Install]
          WantedBy=multi-user.target
      when: redis_password == ""

    - name: "[4/7] Create Redis Exporter systemd service (with auth)"
      copy:
        dest: /etc/systemd/system/redis_exporter.service
        mode: "0644"
        content: |
          [Unit]
          Description=Redis Exporter
          After=network.target redis-server.service

          [Service]
          User=nobody
          ExecStart=/usr/local/bin/redis_exporter \
            --redis.addr=redis://{{ redis_host }}:{{ redis_port }} \
            --redis.password={{ redis_password }} \
            --web.listen-address=0.0.0.0:{{ redis_exporter_port }}
          Restart=on-failure
          RestartSec=5s

          [Install]
          WantedBy=multi-user.target
      when: redis_password != ""

    - name: "[4/7] Reload systemd and enable Redis Exporter"
      systemd:
        name: redis_exporter
        enabled: true
        state: started
        daemon_reload: true

    - name: "[4/7] Wait for Redis Exporter metrics port to be ready"
      wait_for:
        host: "{{ redis_host }}"
        port: "{{ redis_exporter_port }}"
        timeout: 30

    # ─────────────────────────────────────────
    # STEP 5 — VERIFY METRICS
    # ─────────────────────────────────────────
    - name: "[5/7] Fetch /metrics from Redis Exporter"
      uri:
        url: "http://{{ redis_host }}:{{ redis_exporter_port }}/metrics"
        return_content: true
      register: metrics_output

    - name: "[5/7] Assert redis_up is 1"
      assert:
        that:
          - "'redis_up 1' in metrics_output.content"
        fail_msg: "FAILED — redis_up metric not found or Redis is down!"
        success_msg: "PASSED — Redis Exporter is up and redis_up = 1"

    - name: "[5/7] Show key metrics"
      debug:
        msg: "{{ metrics_output.content
              | regex_findall('(?m)^(redis_up|redis_connected_clients|redis_used_memory_bytes|redis_keyspace_hits_total|redis_keyspace_misses_total|redis_commands_processed_total)[^\n]*') }}"

    - name: "[5/7] Check Redis Exporter service status"
      command: systemctl is-active redis_exporter
      register: exporter_status
      changed_when: false
      failed_when: exporter_status.stdout != "active"

    - name: "[5/7] Show service status"
      debug:
        msg: "redis_exporter service is: {{ exporter_status.stdout }}"

    # ─────────────────────────────────────────
    # STEP 6 — CLEANUP TEMP FILES
    # ─────────────────────────────────────────
    - name: "[6/7] Remove downloaded tarball"
      file:
        path: "/tmp/{{ exporter_tarball }}"
        state: absent

    - name: "[6/7] Remove extracted exporter directory"
      file:
        path: "/tmp/{{ exporter_dir }}"
        state: absent

    # ─────────────────────────────────────────
    # STEP 7 — FINAL SUMMARY
    # ─────────────────────────────────────────
    - name: "[7/7] Final summary"
      debug:
        msg:
          - "============================================"
          - " Redis + Redis Exporter setup complete!    "
          - "============================================"
          - "  Redis          : {{ redis_host }}:{{ redis_port }}"
          - "  Redis Exporter : {{ redis_host }}:{{ redis_exporter_port }}"
          - "  Metrics URL    : http://{{ redis_host }}:{{ redis_exporter_port }}/metrics"
          - "  Service status : {{ exporter_status.stdout }}"
          - "============================================"
          - "  Useful commands:"
          - "  curl http://localhost:{{ redis_exporter_port }}/metrics"
          - "  systemctl status redis_exporter"
          - "  systemctl status redis-server"
          - "  journalctl -u redis_exporter -f"
          - "============================================"
