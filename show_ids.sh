#!/bin/bash

#############################################
# SHOW IDS SCRIPT - Enumerate AWS Resources
#############################################

# ============== CONFIGURATION ==============
AWS_REGION="${AWS_REGION:-eu-west-1}"
# ============================================

echo "=========================================="
echo "AWS Resource Enumeration"
echo "Region: $AWS_REGION"
echo "Account: $(aws sts get-caller-identity --query 'Account' --output text)"
echo "Date: $(date)"
echo "=========================================="

#############################################
# VPCs
#############################################
echo ""
echo "=========================================="
echo "VPCs"
echo "=========================================="
aws ec2 describe-vpcs \
    --region $AWS_REGION \
    --query 'Vpcs[*].[VpcId,CidrBlock,State,Tags[?Key==`Name`].Value|[0]]' \
    --output text | while read vpc_id cidr state name; do
    echo "  $vpc_id | $cidr | $state | Name: $name"
done

#############################################
# Subnets
#############################################
echo ""
echo "=========================================="
echo "Subnets"
echo "=========================================="
aws ec2 describe-subnets \
    --region $AWS_REGION \
    --query 'Subnets[*].[SubnetId,VpcId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`].Value|[0]]' \
    --output text | while read subnet_id vpc_id cidr az name; do
    echo "  $subnet_id | VPC: $vpc_id | $cidr | $az | Name: $name"
done

#############################################
# Security Groups
#############################################
echo ""
echo "=========================================="
echo "Security Groups"
echo "=========================================="
aws ec2 describe-security-groups \
    --region $AWS_REGION \
    --query 'SecurityGroups[*].[GroupId,GroupName,VpcId,Description]' \
    --output text | while read sg_id name vpc_id desc; do
    echo "  $sg_id | $name | VPC: $vpc_id"
    echo "           Description: $desc"
done

#############################################
# EC2 Instances
#############################################
echo ""
echo "=========================================="
echo "EC2 Instances"
echo "=========================================="
INSTANCES=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PrivateIpAddress,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' \
    --output text)

if [ -z "$INSTANCES" ]; then
    echo "  No EC2 instances found"
else
    echo "$INSTANCES" | while read instance_id type state private_ip public_ip name; do
        echo "  $instance_id | $type | $state | Private: $private_ip | Public: $public_ip | Name: $name"
    done
fi

#############################################
# Client VPN Endpoints
#############################################
echo ""
echo "=========================================="
echo "Client VPN Endpoints"
echo "=========================================="
VPNS=$(aws ec2 describe-client-vpn-endpoints \
    --region $AWS_REGION \
    --query 'ClientVpnEndpoints[*].[ClientVpnEndpointId,Status.Code,ClientCidrBlock,VpcId,Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null)

if [ -z "$VPNS" ]; then
    echo "  No Client VPN endpoints found"
else
    echo "$VPNS" | while read vpn_id status cidr vpc_id name; do
        echo "  $vpn_id | Status: $status | CIDR: $cidr | VPC: $vpc_id | Name: $name"
        
        # Get associations
        echo "    Associations:"
        aws ec2 describe-client-vpn-target-networks \
            --client-vpn-endpoint-id $vpn_id \
            --region $AWS_REGION \
            --query 'ClientVpnTargetNetworks[*].[AssociationId,SubnetId,Status.Code]' \
            --output text 2>/dev/null | while read assoc_id subnet_id assoc_status; do
            echo "      $assoc_id | Subnet: $subnet_id | Status: $assoc_status"
        done
    done
fi

#############################################
# EFS File Systems
#############################################
echo ""
echo "=========================================="
echo "EFS File Systems"
echo "=========================================="
EFS_LIST=$(aws efs describe-file-systems \
    --region $AWS_REGION \
    --query 'FileSystems[*].[FileSystemId,LifeCycleState,SizeInBytes.Value,Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null)

if [ -z "$EFS_LIST" ]; then
    echo "  No EFS file systems found"
else
    echo "$EFS_LIST" | while read efs_id state size name; do
        size_mb=$((size / 1024 / 1024))
        echo "  $efs_id | Status: $state | Size: ${size_mb}MB | Name: $name"
        
        # Get mount targets
        echo "    Mount Targets:"
        aws efs describe-mount-targets \
            --file-system-id $efs_id \
            --region $AWS_REGION \
            --query 'MountTargets[*].[MountTargetId,SubnetId,IpAddress,LifeCycleState]' \
            --output text 2>/dev/null | while read mt_id subnet_id ip mt_state; do
            echo "      $mt_id | Subnet: $subnet_id | IP: $ip | Status: $mt_state"
        done
    done
fi

#############################################
# ACM Certificates
#############################################
echo ""
echo "=========================================="
echo "ACM Certificates"
echo "=========================================="
CERTS=$(aws acm list-certificates \
    --region $AWS_REGION \
    --query 'CertificateSummaryList[*].[CertificateArn,DomainName,Status]' \
    --output text 2>/dev/null)

if [ -z "$CERTS" ]; then
    echo "  No ACM certificates found"
else
    echo "$CERTS" | while read cert_arn domain status; do
        echo "  $cert_arn"
        echo "    Domain: $domain | Status: $status"
    done
fi

#############################################
# Internet Gateways
#############################################
echo ""
echo "=========================================="
echo "Internet Gateways"
echo "=========================================="
IGWS=$(aws ec2 describe-internet-gateways \
    --region $AWS_REGION \
    --query 'InternetGateways[*].[InternetGatewayId,Attachments[0].VpcId,Attachments[0].State,Tags[?Key==`Name`].Value|[0]]' \
    --output text)

if [ -z "$IGWS" ]; then
    echo "  No Internet Gateways found"
else
    echo "$IGWS" | while read igw_id vpc_id state name; do
        echo "  $igw_id | VPC: $vpc_id | State: $state | Name: $name"
    done
fi

#############################################
# NAT Gateways
#############################################
echo ""
echo "=========================================="
echo "NAT Gateways"
echo "=========================================="
NATS=$(aws ec2 describe-nat-gateways \
    --region $AWS_REGION \
    --filter "Name=state,Values=available,pending" \
    --query 'NatGateways[*].[NatGatewayId,VpcId,SubnetId,State,Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null)

if [ -z "$NATS" ]; then
    echo "  No NAT Gateways found"
else
    echo "$NATS" | while read nat_id vpc_id subnet_id state name; do
        echo "  $nat_id | VPC: $vpc_id | Subnet: $subnet_id | State: $state | Name: $name"
    done
fi

#############################################
# Elastic IPs
#############################################
echo ""
echo "=========================================="
echo "Elastic IPs"
echo "=========================================="
EIPS=$(aws ec2 describe-addresses \
    --region $AWS_REGION \
    --query 'Addresses[*].[AllocationId,PublicIp,InstanceId,AssociationId,Tags[?Key==`Name`].Value|[0]]' \
    --output text)

if [ -z "$EIPS" ]; then
    echo "  No Elastic IPs found"
else
    echo "$EIPS" | while read alloc_id public_ip instance_id assoc_id name; do
        echo "  $alloc_id | $public_ip | Instance: $instance_id | Name: $name"
    done
fi

#############################################
# Route Tables
#############################################
echo ""
echo "=========================================="
echo "Route Tables"
echo "=========================================="
aws ec2 describe-route-tables \
    --region $AWS_REGION \
    --query 'RouteTables[*].[RouteTableId,VpcId,Tags[?Key==`Name`].Value|[0]]' \
    --output text | while read rt_id vpc_id name; do
    echo "  $rt_id | VPC: $vpc_id | Name: $name"
done

#############################################
# Load Balancers (ALB/NLB)
#############################################
echo ""
echo "=========================================="
echo "Load Balancers (ALB/NLB)"
echo "=========================================="
LBS=$(aws elbv2 describe-load-balancers \
    --region $AWS_REGION \
    --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName,Type,State.Code,VpcId]' \
    --output text 2>/dev/null)

if [ -z "$LBS" ]; then
    echo "  No Load Balancers found"
else
    echo "$LBS" | while read lb_arn lb_name lb_type state vpc_id; do
        echo "  $lb_name | Type: $lb_type | State: $state | VPC: $vpc_id"
        echo "    ARN: $lb_arn"
    done
fi

#############################################
# RDS Instances
#############################################
echo ""
echo "=========================================="
echo "RDS Instances"
echo "=========================================="
RDS=$(aws rds describe-db-instances \
    --region $AWS_REGION \
    --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,Engine,DBInstanceStatus,Endpoint.Address]' \
    --output text 2>/dev/null)

if [ -z "$RDS" ]; then
    echo "  No RDS instances found"
else
    echo "$RDS" | while read db_id db_class engine status endpoint; do
        echo "  $db_id | $db_class | $engine | Status: $status"
        echo "    Endpoint: $endpoint"
    done
fi

#############################################
# S3 Buckets (Global but listed here)
#############################################
echo ""
echo "=========================================="
echo "S3 Buckets (Global)"
echo "=========================================="
BUCKETS=$(aws s3api list-buckets \
    --query 'Buckets[*].[Name,CreationDate]' \
    --output text 2>/dev/null)

if [ -z "$BUCKETS" ]; then
    echo "  No S3 buckets found"
else
    echo "$BUCKETS" | while read bucket_name created; do
        # Check if bucket is in our region
        BUCKET_REGION=$(aws s3api get-bucket-location \
            --bucket $bucket_name \
            --query 'LocationConstraint' \
            --output text 2>/dev/null)
        
        # Handle null region (us-east-1)
        if [ "$BUCKET_REGION" = "None" ] || [ "$BUCKET_REGION" = "null" ]; then
            BUCKET_REGION="us-east-1"
        fi
        
        echo "  $bucket_name | Region: $BUCKET_REGION | Created: $created"
    done
fi

#############################################
# Lambda Functions
#############################################
echo ""
echo "=========================================="
echo "Lambda Functions"
echo "=========================================="
LAMBDAS=$(aws lambda list-functions \
    --region $AWS_REGION \
    --query 'Functions[*].[FunctionName,Runtime,MemorySize,Timeout]' \
    --output text 2>/dev/null)

if [ -z "$LAMBDAS" ]; then
    echo "  No Lambda functions found"
else
    echo "$LAMBDAS" | while read func_name runtime memory timeout; do
        echo "  $func_name | Runtime: $runtime | Memory: ${memory}MB | Timeout: ${timeout}s"
    done
fi

#############################################
# Key Pairs
#############################################
echo ""
echo "=========================================="
echo "Key Pairs"
echo "=========================================="
aws ec2 describe-key-pairs \
    --region $AWS_REGION \
    --query 'KeyPairs[*].[KeyPairId,KeyName,KeyType]' \
    --output text | while read key_id key_name key_type; do
    echo "  $key_id | $key_name | Type: $key_type"
done

#############################################
# Summary for Cleanup Script
#############################################
echo ""
echo "=========================================="
echo "QUICK COPY FOR CLEANUP SCRIPT"
echo "=========================================="

# Get first VPC (if exists)
FIRST_VPC=$(aws ec2 describe-vpcs --region $AWS_REGION --query 'Vpcs[?Tags[?Key==`Name` && contains(Value, `vpn`)]].VpcId' --output text | head -1)
if [ -n "$FIRST_VPC" ] && [ "$FIRST_VPC" != "None" ]; then
    echo ""
    echo "# VPN-related VPC found: $FIRST_VPC"
    echo "VPC_ID=\"$FIRST_VPC\""
    
    # Get subnets for this VPC
    aws ec2 describe-subnets \
        --region $AWS_REGION \
        --filters "Name=vpc-id,Values=$FIRST_VPC" \
        --query 'Subnets[*].SubnetId' \
        --output text | tr '\t' '\n' | nl | while read num subnet; do
        echo "PRIVATE_SUBNET_$num=\"$subnet\""
    done
    
    # Get security groups for this VPC
    aws ec2 describe-security-groups \
        --region $AWS_REGION \
        --filters "Name=vpc-id,Values=$FIRST_VPC" \
        --query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]' \
        --output text | while read sg_id sg_name; do
        var_name=$(echo $sg_name | tr '[:lower:]-' '[:upper:]_')
        echo "${var_name}_SG_ID=\"$sg_id\""
    done
fi

# Get VPN Endpoint
VPN_EP=$(aws ec2 describe-client-vpn-endpoints --region $AWS_REGION --query 'ClientVpnEndpoints[0].ClientVpnEndpointId' --output text 2>/dev/null)
if [ -n "$VPN_EP" ] && [ "$VPN_EP" != "None" ]; then
    echo "VPN_ENDPOINT_ID=\"$VPN_EP\""
    
    ASSOC=$(aws ec2 describe-client-vpn-target-networks --client-vpn-endpoint-id $VPN_EP --region $AWS_REGION --query 'ClientVpnTargetNetworks[0].AssociationId' --output text 2>/dev/null)
    if [ -n "$ASSOC" ] && [ "$ASSOC" != "None" ]; then
        echo "ASSOCIATION_ID=\"$ASSOC\""
    fi
fi

# Get EFS
EFS=$(aws efs describe-file-systems --region $AWS_REGION --query 'FileSystems[0].FileSystemId' --output text 2>/dev/null)
if [ -n "$EFS" ] && [ "$EFS" != "None" ]; then
    echo "EFS_ID=\"$EFS\""
    
    aws efs describe-mount-targets \
        --file-system-id $EFS \
        --region $AWS_REGION \
        --query 'MountTargets[*].MountTargetId' \
        --output text 2>/dev/null | tr '\t' '\n' | nl | while read num mt_id; do
        echo "MOUNT_TARGET_$num=\"$mt_id\""
    done
fi

# Get ACM Certs
echo ""
echo "# ACM Certificates"
aws acm list-certificates \
    --region $AWS_REGION \
    --query 'CertificateSummaryList[*].[CertificateArn,DomainName]' \
    --output text 2>/dev/null | while read cert_arn domain; do
    if echo "$domain" | grep -q "server"; then
        echo "SERVER_CERT_ARN=\"$cert_arn\""
    elif echo "$domain" | grep -q "client"; then
        echo "CLIENT_CERT_ARN=\"$cert_arn\""
    fi
done

echo ""
echo "=========================================="
echo "Enumeration complete!"
echo "=========================================="