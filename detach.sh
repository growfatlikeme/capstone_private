#!/bin/bash

#==============================================================================
# VPC Dependency Cleanup Script
# Description: Removes all dependent resources from a specific VPC to allow
#              Terraform to destroy it cleanly.
#==============================================================================

set -e

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
REGION="ap-southeast-1"
VPC_NAME="growfattest_vpc"  # Replace with your VPC Name tag

echo "🔍 Resolving VPC ID for VPC named: $VPC_NAME..."
VPC_ID=$(aws ec2 describe-vpcs \
  --region $REGION \
  --filters "Name=tag:Name,Values=$VPC_NAME" \
  --query "Vpcs[0].VpcId" \
  --output text)

if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
  echo "❌ VPC with name '$VPC_NAME' not found in region $REGION."
  exit 1
fi

echo "🧹 Starting cleanup for VPC: $VPC_ID"
echo "==============================================="

#------------------------------------------------------------------------------
# Phase 1: Terminate EC2 Instances
#------------------------------------------------------------------------------
echo "🔻 Terminating EC2 instances in VPC..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

if [ -n "$INSTANCE_IDS" ]; then
  aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCE_IDS
  echo "  • Waiting for instances to terminate..."
  aws ec2 wait instance-terminated --region $REGION --instance-ids $INSTANCE_IDS
else
  echo "  • No EC2 instances found."
fi

#------------------------------------------------------------------------------
# Phase 2: Delete NAT Gateways
#------------------------------------------------------------------------------
echo "🌐 Deleting NAT Gateways..."
NAT_IDS=$(aws ec2 describe-nat-gateways \
  --region $REGION \
  --filter "Name=vpc-id,Values=$VPC_ID" \
  --query "NatGateways[].NatGatewayId" \
  --output text)

for nat in $NAT_IDS; do
  echo "  • Deleting NAT Gateway: $nat"
  aws ec2 delete-nat-gateway --region $REGION --nat-gateway-id $nat
done

echo "  • Waiting for NAT Gateways to be deleted..."
sleep 30  # NAT deletion is async; wait before proceeding

#------------------------------------------------------------------------------
# Phase 3: Delete Elastic IPs
#------------------------------------------------------------------------------
echo "⚡ Releasing Elastic IPs..."
ALLOC_IDS=$(aws ec2 describe-addresses \
  --region $REGION \
  --filters "Name=domain,Values=vpc" \
  --query "Addresses[].AllocationId" \
  --output text)

for alloc in $ALLOC_IDS; do
  echo "  • Releasing EIP: $alloc"
  aws ec2 release-address --region $REGION --allocation-id $alloc
done

#------------------------------------------------------------------------------
# Phase 4: Delete ENIs
#------------------------------------------------------------------------------
echo "🔌 Deleting Elastic Network Interfaces..."
ENI_IDS=$(aws ec2 describe-network-interfaces \
  --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "NetworkInterfaces[].NetworkInterfaceId" \
  --output text)

for eni in $ENI_IDS; do
  echo "  • Deleting ENI: $eni"
  aws ec2 delete-network-interface --region $REGION --network-interface-id $eni || true
done

#------------------------------------------------------------------------------
# Phase 5: Delete Route Tables (non-main)
#------------------------------------------------------------------------------
echo "🛣️ Deleting non-main route tables..."
ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
  --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "RouteTables[?Associations[?Main!=`true`]].RouteTableId" \
  --output text)

for rt in $ROUTE_TABLE_IDS; do
  echo "  • Deleting Route Table: $rt"
  aws ec2 delete-route-table --region $REGION --route-table-id $rt
done

#------------------------------------------------------------------------------
# Phase 6: Delete Subnets
#------------------------------------------------------------------------------
echo "📦 Deleting subnets..."
SUBNET_IDS=$(aws ec2 describe-subnets \
  --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[].SubnetId" \
  --output text)

for subnet in $SUBNET_IDS; do
  echo "  • Deleting Subnet: $subnet"
  aws ec2 delete-subnet --region $REGION --subnet-id $subnet
done

#------------------------------------------------------------------------------
# Phase 7: Final Check
#------------------------------------------------------------------------------
echo ""
echo "✅ VPC dependency cleanup complete!"
echo "You can now safely run: terraform destroy"
echo ""
