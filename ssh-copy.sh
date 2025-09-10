#!/bin/bash

# === CONFIGURATION ===
CONTROL_USER=$(whoami)
MANAGED_USER="ubuntu"                 # Change if your managed node uses a different username
MANAGED_IP="65.0.95.35"           # Replace with your managed node's IP
INVENTORY_FILE="$HOME/ansible_hosts"

echo "🔧 Updating system and installing Ansible..."
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible

echo "✅ Ansible installed: $(ansible --version | head -n 1)"

echo "🔐 Generating SSH key (if not exists)..."
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    ssh-keygen -t rsa -b 4096 -C "ansible-lab" -f "$HOME/.ssh/id_rsa" -N ""
fi
