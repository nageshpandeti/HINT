echo "=== Installing Docker Engine ==="
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== Starting and enabling Docker ==="
sudo systemctl start docker
sudo systemctl enable docker

echo "=== Adding current user to docker group ==="
sudo usermod -aG docker $USER
echo "You may need to log out and log back in for group changes to take effect."

echo "=== Validating Docker installation ==="
docker --version || { echo "Docker installation failed"; exit 1; }
docker run hello-world || { echo "Docker test run failed"; exit 1; }

echo "=== Docker installation and setup completed successfully! ==="