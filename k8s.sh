#!/bin/bash

# Table initialization with header
declare -a steps=(
    "01    | Change the Hostname                                          | Pending"
    "02    | Persistent loading of modules                                | Pending"
    "03    | Load kernel modules                                          | Pending"
    "04    | Update IP Table settings                                     | Pending"
    "05    | Apply Kernel Settings Without Reboot                         | Pending"
    "06    | Add Docker Repository GPG Key                                | Pending"
    "07    | Add Docker Repository                                        | Pending"
    "08    | Install Containerd                                           | Pending"
    "09    | Configure containerd for systemd                             | Pending"
    "10    | Reload, Restart, Enable containerd                           | Pending"
    "11    | Install required packages for Kubernetes                     | Pending"
    "12    | Download Kubernetes GPG key                                  | Pending"
    "13    | Add Kubernetes Repository                                    | Pending"
    "14    | Install kubelet, kubeadm, kubectl                            | Pending"
    "15    | Hold the installed packages                                  | Pending"
    "16    | Enable kubelet service                                       | Pending"
    "17    | Disable swap temporarily                                     | Pending"
    "18    | Make swap off permanent                                      | Pending"
    "19    | Kubernetes MasterNode Initialized                            | Pending"
    "20    | Set KUBECONFIG and add it to .bashrc                          | Pending"
    "21    | Show kubectl get nodes and kubectl get pods -n kube-system     | Pending"
)

# User input for Master or Worker node selection
echo "Please select the node type:"
echo "1) Master Node"
echo "2) Worker Node"
read -p "Enter your choice (1 or 2): " node_choice

if [ "$node_choice" -eq 1 ]; then
    node_type="MasterNode"
elif [ "$node_choice" -eq 2 ]; then
    node_type="WorkerNode"
else
    echo "Invalid choice. Exiting."
    exit 1
fi

# Ask for unique hostname
while true; do
    read -p "Enter a unique hostname for this $node_type: " unique_hostname
    if [ -z "$unique_hostname" ]; then
        echo "Hostname cannot be empty. Please enter a valid hostname."
    else
        # Optionally check if hostname is valid (letters, digits, dash)
        if [[ "$unique_hostname" =~ ^[a-zA-Z0-9-]+$ ]]; then
            break
        else
            echo "Invalid hostname. Use only letters, numbers, and dashes."
        fi
    fi
done

echo "Setting hostname to $unique_hostname ..."
hostnamectl set-hostname "$unique_hostname"
steps[0]="01    | Change the Hostname                                          | Completed"

# Step 02: Persistent loading of modules
echo "Running: Persistent loading of modules..."
steps[1]="02    | Persistent loading of modules                                | Completed"

# Step 03: Load kernel modules
modprobe overlay
modprobe br_netfilter
steps[2]="03    | Load kernel modules                                          | Completed"

# Step 04: Update IP Table settings
tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
steps[3]="04    | Update IP Table settings                                     | Completed"

# Step 05: Apply Kernel Settings Without Reboot
sysctl --system
steps[4]="05    | Apply Kernel Settings Without Reboot                         | Completed"

# Step 06: Add Docker Repository GPG Key
mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
steps[5]="06    | Add Docker Repository GPG Key                                | Completed"

# Step 07: Add Docker Repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
steps[6]="07    | Add Docker Repository                                        | Completed"

# Step 08: Install Containerd
apt-get update && apt-get install -y containerd.io
steps[7]="08    | Install Containerd                                           | Completed"

# Step 09: Configure containerd for systemd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
steps[8]="09    | Configure containerd for systemd                             | Completed"

# Step 10: Reload, Restart, Enable containerd
systemctl daemon-reload
systemctl restart containerd
systemctl enable containerd
steps[9]="10    | Reload, Restart, Enable containerd                           | Completed"

# Step 11: Install required packages for Kubernetes
apt-get update && apt-get install -y apt-transport-https ca-certificates curl
steps[10]="11    | Install required packages for Kubernetes                     | Completed"

# Step 12: Download Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
steps[11]="12    | Download Kubernetes GPG key                                  | Completed"

# Step 13: Add Kubernetes Repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
steps[12]="13    | Add Kubernetes Repository                                    | Completed"

# Step 14: Install kubelet, kubeadm, kubectl
apt-get update && apt-get install -y kubelet kubeadm kubectl
steps[13]="14    | Install kubelet, kubeadm, kubectl                            | Completed"

# Step 15: Hold the installed packages
apt-mark hold kubelet kubeadm kubectl
steps[14]="15    | Hold the installed packages                                  | Completed"

# Step 16: Enable kubelet service
systemctl enable kubelet
steps[15]="16    | Enable kubelet service                                       | Completed"

# Step 17: Disable swap temporarily
swapoff -a
steps[16]="17    | Disable swap temporarily                                     | Completed"

# Step 18: Make swap off permanent
sed -i '/swap/d' /etc/fstab
steps[17]="18    | Make swap off permanent                                      | Completed"

# Step 19: Kubernetes MasterNode Initialization (Only if Master Node selected)
kubeadm_output=""
if [ "$node_choice" -eq 1 ]; then
    read -p "Do you want to proceed with Kubernetes MasterNode Initialization? (Yes/No): " proceed_init
    if [[ "$proceed_init" =~ ^[Yy](es)?$ ]]; then
        kubeadm_output=$(kubeadm init 2>&1)
        steps[18]="19    | Kubernetes MasterNode Initialized                            | Completed"
    else
        steps[18]="19    | Kubernetes MasterNode Initialization skipped                | Skipped"
    fi
fi

# Step 20: Set KUBECONFIG for root and add it to .bashrc
if [ "$EUID" -eq 0 ]; then
    export KUBECONFIG=/etc/kubernetes/admin.conf
    echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /root/.bashrc
    steps[19]="20    | Set KUBECONFIG and added it to .bashrc for root              | Completed"
else
    echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> ~/.bashrc
    steps[19]="20    | Set KUBECONFIG and added it to .bashrc for user              | Completed"
fi

# Step 21: Show kubectl get nodes and kubectl get pods -n kube-system
kubectl get nodes
kubectl get pods -n kube-system
steps[20]="21    | Show kubectl get nodes and kubectl get pods -n kube-system   | Completed"

# Print the final table at the end
echo -e "+-------+------------------------------------------------------------+-----------------+"
echo -e "| Step  | Description                                              | Process State   |"
echo -e "+-------+------------------------------------------------------------+-----------------+"
for step in "${steps[@]}"
do
    echo -e "| $step"
done

# Show the final output of `kubeadm init` if it was executed
if [ "$node_choice" -eq 1 ] && [[ -n "$kubeadm_output" ]]; then
    echo -e "+-------+------------------------------------------------------------+-----------------+"
    echo -e "| Final Output of kubeadm init                                |"
    echo -e "+-------+------------------------------------------------------------+-----------------+"
    echo "$kubeadm_output" | while IFS= read -r line; do
        echo -e "| $line"
    done
    echo -e "+-------+------------------------------------------------------------+-----------------+"
fi

# Final message based on the selected node type
if [ "$node_choice" -eq 1 ]; then
    echo "Master Node setup completed!"
else
    echo "Worker Node setup completed!"
fi
