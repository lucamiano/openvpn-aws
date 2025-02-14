#!/bin/bash

# Check if region parameter is provided
if [ -z "$1" ]; then
  echo "You must specify a region."
  exit 1
fi

# Configuration variables
REGION=$1  # Accept region as a parameter
KEY_NAME="ec2-vpn-keypair-$REGION"
SECURITY_GROUP_NAME="OpenVPN-SG-$REGION"

# Get the most recently launched instance that is not terminated
INSTANCE_ID=$(aws ec2 describe-instances --region "$REGION" \
  --query "Reservations[].Instances[?State.Name!='terminated'] | sort_by(@, &LaunchTime)[-1].InstanceId" --output text)

if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
  echo "Terminating the most recently launched EC2 instance: $INSTANCE_ID"

  # Terminate the instance
  aws ec2 terminate-instances --region "$REGION" --instance-ids "$INSTANCE_ID"

  # Wait for termination
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$INSTANCE_ID"
  echo "EC2 instance $INSTANCE_ID terminated."
else
  echo "No active EC2 instances found to terminate."
fi

# Check if the Security Group exists
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region "$REGION" --query "SecurityGroups[?GroupName=='$SECURITY_GROUP_NAME'].GroupId" --output text)
if [ "$SECURITY_GROUP_ID" != "None" ]; then
  echo "Deleting Security Group with ID: $SECURITY_GROUP_ID"
  aws ec2 delete-security-group --region "$REGION" --group-id "$SECURITY_GROUP_ID"
  echo "Security Group $SECURITY_GROUP_ID deleted."
else
  echo "No Security Group found to delete."
fi

# Check if SSH key exists and delete it
EXISTING_KEY=$(aws ec2 describe-key-pairs --region "$REGION" --query "KeyPairs[?KeyName=='$KEY_NAME'].KeyName" --output text)
if [ "$EXISTING_KEY" != "None" ]; then
  echo "Deleting SSH Key Pair: $KEY_NAME"
  aws ec2 delete-key-pair --region "$REGION" --key-name "$KEY_NAME"
  echo "SSH Key Pair $KEY_NAME deleted."
else
  echo "No SSH Key Pair found to delete."
fi

# Optionally, delete the key pair file if it exists
if [ -f "$KEY_NAME.pem" ]; then
  rm "$KEY_NAME.pem"
  echo "Deleted local SSH private key file $KEY_NAME.pem."
else
  echo "No local SSH private key file found."
fi

echo "Cleanup completed."

