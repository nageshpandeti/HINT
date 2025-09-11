#!/bin/bash
set -e

echo "🔄 Updating system packages..."
sudo yum update -y

echo "📦 Installing Docker..."
sudo yum install -y docker

echo "🚀 Starting and enabling Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

echo "👤 Adding ec2-user to Docker group..."
sudo usermod -aG docker ec2-user

echo "🔍 Validating Docker installation..."
echo "-----------------------------------"
echo "📌 Docker Info:"
docker info || echo "⚠️ Run 'docker info' after re-login as ec2-user."

<<<<<<< HEAD
echo "-----------------------------------"
=======
echo "-----------------------------------"vi    
>>>>>>> ec04af13c76913e5fd63f395507ae8d04ab31a37
echo "📌 Docker Service Status:"
sudo systemctl status docker --no-pager | head -n 10

echo "✅ Docker installed, running, and validated!"
echo "⚠️ Please log out and log back in for 'ec2-user' group changes to take effect."
