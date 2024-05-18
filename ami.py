import boto3
import time
import os

# Define variables
AMI_NAME = "test"
REGION = "us-east-1"
SOURCE_BUCKET = "test-j3"
LOCAL_PATH = os.getenv('LOCAL_PATH', '/data')  # Use environment variable or default to /data
ROLE_ARN = "arn:aws:iam::992382823608:role/assume-role"
DEST_REGION = "us-west-2"
DEST_BUCKET = "test-j3-1"
SHARE_ACCOUNTS = [""]  # Add your account IDs here

def assume_role(role_arn, session_name):
    sts_client = boto3.client('sts')
    assumed_role = sts_client.assume_role(RoleArn=role_arn, RoleSessionName=session_name)
    credentials = assumed_role['Credentials']
    return boto3.Session(
        aws_access_key_id=credentials['AccessKeyId'],
        aws_secret_access_key=credentials['SecretAccessKey'],
        aws_session_token=credentials['SessionToken']
    )

def get_latest_ami_id(ec2_client, ami_name):
    images = ec2_client.describe_images(Owners=['self'], Filters=[{'Name': 'name', 'Values': [ami_name]}])
    latest_image = sorted(images['Images'], key=lambda x: x['CreationDate'], reverse=True)[0]
    return latest_image['ImageId']

def wait_for_task_completion(ec2_client, image_id, task_state='Completed'):
    while True:
        tasks = ec2_client.describe_store_image_tasks(ImageIds=[image_id])
        if tasks['StoreImageTaskResults'][0]['StoreTaskState'] == task_state:
            break
        time.sleep(30)

def wait_for_s3_file(s3_client, bucket, key):
    while True:
        try:
            s3_client.head_object(Bucket=bucket, Key=key)
            break
        except s3_client.exceptions.NoSuchKey:
            time.sleep(30)

def wait_for_ami(ec2_client, image_id, state='available'):
    while True:
        images = ec2_client.describe_images(ImageIds=[image_id])
        if images['Images'][0]['State'] == state:
            break
        time.sleep(30)

def share_ami(ec2_client, image_id, accounts):
    for account in accounts:
        ec2_client.modify_image_attribute(
            ImageId=image_id,
            LaunchPermission={'Add': [{'UserId': account}]}
        )

# Assume role
session = assume_role(ROLE_ARN, "TestSession")
ec2_client = session.client('ec2', region_name=REGION)
s3_client = session.client('s3', region_name=REGION)

# Get the latest AMI ID
ami_id = get_latest_ami_id(ec2_client, AMI_NAME)
print(f"Latest AMI ID for '{AMI_NAME}' in '{REGION}': {ami_id}")

# Check if the AMI is already present in the source S3 bucket
try:
    s3_client.head_object(Bucket=SOURCE_BUCKET, Key=f"{ami_id}.bin")
    print(f"AMI ID: {ami_id} is already present in S3 bucket '{SOURCE_BUCKET}'")
except s3_client.exceptions.NoSuchKey:
    # Create a task to store the AMI in the S3 bucket
    store_task = ec2_client.create_store_image_task(ImageId=ami_id, Bucket=SOURCE_BUCKET)
    print(f"Store image task created with ID: {store_task['TaskId']}")

    # Wait for the image to be stored in S3
    wait_for_task_completion(ec2_client, ami_id)
    print(f"Image stored in S3 bucket '{SOURCE_BUCKET}' with ID: {ami_id}")

# Copy the AMI to local
local_file_path = os.path.join(LOCAL_PATH, f"{ami_id}.bin")
s3_client.download_file(SOURCE_BUCKET, f"{ami_id}.bin", local_file_path)
print(f"AMI ID: {ami_id} copied to local path: {LOCAL_PATH}")

# Delete the AMI from the S3 bucket
s3_client.delete_object(Bucket=SOURCE_BUCKET, Key=f"{ami_id}.bin")
print(f"AMI ID: {ami_id} deleted from S3 bucket: {SOURCE_BUCKET}")

# Save AMI ID and name to files
with open("ami_id.txt", "w") as f:
    f.write(ami_id)
with open("ami_name.txt", "w") as f:
    f.write(AMI_NAME)

# Copy the AMI to the destination bucket in another region
s3_client_dest = session.client('s3', region_name=DEST_REGION)
s3_client_dest.upload_file(local_file_path, DEST_BUCKET, f"{ami_id}.bin")
print(f"AMI ID: {ami_id} copied to S3 bucket '{DEST_BUCKET}' in region '{DEST_REGION}'")

# Wait for the AMI to become available in the destination bucket
wait_for_s3_file(s3_client_dest, DEST_BUCKET, f"{ami_id}.bin")
print(f"AMI ID: {ami_id} is available in S3 bucket '{DEST_BUCKET}'")

# Create an image restore task in the destination region
ec2_client_dest = session.client('ec2', region_name=DEST_REGION)
restore_task = ec2_client_dest.create_restore_image_task(Bucket=DEST_BUCKET, ObjectKey=f"{ami_id}.bin", Name=AMI_NAME)
restore_task_id = restore_task['ImageId']
print(f"Image restore task created with ID: {restore_task_id} in progress in region '{DEST_REGION}'")

# Wait for the AMI to become available in the destination region
wait_for_ami(ec2_client_dest, restore_task_id)
print("AMI restoration is completed")
print(f"RESTORE_TASK_ID = {restore_task_id}")

# Clear local path
print(f"Deleting: {ami_id} from local")
os.remove(local_file_path)

# Delete object from the destination S3 bucket
print("Deleting object from S3 destination bucket")
s3_client_dest.delete_object(Bucket=DEST_BUCKET, Key=f"{ami_id}.bin")
