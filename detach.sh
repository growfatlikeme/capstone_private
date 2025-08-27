#!/bin/bash

#==============================================================================
# VPC Dependency Cleanup Script (Full)
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
# Phase 2: Delete Load Balancers in VPC
#------------------------------------------------------------------------------
echo "🧨 Deleting Load Balancers attached to VPC: $VPC_ID..."

CLB_NAMES=$(aws elb describe-load-balancers \
  --region $REGION \
  --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].LoadBalancerName" \
  --output text)

for clb in $CLB_NAMES; do
  echo "  • Deleting Classic ELB: $clb"
  aws elb delete-load-balancer --region $REGION --load-balancer-name "$clb"
done

ELB_ARNs=$(aws elbv2 describe-load-balancers \
  --region $REGION \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
  --output text)

for elb_arn in $ELB_ARNs; do
  echo "  • Deleting ELBv2: $elb_arn"
  aws elbv2 delete-load-balancer --region $REGION --load-balancer-arn "$elb_arn"
done

echo "  • Waiting for load balancer cleanup..."
sleep 20

#------------------------------------------------------------------------------
# Phase 3: Delete NAT Gateways
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
sleep 30

#------------------------------------------------------------------------------
# Phase 4: Release Elastic IPs (Scoped to VPC)
#------------------------------------------------------------------------------
echo "⚡ Releasing Elastic IPs attached to VPC: $VPC_ID..."

ALLOC_IDS=$(aws ec2 describe-addresses \
  --region $REGION \
  --query "Addresses[?NetworkInterfaceId!=null].{AllocId:AllocationId,ENI:NetworkInterfaceId}" \
  --output json | jq -r '.[] | "\(.AllocId) \(.ENI)"')

for entry in $ALLOC_IDS; do
  ALLOC_ID=$(echo $entry | awk '{print $1}')
  ENI_ID=$(echo $entry | awk '{print $2}')

  ENI_VPC_ID=$(aws ec2 describe-network-interfaces \
    --region $REGION \
    --network-interface-ids $ENI_ID \
    --query "NetworkInterfaces[0].VpcId" \
    --output text)

  if [[ "$ENI_VPC_ID" == "$VPC_ID" ]]; then
    echo "  • Releasing EIP: $ALLOC_ID (attached to ENI: $ENI_ID)"
    aws ec2 release-address --region $REGION --allocation-id $ALLOC_ID
  fi
done


#------------------------------------------------------------------------------
# Phase 6: Delete Security Groups (non-default)
#------------------------------------------------------------------------------
echo "🛡️ Deleting non-default security groups in VPC: $VPC_ID..."

SG_IDS=$(aws ec2 describe-security-groups \
  --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[?GroupName!='default'].GroupId" \
  --output text)

for sg in $SG_IDS; do
  echo "  • Deleting Security Group: $sg"
  aws ec2 delete-security-group --region $REGION --group-id "$sg" || echo "    ⚠️ Could not delete $sg (may be in use)"
done

#------------------------------------------------------------------------------
# Phase 7: Delete Route Tables (non-main)
#------------------------------------------------------------------------------
echo "🛣️ Deleting non-main route tables..."
ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
  --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "RouteTables[?Associations[?Main==\`false\`]].RouteTableId" \
  --output text)

for rt in $ROUTE_TABLE_IDS; do
  echo "  • Deleting Route Table: $rt"
  aws ec2 delete-route-table --region $REGION --route-table-id $rt
done

#------------------------------------------------------------------------------
# Phase 8: Delete Subnets
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
# Phase 9: Final Check
#------------------------------------------------------------------------------
echo ""
echo "✅ VPC dependency cleanup complete!"
echo "You can now safely run: terraform destroy"
echo ""
