#!/usr/bin/env python3
import os
import subprocess
import getpass

def run_cmd(cmd, check=True):
    """Run a shell command."""
    try:
        subprocess.run(cmd, shell=True, check=check)
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Command failed: {cmd}\n{e}")

def generate_ssh_key():
    """Generate SSH key if missing."""
    ssh_dir = os.path.expanduser("~/.ssh")
    pub_key = os.path.join(ssh_dir, "id_rsa.pub")

    if not os.path.exists(pub_key):
        print("[INFO] Generating SSH key...")
        os.makedirs(ssh_dir, exist_ok=True)
        run_cmd("ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa")
    else:
        print("[OK] SSH key already exists.")
    return pub_key

def copy_ssh_key(node):
    """Copy SSH key interactively (asks for password)."""
    print(f"\n[INFO] Copying SSH key to {node} ...")
    cmd = f"ssh-copy-id -o StrictHostKeyChecking=no {node}"
    run_cmd(cmd)

def test_ssh_connection(node):
    """Test SSH connection without password."""
    print(f"[INFO] Testing SSH connection to {node} ...")
    cmd = f"ssh -o BatchMode=yes -o StrictHostKeyChecking=no {node} 'echo SUCCESS'"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if "SUCCESS" in result.stdout:
        print(f"[OK] SSH connection to {node} works without password.")
    else:
        print(f"[ERROR] SSH connection to {node} failed.\n{result.stderr}")

def main():
    # 🔹 Add your managed nodes here
    managed_nodes = [
        "ec2-user@13.233.15.116"
        # "ubuntu@<another-ip>",
        # "centos@<another-ip>"
    ]

    # Step 1: Generate SSH key if missing
    generate_ssh_key()

    # Step 2: Copy key interactively to each node
    for node in managed_nodes:
        copy_ssh_key(node)

    # Step 3: Test connections
    for node in managed_nodes:
        test_ssh_connection(node)

    print("\n[SUCCESS] SSH setup complete. You can now use Ansible without password.")

if __name__ == "__main__":
    main()
