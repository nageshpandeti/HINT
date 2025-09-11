import boto3

# Initialize boto3 client (Mumbai region)
region = "ap-south-1"
ec2 = boto3.resource("ec2", region_name=region)
client = boto3.client("ec2", region_name=region)

# 🔹 Step 1: Fetch latest Amazon Linux 2 AMI ID
ami_response = client.describe_images(
    Owners=["amazon"],
    Filters=[
        {"Name": "name", "Values": ["amzn2-ami-hvm-*-x86_64-gp2"]},
        {"Name": "state", "Values": ["available"]}
    ]
)

# Sort images by creation date (latest first)
images = sorted(ami_response["Images"], key=lambda x: x["CreationDate"], reverse=True)
latest_ami = images[0]["ImageId"]

print(f"Using latest Amazon Linux 2 AMI: {latest_ami}")

# 🔹 Step 2: Launch EC2 instance
instances = ec2.create_instances(
    ImageId=latest_ami,
    MinCount=1,
    MaxCount=1,
    InstanceType="t3.micro",                  # Free-tier eligible
    KeyName="tomcat",                         # Your key pair
    SecurityGroupIds=["sg-05cecc89c2dacee03"],# Your SG
    SubnetId="subnet-0b1b2fa6b11643a0b",      # Your subnet
    TagSpecifications=[
        {
            "ResourceType": "instance",
            "Tags": [{"Key": "Name", "Value": "MyEC2Instance"}]
        }
    ]
)

# 🔹 Step 3: Wait until running and get details
instance = instances[0]
print(f"Launching EC2 instance {instance.id}...")
instance.wait_until_running()
instance.reload()

print("✅ EC2 instance is running!")
print(f"Instance ID : {instance.id}")
print(f"Public IPv4 : {instance.public_ip_address}")
print(f"Private IPv4: {instance.private_ip_address}")
