#!/bin/bash

set -e

echo "🔧 Updating system..."
sudo apt update -y
sudo apt upgrade -y

echo "☕ Installing OpenJDK 17..."
sudo apt install openjdk-17-jdk -y

echo "🔧 Installing Maven..."
sudo apt install maven -y

echo "🐙 Installing Git..."
sudo apt install git -y

echo "🐳 Installing Docker..."
sudo apt install apt-transport-https ca-certificates curl software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update -y
sudo apt install docker-ce docker-ce-cli containerd.io -y
sudo usermod -aG docker $USER

echo "🔐 Installing Jenkins..."
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo \
  "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update -y
sudo apt install fontconfig openjdk-17-jre jenkins -y
sudo systemctl enable jenkins
sudo systemctl start jenkins

echo "✅ All tools installed successfully!"
echo "🔑 Jenkins initial admin password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
