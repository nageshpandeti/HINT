#!/bin/bash
# setup_redis_exporter.sh
# End-to-end Redis + Redis Exporter + Prometheus setup on Ubuntu VM
# Run as: bash setup_redis_exporter.sh

set -e

echo "===== [1/5] Updating packages ====="
sudo apt-get update -y

# ─────────────────────────────────────────
# REDIS
# ─────────────────────────────────────────
echo "===== [2/5] Installing Redis ====="
sudo apt-get install -y redis-server

# Enable and start Redis
sudo systemctl enable redis-server
sudo systemctl start redis-server

# Quick sanity check
redis-cli ping   # Should print: PONG

# ─────────────────────────────────────────
# REDIS EXPORTER
# ─────────────────────────────────────────
echo "===== [3/5] Installing Redis Exporter ====="

EXPORTER_VERSION="1.62.0"
ARCH="amd64"
TARBALL="redis_exporter-v${EXPORTER_VERSION}.linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/oliver006/redis_exporter/releases/download/v${EXPORTER_VERSION}/${TARBALL}"

cd /tmp
wget -q "$DOWNLOAD_URL" -O "$TARBALL"
tar -xzf "$TARBALL"
sudo mv "redis_exporter-v${EXPORTER_VERSION}.linux-${ARCH}/redis_exporter" /usr/local/bin/
sudo chmod +x /usr/local/bin/redis_exporter

# Create a systemd service for redis_exporter
sudo tee /etc/systemd/system/redis_exporter.service > /dev/null <<EOF
[Unit]
Description=Redis Exporter
After=network.target redis-server.service

[Service]
User=nobody
ExecStart=/usr/local/bin/redis_exporter \
  --redis.addr=redis://127.0.0.1:6379 \
  --web.listen-address=0.0.0.0:9121
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable redis_exporter
sudo systemctl start redis_exporter

# ─────────────────────────────────────────
# PROMETHEUS (optional but recommended)
# ─────────────────────────────────────────
echo "===== [4/5] Installing Prometheus ====="

PROM_VERSION="2.51.2"
PROM_TARBALL="prometheus-${PROM_VERSION}.linux-${ARCH}.tar.gz"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/${PROM_TARBALL}"

cd /tmp
wget -q "$PROM_URL" -O "$PROM_TARBALL"
tar -xzf "$PROM_TARBALL"
sudo mv "prometheus-${PROM_VERSION}.linux-${ARCH}/prometheus" /usr/local/bin/
sudo mv "prometheus-${PROM_VERSION}.linux-${ARCH}/promtool"   /usr/local/bin/

# Prometheus config — scrapes redis_exporter every 15s
sudo mkdir -p /etc/prometheus
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'redis'
    static_configs:
      - targets: ['localhost:9121']
EOF

# Systemd service for Prometheus
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
User=nobody
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.listen-address=0.0.0.0:9090
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo mkdir -p /var/lib/prometheus
sudo chown nobody:nogroup /var/lib/prometheus

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

echo "===== [5/5] Setup complete! ====="
