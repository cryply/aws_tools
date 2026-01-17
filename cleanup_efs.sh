#!/bin/bash


# ============== FILL THESE IN ==============
AWS_REGION="eu-west-1"


# Replace vars below.
VPC_ID="vpc-"
PRIVATE_SUBNET_1="subnet-"
PRIVATE_SUBNET_2="subnet-"
PRIVATE_RESOURCES_SG_SG_ID="sg-"
EFS_SG_SG_ID="sg-"
VPN_ENDPOINT_SG_SG_ID="sg-"
VPN_ENDPOINT_ID=""
ASSOCIATION_ID="c"
EFS_ID=""
MOUNT_TARGET_1=""
MOUNT_TARGET_2=""

# ACM Certificates
SERVER_CERT_ARN=""
CLIENT_CERT_ARN=""



# ============================================

set -e

echo "=========================================="
echo "AWS VPN + EFS Cleanup Script"
echo "Region: $AWS_REGION"
echo "=========================================="

# Function to wait for resource deletion
wait_for_deletion() {
    local check_command="$1"
    local resource_name="$2"
    local max_attempts=30
    local attempt=0
    
    echo "Waiting for $resource_name to be deleted..."
    while [ $attempt -lt $max_attempts ]; do
        if ! eval "$check_command" 2>/dev/null; then
            echo "$resource_name deleted!"
            return 0
        fi
        attempt=$((attempt + 1))
        echo "  Still deleting... (attempt $attempt/$max_attempts)"
        sleep 10
    done
    echo "Warning: $resource_name may not be fully deleted"
    return 1
}

# Step 1: Unmount EFS
echo ""
echo "Step 1: Unmounting EFS..."
if mount | grep -q /mnt/efs; then
    sudo umount -f /mnt/efs 2>/dev/null || sudo umount -l /mnt/efs 2>/dev/null || true
    echo "EFS unmounted"
else
    echo "EFS not mounted, skipping"
fi

# Step 2: Delete EFS Mount Targets
echo ""
echo "Step 2: Deleting EFS mount targets..."
if [ -n "$MOUNT_TARGET_1" ]; then
    aws efs delete-mount-target \
        --mount-target-id $MOUNT_TARGET_1 \
        --region $AWS_REGION 2>/dev/null && echo "Mount target 1 deletion initiated" || echo "Mount target 1 already deleted or not found"
fi

if [ -n "$MOUNT_TARGET_2" ]; then
    aws efs delete-mount-target \
        --mount-target-id $MOUNT_TARGET_2 \
        --region $AWS_REGION 2>/dev/null && echo "Mount target 2 deletion initiated" || echo "Mount target 2 already deleted or not found"
fi

# Wait for mount targets to be deleted
if [ -n "$EFS_ID" ]; then
    echo "Waiting for mount targets to be deleted..."
    sleep 60
fi

# Step 3: Delete EFS File System
echo ""
echo "Step 3: Deleting EFS file system..."
if [ -n "$EFS_ID" ]; then
    aws efs delete-file-system \
        --file-system-id $EFS_ID \
        --region $AWS_REGION 2>/dev/null && echo "EFS deletion initiated" || echo "EFS already deleted or not found"
fi

# Step 4: Disassociate VPN Target Network
echo ""
echo "Step 4: Disassociating VPN target network..."
if [ -n "$VPN_ENDPOINT_ID" ] && [ -n "$ASSOCIATION_ID" ]; then
    aws ec2 disassociate-client-vpn-target-network \
        --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
        --association-id $ASSOCIATION_ID \
        --region $AWS_REGION 2>/dev/null && echo "VPN disassociation initiated" || echo "Already disassociated or not found"
    
    echo "Waiting for disassociation..."
    sleep 60
fi

# Step 5: Delete VPN Endpoint
echo ""
echo "Step 5: Deleting VPN endpoint..."
if [ -n "$VPN_ENDPOINT_ID" ]; then
    aws ec2 delete-client-vpn-endpoint \
        --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
        --region $AWS_REGION 2>/dev/null && echo "VPN endpoint deletion initiated" || echo "VPN endpoint already deleted or not found"
    
    echo "Waiting for VPN endpoint deletion... (this takes 2-3 minutes)"
    sleep 120
fi

# Step 6: Delete Security Groups
echo ""
echo "Step 6: Deleting security groups..."

if [ -n "$EFS_SG_ID" ]; then
    aws ec2 delete-security-group \
        --group-id $EFS_SG_ID \
        --region $AWS_REGION 2>/dev/null && echo "EFS security group deleted" || echo "EFS security group already deleted or not found"
fi

if [ -n "$VPN_SG_ID" ]; then
    aws ec2 delete-security-group \
        --group-id $VPN_SG_ID \
        --region $AWS_REGION 2>/dev/null && echo "VPN security group deleted" || echo "VPN security group already deleted or not found"
fi

if [ -n "$RESOURCES_SG_ID" ]; then
    aws ec2 delete-security-group \
        --group-id $RESOURCES_SG_ID \
        --region $AWS_REGION 2>/dev/null && echo "Resources security group deleted" || echo "Resources security group already deleted or not found"
fi

# Step 7: Delete Subnets
echo ""
echo "Step 7: Deleting subnets..."

if [ -n "$PRIVATE_SUBNET_1" ]; then
    aws ec2 delete-subnet \
        --subnet-id $PRIVATE_SUBNET_1 \
        --region $AWS_REGION 2>/dev/null && echo "Private subnet 1 deleted" || echo "Private subnet 1 already deleted or not found"
fi

if [ -n "$PRIVATE_SUBNET_2" ]; then
    aws ec2 delete-subnet \
        --subnet-id $PRIVATE_SUBNET_2 \
        --region $AWS_REGION 2>/dev/null && echo "Private subnet 2 deleted" || echo "Private subnet 2 already deleted or not found"
fi

# Step 8: Delete VPC
echo ""
echo "Step 8: Deleting VPC..."
if [ -n "$VPC_ID" ]; then
    aws ec2 delete-vpc \
        --vpc-id $VPC_ID \
        --region $AWS_REGION 2>/dev/null && echo "VPC deleted" || echo "VPC already deleted or not found"
fi

# Step 9: Delete ACM Certificates
echo ""
echo "Step 9: Deleting ACM certificates..."

if [ -n "$SERVER_CERT_ARN" ]; then
    aws acm delete-certificate \
        --certificate-arn $SERVER_CERT_ARN \
        --region $AWS_REGION 2>/dev/null && echo "Server certificate deleted" || echo "Server certificate already deleted or not found"
fi

if [ -n "$CLIENT_CERT_ARN" ]; then
    aws acm delete-certificate \
        --certificate-arn $CLIENT_CERT_ARN \
        --region $AWS_REGION 2>/dev/null && echo "Client certificate deleted" || echo "Client certificate already deleted or not found"
fi

# Step 10: Cleanup local files
echo ""
echo "Step 10: Cleaning up local files..."
rm -f ~/aws-vpn-config.ovpn
rm -f ~/aws-vpn-variables.sh
rm -rf ~/easy-rsa
sudo rmdir /mnt/efs 2>/dev/null || true

# Kill any running OpenVPN
sudo killall openvpn 2>/dev/null || true

echo ""
echo "=========================================="
echo "Cleanup complete!"
echo "=========================================="