import boto3

# Initialize EC2 client for Mumbai region
region = "ap-south-1"
ec2 = boto3.client("ec2", region_name=region)

def list_ebs_volumes():
    response = ec2.describe_volumes()
    volumes = response["Volumes"]

    if not volumes:
        print(f"No EBS volumes found in {region}.")
        return

    print(f"🔹 EBS Volumes in {region}:\n")

    for vol in volumes:
        vol_id = vol["VolumeId"]
        size = vol["Size"]
        state = vol["State"]
        az = vol["AvailabilityZone"]
        attachments = vol["Attachments"]

        attached_instance = attachments[0]["InstanceId"] if attachments else "Not attached"

        print(f" - Volume ID    : {vol_id}")
        print(f"   Size (GiB)  : {size}")
        print(f"   State       : {state}")
        print(f"   AZ          : {az}")
        print(f"   Attached to : {attached_instance}")
        print("-" * 40)

if __name__ == "__main__":
    list_ebs_volumes()
