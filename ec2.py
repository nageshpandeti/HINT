import boto3

# Initialize EC2 client
ec2 = boto3.resource('ec2', region_name='us-east-1')

# Create a new EC2 instance
instances = ec2.create_instances(
    ImageId='ami-0360c520857e3138f',   # Replace with a valid AMI ID in your region
    MinCount=1,
    MaxCount=1,
    InstanceType='t2.micro',          # Free tier eligible
    KeyName='my-ec2keypair',             # Replace with your key pair name
    SecurityGroupIds=['sg-03b12def4d06032af'],  # Replace with your security group ID
    SubnetId='subnet-0123456789abcdef0',        # Replace with your subnet ID
    TagSpecifications=[
        {
            'ResourceType': 'instance',
            'Tags': [{'Key': 'Name', 'Value': 'MyBoto3Instance'}]
        }
    ]
)

print("EC2 Instance Created with ID:", instances[0].id)
