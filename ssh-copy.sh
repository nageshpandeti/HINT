#!/bin/bash

# === CONFIGURATION ===
<<<<<<< HEAD
CONTROL_USER="ansible"
MANAGED_IP="65.0.95.35"  # Replace with actual IP
ANSIBLE_PASSWORD="Ansible@123"# Replace with desired password

# === STEP 1: Install Ansible on Control Node ===
echo "[+] Installing Ansible on control node..."
=======
CONTROL_USER=$(whoami)
MANAGED_USER="ubuntu"                 # Change if your managed node uses a different username
MANAGED_IP="65.0.95.35"           # Replace with your managed node's IP
INVENTORY_FILE="$HOME/ansible_hosts"

echo "🔧 Updating system and installing Ansible..."
>>>>>>> ec04af13c76913e5fd63f395507ae8d04ab31a37
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible

<<<<<<< HEAD
# === STEP 2: Create ansible user on control node ===
echo "[+] Creating '$CONTROL_USER' user on control node..."
sudo useradd -m -s /bin/bash $CONTROL_USER
echo "$CONTROL_USER:$ANSIBLE_PASSWORD" | sudo chpasswd
sudo usermod -aG sudo $CONTROL_USER

# === STEP 3: Generate SSH key ===
echo "[+] Generating SSH key for '$CONTROL_USER'..."
sudo -u $CONTROL_USER ssh-keygen -t rsa -b 4096 -N "" -f /home/$CONTROL_USER/.ssh/id_rsa

# === STEP 4: Create ansible user on managed node ===
echo "[+] Creating '$CONTROL_USER' user on managed node..."
sshpass -p "ubuntu" ssh -o StrictHostKeyChecking=no ubuntu@$MANAGED_IP "sudo useradd -m -s /bin/bash $CONTROL_USER && echo '$CONTROL_USER:$ANSIBLE_PASSWORD' | sudo chpasswd && sudo usermod -aG sudo $CONTROL_USER"

# === STEP 5: Copy SSH key to managed node ===
echo "[+] Copying SSH key to managed node..."
sudo -u $CONTROL_USER sshpass -p "$ANSIBLE_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no $CONTROL_USER@$MANAGED_IP

# === STEP 6: Configure inventory ===
echo "[+] Configuring Ansible inventory..."
echo "[managed]" | sudo tee /etc/ansible/hosts
echo "$MANAGED_IP ansible_user=$CONTROL_USER" | sudo tee -a /etc/ansible/hosts

# === STEP 7: Test connectivity ===
echo "[+] Testing Ansible connectivity..."
sudo -u $CONTROL_USER ansible all -m ping

echo "[✓] Setup complete. You can now run playbooks targeting $MANAGED_IP"
=======
echo "✅ Ansible installed: $(ansible --version | head -n 1)"

echo "🔐 Generating SSH key (if not exists)..."
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    ssh-keygen -t rsa -b 4096 -C "ansible-lab" -f "$HOME/.ssh/id_rsa" -N ""
fi
>>>>>>> ec04af13c76913e5fd63f395507ae8d04ab31a37
