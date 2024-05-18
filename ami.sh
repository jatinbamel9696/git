#!/bin/bash

# Function to assume an AWS role
assume_role() {
  local role_arn=$1
  local session_name=$2
  CREDS=$(aws sts assume-role --role-arn "$role_arn" --role-session-name "$session_name" --output json)
  AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
  AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
  AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')
}

# Function to get the latest AMI ID
get_latest_ami_id() {
  local ami_name=$1
  local region=$2
  aws ec2 describe-images --owners self --region "${region}" --filters "Name=name,Values=${ami_name}" --query 'reverse(sort_by(Images, &CreationDate))[0].ImageId' --output text
}

# Function to wait for a store image task to complete
wait_for_store_image_task() {
  local ami_id=$1
  local region=$2
  while [ "$(aws ec2 describe-store-image-tasks --region "${region}" --image-ids "${ami_id}" --query 'StoreImageTaskResults[0].StoreTaskState' --output text)" != "Completed" ]; do
    sleep 30
  done
}

# Function to wait for a file to be available in S3
wait_for_s3_file() {
  local bucket=$1
  local key=$2
  local profile=$3
  while ! aws s3 ls "s3://${bucket}/${key}" --profile "${profile}" >/dev/null 2>&1; do
    sleep 30
  done
}

# Function to wait for an AMI to be available
wait_for_ami() {
  local ami_id=$1
  local region=$2
  local profile=$3
  while [ "$(aws ec2 describe-images --image-ids "${ami_id}" --query 'Images[0].State' --output text --region "${region}" --profile "${profile}")" != "available" ]; do
    sleep 30
  done
}

# Function to share an AMI with specified accounts
share_ami() {
  local ami_id=$1
  local accounts=("${!2}")
  local profile=$3
  for AWS_ACCOUNT_ID in "${accounts[@]}"; do
    aws ec2 modify-image-attribute --image-id "${ami_id}" --launch-permission "Add=[{UserId=${AWS_ACCOUNT_ID}}]" --profile "${profile}"
  done
}

# Define variables for the first account
AMI_NAME="test"
REGION="us-east-1"
SOURCE_BUCKET="test-j3"
LOCAL_PATH="/data"
FIRST_ACCOUNT_ROLE_ARN="arn:aws:iam::992382823608:role/assume-role"
FIRST_ACCOUNT_SESSION="FirstAccountSession"

# Assume role for the first account
assume_role "$FIRST_ACCOUNT_ROLE_ARN" "$FIRST_ACCOUNT_SESSION"

# Get the latest AMI ID
AMI_ID=$(get_latest_ami_id "${AMI_NAME}" "${REGION}")
echo "Latest AMI ID for '${AMI_NAME}' in '${REGION}': ${AMI_ID}"

# Check if the AMI is already present in the source S3 bucket
if aws s3api head-object --bucket "${SOURCE_BUCKET}" --key "${AMI_ID}.bin" --region "${REGION}" 2>/dev/null; then
  echo "AMI ID: ${AMI_ID} is already present in S3 bucket '${SOURCE_BUCKET}'"
else
  # Create a task to store the AMI in the S3 bucket
  STORE_TASK_ID=$(aws ec2 create-store-image-task --region "${REGION}" --image-id "${AMI_ID}" --bucket "${SOURCE_BUCKET}" --output text)
  echo "Store image task created with ID: ${STORE_TASK_ID}"

  # Wait for the image to be stored in S3
  wait_for_store_image_task "${AMI_ID}" "${REGION}"
  echo "Image stored in S3 bucket '${SOURCE_BUCKET}' with ID: ${AMI_ID}"
fi

# Copy the AMI to local using aws s3 cp command
aws s3 cp "s3://${SOURCE_BUCKET}/${AMI_ID}.bin" "${LOCAL_PATH}" --region "${REGION}"
echo "AMI ID: ${AMI_ID} copied to local path: ${LOCAL_PATH}"

# Delete the AMI from the S3 bucket
aws s3api delete-object --bucket "${SOURCE_BUCKET}" --key "${AMI_ID}.bin" --region "${REGION}"
echo "AMI ID: ${AMI_ID} deleted from S3 bucket: ${SOURCE_BUCKET}"

# Export the AMI_ID and AMI_NAME to files
echo "${AMI_ID}" > ami_id.txt
echo "${AMI_NAME}" > ami_name.txt

# Define variables for the second account
CN_REGION="cn-north-1"
CHINA_BUCKET="test-j3-1"
SHARE_REGION="us-east-2"
SHARE_ACCOUNTS=()
SECOND_ACCOUNT_ROLE_ARN="arn:aws:iam::992382823608:role/assume-role"
SECOND_ACCOUNT_SESSION="SecondAccountSession"

# Assume role for the second account
assume_role "$SECOND_ACCOUNT_ROLE_ARN" "$SECOND_ACCOUNT_SESSION"

# Import the AMI_ID and AMI_NAME variables from files
AMI_ID=$(cat ami_id.txt)
AMI_NAME=$(cat ami_name.txt)

echo "Latest AMI ID for '${AMI_NAME}': ${AMI_ID}"

# Copy the AMI to the China account using assumed role credentials
aws s3 cp "${LOCAL_PATH}/${AMI_ID}.bin" "s3://${CHINA_BUCKET}/${AMI_ID}.bin" --region "${CN_REGION}"
echo "AMI ID: ${AMI_ID} copied to S3 bucket '${CHINA_BUCKET}'"

# Wait for the AMI to become available in the China account
wait_for_s3_file "${CHINA_BUCKET}" "${AMI_ID}.bin" ""

# Create an image restore task in China account
RESTORE_TASK_ID=$(aws ec2 create-restore-image-task --bucket "${CHINA_BUCKET}" --object-key "${AMI_ID}.bin" --name "${AMI_NAME}" --output text --query 'ImageId')
echo "Image restore task created with ID: ${RESTORE_TASK_ID} is in progress"

# Wait for the AMI to become available in the China account
wait_for_ami "${RESTORE_TASK_ID}" "${CN_REGION}" ""

# Share the restored AMI in another region
echo "Copying to another region started"
SHARED_AMI_ID=$(aws ec2 copy-image --source-image-id "${RESTORE_TASK_ID}" --source-region "${CN_REGION}" --region "${SHARE_REGION}" --name "${AMI_NAME}" --copy-image-tags --output text --query 'ImageId')

# Wait for the AMI to become available in the shared region
wait_for_ami "${SHARED_AMI_ID}" "${SHARE_REGION}" ""
echo "AMI ${SHARED_AMI_ID} is available in the ${SHARE_REGION}"

# Share the restored AMI with specified accounts in China region - cn-north-1
echo "Sharing AMI ${RESTORE_TASK_ID} in China region - cn-north-1"
share_ami "${RESTORE_TASK_ID}" SHARE_ACCOUNTS[@] ""

