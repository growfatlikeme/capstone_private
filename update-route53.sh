#!/usr/bin/env bash
set -euo pipefail

# Configuration
DOMAIN_NAME="g3-snakegame.sctp-sandbox.com"
CLUSTER_NAME="${CLUSTER_NAME:-group3-SRE-cluster}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# Get nginx ingress load balancer hostname
log "🔍 Getting nginx ingress load balancer hostname..."
INGRESS_HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [[ -z "$INGRESS_HOSTNAME" ]]; then
    log "❌ Could not get ingress hostname. Make sure nginx ingress is deployed and has a load balancer."
    exit 1
fi

log "✅ Found ingress hostname: $INGRESS_HOSTNAME"

# Get hosted zone ID for the domain
log "🔍 Finding Route53 hosted zone for $DOMAIN_NAME..."
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?contains(Name, 'sctp-sandbox.com')].Id" --output text | sed 's|/hostedzone/||')

if [[ -z "$HOSTED_ZONE_ID" ]]; then
    log "❌ Could not find hosted zone for domain $DOMAIN_NAME"
    exit 1
fi

log "✅ Found hosted zone ID: $HOSTED_ZONE_ID"

# Create change batch JSON
CHANGE_BATCH=$(cat <<EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "$DOMAIN_NAME",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "$INGRESS_HOSTNAME"
                    }
                ]
            }
        }
    ]
}
EOF
)

# Update Route53 record
log "🔄 Updating Route53 record for $DOMAIN_NAME to point to $INGRESS_HOSTNAME..."
CHANGE_ID=$(aws route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "$CHANGE_BATCH" \
    --query 'ChangeInfo.Id' \
    --output text)

log "✅ Route53 update initiated. Change ID: $CHANGE_ID"
log "🎯 $DOMAIN_NAME now points to $INGRESS_HOSTNAME"
log "⏳ DNS propagation may take a few minutes..."