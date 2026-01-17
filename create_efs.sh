#!/bin/bash


# ============== CONFIGURATION ==============
AWS_REGION="eu-west-1"
VPC_CIDR="10.0.0.0/16"
PRIVATE_SUBNET_1_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_2_CIDR="10.0.2.0/24"
VPN_CLIENT_CIDR="10.100.0.0/22"

# Certificate domain names (can be fictional)
CA_DOMAIN="ca.vpn.example.com"
SERVER_DOMAIN="server.vpn.example.com"
CLIENT_DOMAIN="client.vpn.example.com"

# Local paths
EASY_RSA_DIR="$HOME/easy-rsa"
VPN_CONFIG_FILE="$HOME/aws-vpn-config.ovpn"
VARIABLES_FILE="$HOME/aws-vpn-variables.sh"
EFS_MOUNT_POINT="/mnt/efs"
# ============================================

set -e

echo "=========================================="
echo "AWS VPN + EFS Creation Script"
echo "Region: $AWS_REGION"
echo "=========================================="

# Check prerequisites
echo ""
echo "Checking prerequisites..."

if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI not installed"
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo "ERROR: AWS CLI not configured. Run 'aws configure'"
    exit 1
fi

echo "Prerequisites OK"

#############################################
# STEP 1: Create VPC
#############################################
echo ""
echo "=========================================="
echo "STEP 1: Creating VPC..."
echo "=========================================="

VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $VPC_CIDR \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=vpn-vpc}]' \
    --region $AWS_REGION \
    --query 'Vpc.VpcId' \
    --output text)

echo "VPC created: $VPC_ID"

# Enable DNS hostnames
aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-hostnames \
    --region $AWS_REGION

echo "DNS hostnames enabled"

#############################################
# STEP 2: Create Subnets
#############################################
echo ""
echo "=========================================="
echo "STEP 2: Creating Subnets..."
echo "=========================================="

# Get availability zones
AZ1=$(aws ec2 describe-availability-zones \
    --region $AWS_REGION \
    --query 'AvailabilityZones[0].ZoneName' \
    --output text)

AZ2=$(aws ec2 describe-availability-zones \
    --region $AWS_REGION \
    --query 'AvailabilityZones[1].ZoneName' \
    --output text)

echo "Using AZs: $AZ1, $AZ2"

# Create private subnet 1
PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $PRIVATE_SUBNET_1_CIDR \
    --availability-zone $AZ1 \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=vpn-private-subnet-1}]' \
    --region $AWS_REGION \
    --query 'Subnet.SubnetId' \
    --output text)

echo "Private Subnet 1 created: $PRIVATE_SUBNET_1"

# Create private subnet 2
PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $PRIVATE_SUBNET_2_CIDR \
    --availability-zone $AZ2 \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=vpn-private-subnet-2}]' \
    --region $AWS_REGION \
    --query 'Subnet.SubnetId' \
    --output text)

echo "Private Subnet 2 created: $PRIVATE_SUBNET_2"

#############################################
# STEP 3: Create Security Groups
#############################################
echo ""
echo "=========================================="
echo "STEP 3: Creating Security Groups..."
echo "=========================================="

# VPN Security Group
VPN_SG_ID=$(aws ec2 create-security-group \
    --group-name vpn-endpoint-sg \
    --description "Security group for Client VPN endpoint" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' \
    --output text)

echo "VPN Security Group created: $VPN_SG_ID"

aws ec2 authorize-security-group-ingress \
    --group-id $VPN_SG_ID \
    --protocol -1 \
    --cidr $VPN_CLIENT_CIDR \
    --region $AWS_REGION

# Resources Security Group
RESOURCES_SG_ID=$(aws ec2 create-security-group \
    --group-name private-resources-sg \
    --description "Security group for private resources" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' \
    --output text)

echo "Resources Security Group created: $RESOURCES_SG_ID"

aws ec2 authorize-security-group-ingress \
    --group-id $RESOURCES_SG_ID \
    --protocol -1 \
    --cidr $VPN_CLIENT_CIDR \
    --region $AWS_REGION

# EFS Security Group
EFS_SG_ID=$(aws ec2 create-security-group \
    --group-name efs-sg \
    --description "Security group for EFS" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' \
    --output text)

echo "EFS Security Group created: $EFS_SG_ID"

aws ec2 authorize-security-group-ingress \
    --group-id $EFS_SG_ID \
    --protocol tcp \
    --port 2049 \
    --cidr $VPN_CLIENT_CIDR \
    --region $AWS_REGION

aws ec2 authorize-security-group-ingress \
    --group-id $EFS_SG_ID \
    --protocol tcp \
    --port 2049 \
    --cidr $VPC_CIDR \
    --region $AWS_REGION

#############################################
# STEP 4: Generate Certificates
#############################################
echo ""
echo "=========================================="
echo "STEP 4: Generating Certificates..."
echo "=========================================="

# Install dependencies
sudo apt update
sudo apt install -y git openssl nfs-common openvpn

# Clone easy-rsa
rm -rf $EASY_RSA_DIR
git clone https://github.com/OpenVPN/easy-rsa.git $EASY_RSA_DIR
cd $EASY_RSA_DIR/easyrsa3

# Initialize PKI
./easyrsa init-pki

# Build CA
EASYRSA_REQ_CN="$CA_DOMAIN" ./easyrsa build-ca nopass

# Build server certificate
./easyrsa build-server-full $SERVER_DOMAIN nopass

# Build client certificate
./easyrsa build-client-full $CLIENT_DOMAIN nopass

echo "Certificates generated successfully"

#############################################
# STEP 5: Upload Certificates to ACM
#############################################
echo ""
echo "=========================================="
echo "STEP 5: Uploading Certificates to ACM..."
echo "=========================================="

cd $EASY_RSA_DIR/easyrsa3

# Upload server certificate
SERVER_CERT_ARN=$(aws acm import-certificate \
    --certificate fileb://pki/issued/$SERVER_DOMAIN.crt \
    --private-key fileb://pki/private/$SERVER_DOMAIN.key \
    --certificate-chain fileb://pki/ca.crt \
    --region $AWS_REGION \
    --query 'CertificateArn' \
    --output text)

echo "Server Certificate ARN: $SERVER_CERT_ARN"

# Upload client certificate
CLIENT_CERT_ARN=$(aws acm import-certificate \
    --certificate fileb://pki/issued/$CLIENT_DOMAIN.crt \
    --private-key fileb://pki/private/$CLIENT_DOMAIN.key \
    --certificate-chain fileb://pki/ca.crt \
    --region $AWS_REGION \
    --query 'CertificateArn' \
    --output text)

echo "Client Certificate ARN: $CLIENT_CERT_ARN"

#############################################
# STEP 6: Create VPN Endpoint
#############################################
echo ""
echo "=========================================="
echo "STEP 6: Creating VPN Endpoint..."
echo "=========================================="

VPN_ENDPOINT_ID=$(aws ec2 create-client-vpn-endpoint \
    --client-cidr-block "$VPN_CLIENT_CIDR" \
    --server-certificate-arn "$SERVER_CERT_ARN" \
    --authentication-options "Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn=$CLIENT_CERT_ARN}" \
    --connection-log-options "Enabled=false" \
    --vpc-id "$VPC_ID" \
    --security-group-ids "$VPN_SG_ID" \
    --split-tunnel \
    --tag-specifications 'ResourceType=client-vpn-endpoint,Tags=[{Key=Name,Value=my-client-vpn}]' \
    --region $AWS_REGION \
    --query 'ClientVpnEndpointId' \
    --output text)

echo "VPN Endpoint created: $VPN_ENDPOINT_ID"

#############################################
# STEP 7: Associate VPN with Subnet
#############################################
echo ""
echo "=========================================="
echo "STEP 7: Associating VPN with Subnet..."
echo "=========================================="

ASSOCIATION_ID=$(aws ec2 associate-client-vpn-target-network \
    --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
    --subnet-id "$PRIVATE_SUBNET_1" \
    --region $AWS_REGION \
    --query 'AssociationId' \
    --output text)

echo "Association ID: $ASSOCIATION_ID"

# Wait for association
echo "Waiting for association... (5-10 minutes)"
while true; do
    STATUS=$(aws ec2 describe-client-vpn-target-networks \
        --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
        --region $AWS_REGION \
        --query 'ClientVpnTargetNetworks[0].Status.Code' \
        --output text)
    echo "  Status: $STATUS"
    if [ "$STATUS" = "associated" ]; then
        echo "Association complete!"
        break
    fi
    sleep 30
done

#############################################
# STEP 8: Add Authorization Rules
#############################################
echo ""
echo "=========================================="
echo "STEP 8: Adding Authorization Rules..."
echo "=========================================="

aws ec2 authorize-client-vpn-ingress \
    --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
    --target-network-cidr "$VPC_CIDR" \
    --authorize-all-groups \
    --region $AWS_REGION

echo "Authorization rule added"

#############################################
# STEP 9: Download and Configure VPN Client
#############################################
echo ""
echo "=========================================="
echo "STEP 9: Configuring VPN Client..."
echo "=========================================="

# Download config
aws ec2 export-client-vpn-client-configuration \
    --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
    --region $AWS_REGION \
    --output text > $VPN_CONFIG_FILE

# Add certificates to config
cd $EASY_RSA_DIR/easyrsa3

echo "" >> $VPN_CONFIG_FILE
echo "<cert>" >> $VPN_CONFIG_FILE
cat pki/issued/$CLIENT_DOMAIN.crt >> $VPN_CONFIG_FILE
echo "</cert>" >> $VPN_CONFIG_FILE

echo "" >> $VPN_CONFIG_FILE
echo "<key>" >> $VPN_CONFIG_FILE
cat pki/private/$CLIENT_DOMAIN.key >> $VPN_CONFIG_FILE
echo "</key>" >> $VPN_CONFIG_FILE

echo "VPN config saved to: $VPN_CONFIG_FILE"

#############################################
# STEP 10: Create EFS
#############################################
echo ""
echo "=========================================="
echo "STEP 10: Creating EFS..."
echo "=========================================="

EFS_ID=$(aws efs create-file-system \
    --performance-mode generalPurpose \
    --throughput-mode bursting \
    --encrypted \
    --tags Key=Name,Value=my-vpn-efs \
    --region $AWS_REGION \
    --query 'FileSystemId' \
    --output text)

echo "EFS created: $EFS_ID"

# Wait for EFS to be available
echo "Waiting for EFS to become available..."
while true; do
    STATUS=$(aws efs describe-file-systems \
        --file-system-id $EFS_ID \
        --region $AWS_REGION \
        --query 'FileSystems[0].LifeCycleState' \
        --output text)
    echo "  Status: $STATUS"
    if [ "$STATUS" = "available" ]; then
        echo "EFS is available!"
        break
    fi
    sleep 5
done

#############################################
# STEP 11: Create EFS Mount Targets
#############################################
echo ""
echo "=========================================="
echo "STEP 11: Creating EFS Mount Targets..."
echo "=========================================="

MOUNT_TARGET_1=$(aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id $PRIVATE_SUBNET_1 \
    --security-groups $EFS_SG_ID \
    --region $AWS_REGION \
    --query 'MountTargetId' \
    --output text)

echo "Mount Target 1 created: $MOUNT_TARGET_1"

MOUNT_TARGET_2=$(aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id $PRIVATE_SUBNET_2 \
    --security-groups $EFS_SG_ID \
    --region $AWS_REGION \
    --query 'MountTargetId' \
    --output text)

echo "Mount Target 2 created: $MOUNT_TARGET_2"

# Wait for mount targets
echo "Waiting for mount targets to become available..."
while true; do
    STATUS=$(aws efs describe-mount-targets \
        --file-system-id $EFS_ID \
        --region $AWS_REGION \
        --query 'MountTargets[0].LifeCycleState' \
        --output text)
    echo "  Status: $STATUS"
    if [ "$STATUS" = "available" ]; then
        echo "Mount targets are available!"
        break
    fi
    sleep 10
done

# Get EFS IP
EFS_IP=$(aws efs describe-mount-targets \
    --file-system-id $EFS_ID \
    --region $AWS_REGION \
    --query 'MountTargets[0].IpAddress' \
    --output text)

echo "EFS IP: $EFS_IP"

#############################################
# STEP 12: Connect VPN
#############################################
echo ""
echo "=========================================="
echo "STEP 12: Connecting to VPN..."
echo "=========================================="

# Kill any existing OpenVPN
sudo killall openvpn 2>/dev/null || true
sleep 2

# Connect to VPN in background
sudo openvpn --config $VPN_CONFIG_FILE --daemon

echo "Waiting for VPN connection..."
sleep 15

# Check connection
if ip addr show tun0 &> /dev/null; then
    echo "VPN connected successfully!"
    ip addr show tun0 | grep inet
else
    echo "ERROR: VPN connection failed"
    echo "Try manually: sudo openvpn --config $VPN_CONFIG_FILE"
    exit 1
fi

#############################################
# STEP 13: Mount EFS
#############################################
echo ""
echo "=========================================="
echo "STEP 13: Mounting EFS..."
echo "=========================================="

# Create mount point
sudo mkdir -p $EFS_MOUNT_POINT

# Mount EFS
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $EFS_IP:/ $EFS_MOUNT_POINT

# Verify mount
if mount | grep -q $EFS_MOUNT_POINT; then
    echo "EFS mounted successfully!"
    df -h $EFS_MOUNT_POINT
else
    echo "ERROR: EFS mount failed"
    exit 1
fi

# Test write
echo "Testing EFS write..."
sudo touch $EFS_MOUNT_POINT/test-file.txt
echo "Hello from VPN client - $(date)" | sudo tee $EFS_MOUNT_POINT/test-file.txt
cat $EFS_MOUNT_POINT/test-file.txt
echo "EFS read/write test successful!"

#############################################
# STEP 14: Save Variables
#############################################
echo ""
echo "=========================================="
echo "STEP 14: Saving Variables..."
echo "=========================================="

cat << EOF > $VARIABLES_FILE
# AWS VPN + EFS Variables
# Generated on: $(date)

export AWS_REGION="$AWS_REGION"

# VPC
export VPC_ID="$VPC_ID"
export PRIVATE_SUBNET_1="$PRIVATE_SUBNET_1"
export PRIVATE_SUBNET_2="$PRIVATE_SUBNET_2"

# Security Groups
export VPN_SG_ID="$VPN_SG_ID"
export RESOURCES_SG_ID="$RESOURCES_SG_ID"
export EFS_SG_ID="$EFS_SG_ID"

# VPN
export VPN_ENDPOINT_ID="$VPN_ENDPOINT_ID"
export ASSOCIATION_ID="$ASSOCIATION_ID"
export SERVER_CERT_ARN="$SERVER_CERT_ARN"
export CLIENT_CERT_ARN="$CLIENT_CERT_ARN"

# EFS
export EFS_ID="$EFS_ID"
export EFS_IP="$EFS_IP"
export MOUNT_TARGET_1="$MOUNT_TARGET_1"
export MOUNT_TARGET_2="$MOUNT_TARGET_2"

# Paths
export VPN_CONFIG_FILE="$VPN_CONFIG_FILE"
export EFS_MOUNT_POINT="$EFS_MOUNT_POINT"
EOF

echo "Variables saved to: $VARIABLES_FILE"

#############################################
# SUMMARY
#############################################
echo ""
echo "=========================================="
echo "SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "Resources created:"
echo "  VPC:              $VPC_ID"
echo "  Subnet 1:         $PRIVATE_SUBNET_1"
echo "  Subnet 2:         $PRIVATE_SUBNET_2"
echo "  VPN Endpoint:     $VPN_ENDPOINT_ID"
echo "  EFS:              $EFS_ID"
echo "  EFS IP:           $EFS_IP"
echo ""
echo "Local configuration:"
echo "  VPN Config:       $VPN_CONFIG_FILE"
echo "  Variables:        $VARIABLES_FILE"
echo "  EFS Mount:        $EFS_MOUNT_POINT"
echo ""
echo "Useful commands:"
echo "  Reconnect VPN:    sudo openvpn --config $VPN_CONFIG_FILE --daemon"
echo "  Remount EFS:      sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $EFS_IP:/ $EFS_MOUNT_POINT"
echo "  Check VPN:        ip addr show tun0"
echo "  Check EFS:        df -h $EFS_MOUNT_POINT"
echo "  Load variables:   source $VARIABLES_FILE"
echo ""
echo "To cleanup, fill IDs in cleanup.sh from: $VARIABLES_FILE"
echo "=========================================="