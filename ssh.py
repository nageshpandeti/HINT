import boto3
import time
import paramiko
import os
from botocore.exceptions import ClientError

# ---------- Configuration ----------
REGION = "ap-south-1"                 # Change to your AWS region
AMI_ID = "ami-08e5424edfe926b43"      # Ubuntu 22.04 LTS in ap-south-1
INSTANCE_TYPE = "t2.micro"
KEY_NAME = "tomcat"                   # Existing AWS key pair name (.pem already downloaded)
SECURITY_GROUP = "sg-05cecc89c2dacee03"            # Security group must allow SSH (22)
CONTROL_NODE_NAME = "control-node"
MANAGED_NODE_NAME = "managed-node"
PEM_FILE_PATH = "/path/to/tomcat.pem" # Local path to your pem file
USERNAME = "ubuntu"                   # For Ubuntu AMI

ec2 = boto3.resource("ec2", region_name=REGION)


def create_instance(name):
    print(f"🚀 Launching instance: {name}")
    instance = ec2.create_instances(
        ImageId=AMI_ID,
        InstanceType=INSTANCE_TYPE,
        KeyName=KEY_NAME,
        MinCount=1,
        MaxCount=1,
        SecurityGroups=[SECURITY_GROUP],
        TagSpecifications=[{
            "ResourceType": "instance",
            "Tags": [{"Key": "Name", "Value": name}]
        }]
    )[0]

    instance.wait_until_running()
    instance.reload()
    print(f"✅ {name} running at {instance.public_ip_address}")
    return instance


def ssh_client(ip, key_file):
    k = paramiko.RSAKey.from_private_key_file(key_file)
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(ip, username=USERNAME, pkey=k)
    return ssh


def run_command(ssh, command):
    stdin, stdout, stderr = ssh.exec_command(command)
    return stdout.read().decode(), stderr.read().decode()


# ---------- Main ----------
if __name__ == "__main__":
    # 1. Create Control Node and Managed Node
    control_node = create_instance(CONTROL_NODE_NAME)
    managed_node = create_instance(MANAGED_NODE_NAME)

    control_ip = control_node.public_ip_address
    managed_ip = managed_node.public_ip_address

    print(f"\nControl Node IP: {control_ip}")
    print(f"Managed Node IP: {managed_ip}")

    # Wait for instances to initialize
    print("⌛ Waiting for SSH service to start...")
    time.sleep(60)

    # 2. SSH into control node
    print("🔑 Connecting to Control Node...")
    control_ssh = ssh_client(control_ip, PEM_FILE_PATH)

    # 3. Generate SSH key on control node
    print("🔑 Generating SSH key on Control Node...")
    run_command(control_ssh, "ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ''")

    # 4. Copy key to Managed Node using ssh-copy-id
    print("📤 Copying key to Managed Node...")
    copy_cmd = f"sshpass -p '' ssh-copy-id -i ~/.ssh/id_rsa.pub -o StrictHostKeyChecking=no -o IdentityFile={PEM_FILE_PATH} {USERNAME}@{managed_ip}"
    run_command(control_ssh, copy_cmd)

    # 5. Test passwordless SSH
    print("🔍 Testing passwordless SSH...")
    test_cmd = f"ssh -o StrictHostKeyChecking=no {USERNAME}@{managed_ip} 'hostname'"
    output, error = run_command(control_ssh, test_cmd)

    if error:
        print("❌ SSH Test Failed:", error)
    else:
        print("✅ SSH Test Successful! Connected to:", output.strip())
