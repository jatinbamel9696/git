#!/bin/bash

# Function to assume an AWS role and export credentials
assume_role() {
  local role_arn="$1"
  local aws_region="$2"
  local session_name="AssumeRoleSession"

  # Assume the role and capture the credentials
  CREDS=$(aws sts assume-role --role-arn "$role_arn" --role-session-name "$session_name" --region "$aws_region" --output json)
  
  # Export the assumed credentials
  export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | grep -o '"AccessKeyId": "[^"]*' | cut -d'"' -f4)
  export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": "[^"]*' | cut -d'"' -f4)
  export AWS_SESSION_TOKEN=$(echo "$CREDS" | grep -o '"SessionToken": "[^"]*' | cut -d'"' -f4)
}
# Set the role ARN and AWS regions
GLOBAL_ROLE_TO_ASSUME="arn:aws:iam::992382823608:role/assume-role"
GLOBAL_AWS_REGION="us-east-1"

CHINA_ROLE_TO_ASSUME="arn:aws:iam::992382823608:role/assume-role-china"
CHINA_AWS_REGION="us-west-1"

# Assume the role for global account
assume_role "$GLOBAL_ROLE_TO_ASSUME" "$GLOBAL_AWS_REGION"

# Run your global account operations here
get_latest_ami_id() {
  local ami_name=$1
  local region=$2
  aws ec2 describe-images --owners self --region "${region}" --filters "Name=name,Values=${ami_name}" --query 'reverse(sort_by(Images, &CreationDate))[0].ImageId' --output text
}

# Define variables for the first account
AMI_NAME="test-image"
REGION="us-east-1"
SOURCE_BUCKET="test-j3"
LOCAL_PATH="."
#FIRST_ACCOUNT_ROLE_ARN="arn:aws:iam::992382823608:role/assume-role"

# Assume role for the first account
#assume_role "$FIRST_ACCOUNT_ROLE_ARN" "FirstAccountSession"

# Get the latest AMI ID
AMI_ID=$(get_latest_ami_id "${AMI_NAME}" "${REGION}")

# Check if the AMI ID is empty
if [ -z "$AMI_ID" ]; then
  echo "Error: No AMI found with name '${AMI_NAME}' in region '${REGION}'"
  exit 1
fi

echo "Latest AMI ID for '${AMI_NAME}' in '${REGION}': ${AMI_ID}"

# Check if the AMI is already present in the source S3 bucket
if aws s3api head-object --bucket "${SOURCE_BUCKET}" --key "${AMI_ID}.bin" --region "${REGION}" 2>/dev/null; then
  echo "AMI ID: ${AMI_ID} is already present in S3 bucket '${SOURCE_BUCKET}'"
else
  # Create a task to store the AMI in the S3 bucket
  STORE_TASK_ID=$(aws ec2 create-store-image-task --region "${REGION}" --image-id "${AMI_ID}" --bucket "${SOURCE_BUCKET}" --output text)
  echo "Store image task created with ID: ${STORE_TASK_ID}"

  # Wait for the image to be stored in S3
  while [ "$(aws ec2 describe-store-image-tasks --region "${REGION}" --store-task-ids "${STORE_TASK_ID}"  --query 'StoreImageTasks[0].Status' --output text)" != "completed" ]; do
    sleep 30
  done

  echo "Image stored in S3 bucket '${SOURCE_BUCKET}' with ID: ${AMI_ID}"
fi

# Copy the AMI to local using aws s3 cp command
aws s3 cp "s3://${SOURCE_BUCKET}/${AMI_ID}.bin" "${LOCAL_PATH}" --region "${REGION}"
echo "AMI ID: ${AMI_ID} copied to local path: ${LOCAL_PATH}"
ls -la ${LOCAL_PATH}

# Example: List S3 buckets in the global account
echo "List of S3 buckets in the global account:"
aws s3 ls test-j3

# Assume the role for China account
assume_role "$CHINA_ROLE_TO_ASSUME" "$CHINA_AWS_REGION"

# Run your China account operations here

# Example: List S3 buckets in the China account
echo "List of S3 buckets in the China account:"
aws s3 ls

# End of script
