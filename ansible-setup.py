#!/usr/bin/env python3

import subprocess
import os
import getpass
import sys

def run_cmd(cmd, check=True, capture_output=False, text=True):
    """Helper to run shell commands"""
    return subprocess.run(cmd, shell=True, check=check,
                          capture_output=capture_output, text=text)

def is_installed(command):
    """Check if a command exists"""
    return subprocess.call(f"command -v {command}", shell=True,
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL) == 0

def main():
    print("[INFO] Checking Python3...")
    python_installed = is_installed("python3")
    if python_installed:
        print("[OK] Python3 already installed.")

    print("[INFO] Checking Ansible...")
    ansible_installed = is_installed("ansible")
    if ansible_installed:
        print("[OK] Ansible already installed.")

    # Exit early if both installed
    if python_installed and ansible_installed:
        print("[EXIT] Python3 and Ansible are already installed. Nothing to do.")
        sys.exit(0)

    print("[INFO] Updating system and installing prerequisites...")
    try:
        run_cmd("sudo yum update -y || sudo dnf update -y")
        run_cmd("sudo yum install -y python3 python3-pip sshpass || sudo dnf install -y python3 python3-pip sshpass")
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Package installation failed: {e}")
        sys.exit(1)

    if not ansible_installed:
        print("[INFO] Installing Ansible...")
        with open("/etc/system-release") as f:
            release_info = f.read()
        if "Amazon Linux release 2" in release_info:
            run_cmd("sudo amazon-linux-extras enable ansible2")
            run_cmd("sudo yum install -y ansible")
        else:
            run_cmd("sudo dnf install -y ansible-core")

    # Generate SSH key if missing
    ssh_dir = os.path.expanduser("~/.ssh")
    pub_key = os.path.join(ssh_dir, "id_rsa.pub")
    if not os.path.exists(pub_key):
        print("[INFO] Generating SSH key...")
        os.makedirs(ssh_dir, exist_ok=True)
        run_cmd("ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa")
    else:
        print("[OK] SSH key already exists.")

    # Define managed nodes
    managed_nodes = ["ec2-user@13.233.15.116"]

    # Ask for password once
    ssh_pass = getpass.getpass("Enter SSH password for managed nodes: ")

    for node in managed_nodes:
        print(f"[INFO] Copying SSH key to {node}...")
        try:
            run_cmd(f"sshpass -p '{ssh_pass}' ssh-copy-id -o StrictHostKeyChecking=no {node}")
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Failed to copy SSH key to {node}: {e}")

    print("[SUCCESS] Setup complete!")
    print("Try running: ansible all -m ping -i 'ec2-user@13.233.15.116,'")

if __name__ == "__main__":
    main()
