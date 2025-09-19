#!/bin/bash

# Exit on any error
set -e

echo "<dd27> Updating system packages..."
sudo apt update -y
sudo apt upgrade -y

echo "<dce6> Installing software-properties-common..."
sudo apt install -y software-properties-common

echo "<dcda> Adding Ansible PPA repository..."
sudo add-apt-repository --yes --update ppa:ansible/ansible

echo "<de80> Installing Ansible..."
sudo apt install -y ansible

echo "✅ Verifying installation..."
ansible --version

echo "<df89> Ansible installation complete!"