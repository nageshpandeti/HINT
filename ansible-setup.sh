#!/bin/bash

# Exit on any error
set -e

echo "🔧 Updating system packages..."
sudo apt update -y
sudo apt upgrade -y

echo "📦 Installing software-properties-common..."
sudo apt install -y software-properties-common

echo "📚 Adding Ansible PPA repository..."
sudo add-apt-repository --yes --update ppa:ansible/ansible

echo "🚀 Installing Ansible..."
sudo apt install -y ansible

echo "✅ Verifying installation..."
ansible --version

echo "🎉 Ansible installation complete!"