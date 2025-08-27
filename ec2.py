import boto3

def create_ec2():
    # Initialize EC2 resource
    ec2 = boto3.resource('ec2', region_name='us-east-1')

    print("🚀 Launching EC2 instance...")

    # Launch instance
    instances = ec2.create_instances(
        ImageId='ami-0c55b159cbfafe1f0',   # Replace with a valid AMI in your region
        MinCount=1,
        MaxCount=1,
        InstanceType='t2.micro',          # Free tier eligible
        KeyName='my-keypair',             # Must exist in AWS
        SecurityGroupIds=['sg-0123456789abcdef0'],  # Replace with your SG
        SubnetId='subnet-0123456789abcdef0',        # Replace with your subnet
        TagSpecifications=[
            {
                'ResourceType': 'instance',
                'Tags': [{'Key': 'Name', 'Value': 'Boto3EC2'}]
            }
        ]
    )

    instance = instances[0]

    # Wait for it to run
    print("⌛ Waiting for instance to be in running state...")
    instance.wait_until_running()
    instance.reload()

    print(f"✅ EC2 Instance created: {instance.id}, Public IP: {instance.public_ip_address}")

if __name__ == "__main__":
    create_ec2()
