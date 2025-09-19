import boto3

# ------------ CONFIGURATION ------------
AMI_ID = "ami-05a5bb48beb785bf1"   # Ubuntu 22.04 LTS in ap-south-1
INSTANCE_TYPE = "t3.micro"         # Free Tier eligible
KEY_NAME = "K8s.pem"                # Replace with your EC2 key pair
SECURITY_GROUP_ID = "sg-0d21280163fdc314e"  # Replace with your Security Group ID
SUBNET_ID = "subnet-0f5baa22efcc33c3a"      # Replace with your Subnet ID
REGION = "ap-south-1"
TAG_PROJECT = "k8s-practice"

ec2 = boto3.resource("ec2", region_name=REGION)


def launch_instance(name):
    """Launch a single EC2 instance and return it."""
    instance = ec2.create_instances(
        ImageId=AMI_ID,
        InstanceType=INSTANCE_TYPE,
        KeyName=KEY_NAME,
        SecurityGroupIds=[SECURITY_GROUP_ID],   # ✅ Use ID, not name
        SubnetId=SUBNET_ID,
        MinCount=1,
        MaxCount=1,
        TagSpecifications=[
            {
                "ResourceType": "instance",
                "Tags": [
                    {"Key": "Name", "Value": name},
                    {"Key": "Project", "Value": TAG_PROJECT}
                ]
            }
        ]
    )[0]

    print(f"Launching {name}... Instance ID: {instance.id}")
    instance.wait_until_running()
    instance.reload()
    print(f"{name} Public IP: {instance.public_ip_address}")
    return instance


def main():
    # Launch Master Node
    master = launch_instance("master-node")

    # Launch Worker Nodes
    workers = []
    for i in range(1, 3):
        workers.append(launch_instance(f"worker-node-{i}"))

    print("\n✅ Cluster launched successfully!")
    print(f"Master Node: {master.public_ip_address}")
    for idx, worker in enumerate(workers, start=1):
        print(f"Worker Node {idx}: {worker.public_ip_address}")


if __name__ == "__main__":
    main()
