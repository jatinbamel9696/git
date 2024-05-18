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
#!/bin/bash

# Define variables
AMI_NAME="test-image"
REGION="us-east-1"
SOURCE_BUCKET="test-j3"
LOCAL_PATH="${WORKSPACE}"

# Get the latest AMI ID
AMI_ID=$(aws ec2 describe-images --owners self --region "${REGION}" --filters "Name=name,Values=${AMI_NAME}" --query 'reverse(sort_by(Images, &CreationDate))[0].ImageId' --output text)
echo "Latest AMI ID for '${AMI_NAME}' in '${REGION}': ${AMI_ID}"

# Check if the AMI is already present in the source S3 bucket
if aws s3api head-object --bucket "${SOURCE_BUCKET}" --key "${AMI_ID}.bin" --region "${REGION}" 2>/dev/null; then
  echo "AMI ID: ${AMI_ID} is already present in S3 bucket '${SOURCE_BUCKET}'"
else
  # Create an image store task in the source S3 bucket
  STORE_TASK_ID=$(aws ec2 create-store-image-task --region "${REGION}" --image-id "${AMI_ID}" --bucket "${SOURCE_BUCKET}" --output text)
  echo "Store image task created with ID: ${STORE_TASK_ID}"

  # Wait for the image to be stored in S3 (optional)
  aws ec2 wait image-exists --region "${REGION}" --image-ids "${AMI_ID}"
  echo "Image stored in S3 bucket '${SOURCE_BUCKET}' with ID: ${AMI_ID}"
fi

# Export the AMI_ID variable
export AMI_ID
export AMI_NAME

# Copy the AMI to local using aws s3 cp command
aws s3 cp "s3://${SOURCE_BUCKET}/${AMI_ID}.bin" "${LOCAL_PATH}" --region "${REGION}"
echo "AMI ID: ${AMI_ID} copied to local path: ${LOCAL_PATH}"
ls -la "${WORKSPACE}"


# Delete the AMI from the S3 bucket
# aws s3api delete-object --bucket "${SOURCE_BUCKET}" --key "${AMI_ID}.bin" --region "${REGION}"
# echo "AMI ID: ${AMI_ID} deleted from S3 bucket: ${SOURCE_BUCKET}"


# Assume the role for China account
assume_role "$CHINA_ROLE_TO_ASSUME" "$CHINA_AWS_REGION"

# Run your China account operations here

# Example: List S3 buckets in the China account
echo "List of S3 buckets in the China account:"
aws s3 ls

# End of script
