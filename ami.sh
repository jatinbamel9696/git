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

# Example: List S3 buckets in the global account
echo "List of S3 buckets in the global account:"
aws s3 ls

# Assume the role for China account
assume_role "$CHINA_ROLE_TO_ASSUME" "$CHINA_AWS_REGION"

# Run your China account operations here

# Example: List S3 buckets in the China account
echo "List of S3 buckets in the China account:"
aws s3 ls

# End of script
