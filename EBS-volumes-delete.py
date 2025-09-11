import boto3

# Initialize EC2 client for Mumbai region
region = "ap-south-1"
ec2 = boto3.client("ec2", region_name=region)

def delete_unused_volumes():
    response = ec2.describe_volumes()
    volumes = response["Volumes"]

    if not volumes:
        print(f"No EBS volumes found in {region}.")
        return

    print(f"🔹 Checking {len(volumes)} EBS volume(s) in {region}...\n")

    for vol in volumes:
        vol_id = vol["VolumeId"]
        size = vol["Size"]
        state = vol["State"]
        az = vol["AvailabilityZone"]
        attachments = vol["Attachments"]

        if state == "available" and not attachments:
            try:
                ec2.delete_volume(VolumeId=vol_id)
                print(f"✅ Deleted unused volume: {vol_id} ({size} GiB in {az})")
            except Exception as e:
                print(f"❌ Failed to delete {vol_id}: {e}")
        else:
            print(f"⚠️ Skipping {vol_id} ({size} GiB) - State: {state}, Attachments: {len(attachments)}")

if __name__ == "__main__":
    delete_unused_volumes()
