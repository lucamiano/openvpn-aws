#!/bin/bash

# Check if region parameter is provided
if [ -z "$1" ]; then
  echo "You must specify a region. You can also configure your region by running \"aws configure\"."
  exit 1
fi

# Configuration variables
REGION=$1  # Accept region as a parameter
INSTANCE_TYPE="t3.micro"
KEY_NAME="ec2-vpn-keypair-$REGION"
SECURITY_GROUP_NAME="OpenVPN-SG-$REGION"

# Get the latest Ubuntu 22.04 LTS AMI ID dynamically
AMI_ID=$(aws ec2 describe-images --region "$REGION" --owners "amazon" --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text)
if [ -z "$AMI_ID" ] || [ "$AMI_ID" == "None" ]; then
  echo "Failed to retrieve AMI ID. Check your AWS credentials and region."
  exit 1
fi
echo "Using AMI ID: $AMI_ID"

# Check if SSH key already exists
EXISTING_KEY=$(aws ec2 describe-key-pairs --region "$REGION" --query "KeyPairs[?KeyName=='$KEY_NAME'].KeyName" --output text)
if [ -z "$EXISTING_KEY" ]; then
  # Create SSH key if it doesn't exist
  aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" --query "KeyMaterial" --output text > "$KEY_NAME.pem"
  chmod 400 "$KEY_NAME.pem"
  echo "SSH key created and saved as $KEY_NAME.pem"
else
  echo "SSH key $KEY_NAME already exists, using existing key."
fi

# Check if Security Group exists
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region "$REGION" --query "SecurityGroups[?GroupName=='$SECURITY_GROUP_NAME'].GroupId" --output text)
if [ -z "$SECURITY_GROUP_ID" ]; then
  # Create Security Group if it doesn't exist
  SECURITY_GROUP_ID=$(aws ec2 create-security-group --region "$REGION" --group-name "$SECURITY_GROUP_NAME" --description "Security group for OpenVPN and SSH" --query 'GroupId' --output text)
  echo "Security Group created with ID: $SECURITY_GROUP_ID"

  # Configure Security Group rules
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SECURITY_GROUP_ID" --protocol udp --port 1194 --cidr 0.0.0.0/0
  echo "Security Group rules configured"
else
  echo "Security Group $SECURITY_GROUP_NAME already exists with ID: $SECURITY_GROUP_ID"
fi

# Get the default VPC ID and its CIDR block
DEFAULT_VPC_INFO=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=isDefault,Values=true" --query "Vpcs[0].[VpcId, CidrBlock]" --output text)
if [ -z "$DEFAULT_VPC_INFO" ]; then
  echo "No default VPC found in region $REGION. Please create a VPC and try again."
  exit 1
fi
DEFAULT_VPC_ID=$(echo "$DEFAULT_VPC_INFO" | awk '{print $1}')
DEFAULT_VPC_CIDR=$(echo "$DEFAULT_VPC_INFO" | awk '{print $2}')
echo "Default VPC ID: $DEFAULT_VPC_ID"
echo "Default VPC CIDR: $DEFAULT_VPC_CIDR"

# Check if a subnet exists in the default VPC
SUBNET_ID=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" --query "Subnets[0].SubnetId" --output text)
if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" == "None" ]; then
  echo "No subnet found in the default VPC. Creating a new subnet..."

  # Get the first availability zone in the region
  AVAILABILITY_ZONE=$(aws ec2 describe-availability-zones --region "$REGION" --query "AvailabilityZones[0].ZoneName" --output text)
  if [ -z "$AVAILABILITY_ZONE" ]; then
    echo "No availability zone found in region $REGION. Please check your region settings."
    exit 1
  fi

  # Calculate a valid subnet CIDR block based on the VPC CIDR
  if [[ "$DEFAULT_VPC_CIDR" == "10.0.0.0/16" ]]; then
    SUBNET_CIDR="10.0.1.0/24"
  elif [[ "$DEFAULT_VPC_CIDR" == "172.31.0.0/16" ]]; then
    SUBNET_CIDR="172.31.1.0/24"
  elif [[ "$DEFAULT_VPC_CIDR" == "192.168.0.0/16" ]]; then
    SUBNET_CIDR="192.168.1.0/24"
  else
    echo "Unsupported VPC CIDR block: $DEFAULT_VPC_CIDR. Please manually specify a subnet CIDR."
    exit 1
  fi

  # Create a new subnet in the default VPC
  SUBNET_ID=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$DEFAULT_VPC_ID" --cidr-block "$SUBNET_CIDR" --availability-zone "$AVAILABILITY_ZONE" --query "Subnet.SubnetId" --output text)
  if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" == "None" ]; then
    echo "Failed to create subnet. Check your AWS settings."
    exit 1
  fi
  echo "Created new subnet with ID: $SUBNET_ID and CIDR: $SUBNET_CIDR"
else
  echo "Using existing subnet with ID: $SUBNET_ID"
fi

# Launch EC2 instance
INSTANCE_ID=$(aws ec2 run-instances --region "$REGION" --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" --subnet-id "$SUBNET_ID" --key-name "$KEY_NAME" --security-group-ids "$SECURITY_GROUP_ID" --query 'Instances[0].InstanceId' --associate-public-ip-address --output text)
if [ -z "$INSTANCE_ID" ]; then
  echo "Failed to launch instance. Check your AWS settings."
  exit 1
fi
echo "Instance launched with ID: $INSTANCE_ID"

# Wait for the instance to be running
echo "Waiting for the instance to start..."
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
echo "The instance is now running"

# Retrieve public IP
PUBLIC_IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
if [ -z "$PUBLIC_IP" ]; then
  echo "Failed to retrieve public IP."
  exit 1
fi
echo "The instance is accessible at IP: $PUBLIC_IP"

# Wait for SSH to be available
echo "Waiting for SSH to be available..."
until ssh -o StrictHostKeyChecking=no -i "$KEY_NAME.pem" ubuntu@$PUBLIC_IP 'echo SSH is ready'; do
  sleep 10
  echo "Retrying SSH connection..."
done

echo "Installing Docker and OpenVPN..."
ssh -o StrictHostKeyChecking=no -i "$KEY_NAME.pem" ubuntu@$PUBLIC_IP << 'EOF'
export PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
sudo apt-get update -y
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $(whoami)
newgrp docker
sudo curl -L "https://github.com/docker/compose/releases/download/v2.6.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
mkdir ~/openvpn-docker
cd ~/openvpn-docker

cat <<EOL > docker-compose.yaml
version: '3.8'
services:
  openvpn:
    image: kylemanna/openvpn
    container_name: openvpn-server
    cap_add:
      - NET_ADMIN
    ports:
      - "1194:1194/udp"
    volumes:
      - ./openvpn_data:/etc/openvpn
    environment:
      - OVPN_DATA=ovpn-data
      - OVPN_SERVER_URL=udp://$PUBLIC_IP
    restart: unless-stopped
    command: ovpn_run
EOL

# Now pass the public IP in the -u option for the ovpn_genconfig
docker-compose run --rm openvpn ovpn_genconfig -u udp://$PUBLIC_IP
EOF

ssh -o StrictHostKeyChecking=no -i "$KEY_NAME.pem" ubuntu@$PUBLIC_IP << 'EOF'
export PASSPHRASE="abcde12345"
cd ~/openvpn-docker
sudo apt-get install expect -y
expect <<EOL
spawn docker-compose run -tt --rm openvpn ovpn_initpki
set timeout -1
expect "Enter New CA Key Passphrase:" { send "$PASSPHRASE\r" }
expect "Re-Enter New CA Key Passphrase:" { send "$PASSPHRASE\r" }
expect "Common Name" { send "ubuntu\r" }
expect "Enter pass phrase for /etc/openvpn/pki/private/ca.key:" { send "$PASSPHRASE\r" }
expect "Enter pass phrase for /etc/openvpn/pki/private/ca.key:" { send "$PASSPHRASE\r" }
expect "CRL file:"
expect eof
EOL
EOF

ssh -o StrictHostKeyChecking=no -i "$KEY_NAME.pem" ubuntu@$PUBLIC_IP << 'EOF' 
cd ~/openvpn-docker
docker-compose up -d
EOF

echo "Docker and OpenVPN installation completed."
# Generate Client certificate and .ovpn file
echo "Generating Client certificate"
ssh -o StrictHostKeyChecking=no -i "$KEY_NAME.pem" ubuntu@$PUBLIC_IP << 'EOF'
export PASSPHRASE="abcde12345"
cd ~/openvpn-docker
expect <<EOL
spawn docker-compose run -tt --rm openvpn easyrsa build-client-full openvpn-client nopass
expect "Enter pass phrase for /etc/openvpn/pki/private/ca.key:" { send "$PASSPHRASE\r" }
expect eof
EOL
EOF

ssh -o StrictHostKeyChecking=no -i "$KEY_NAME.pem" ubuntu@$PUBLIC_IP << 'EOF'
cd ~/openvpn-docker
docker-compose run --rm openvpn ovpn_getclient openvpn-client > /home/ubuntu/openvpn-client.ovpn
echo "Certificate successfully generated"
EOF

# Retrieve the .ovpn file to your local machine
echo "Downloading the .ovpn file from EC2 instance..."
scp -i "$KEY_NAME.pem" ubuntu@$PUBLIC_IP:~/openvpn-client.ovpn ./openvpn-client.ovpn
echo "The .ovpn file has been downloaded to your local machine."

