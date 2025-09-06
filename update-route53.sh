#!/usr/bin/env bash
set -euo pipefail

# Configuration
DOMAIN_NAME="g3-snakegame.sctp-sandbox.com"
CLUSTER_NAME="${CLUSTER_NAME:-group3-SRE-cluster}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# Get nginx ingress load balancer hostname with retries
log "🔍 Getting nginx ingress load balancer hostname..."
for i in {1..10}; do
    INGRESS_HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [[ -n "$INGRESS_HOSTNAME" && "$INGRESS_HOSTNAME" != "<none>" ]]; then
        break
    fi
    log "⏳ Attempt $i/10: Waiting for LoadBalancer hostname..."
    sleep 10
done

if [[ -z "$INGRESS_HOSTNAME" || "$INGRESS_HOSTNAME" == "<none>" ]]; then
    log "❌ Could not get ingress hostname after 10 attempts. Skipping Route53 update."
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

# Verify current DNS record before updating
log "🔍 Checking current DNS record..."
CURRENT_RECORD=$(aws route53 list-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" --query "ResourceRecordSets[?Name=='$DOMAIN_NAME.'].ResourceRecords[0].Value" --output text 2>/dev/null || echo "none")
log "📋 Current record points to: $CURRENT_RECORD"

# Update Route53 record
log "🔄 Updating Route53 record for $DOMAIN_NAME to point to $INGRESS_HOSTNAME..."
if CHANGE_ID=$(aws route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "$CHANGE_BATCH" \
    --query 'ChangeInfo.Id' \
    --output text 2>&1); then
    log "✅ Route53 update initiated. Change ID: $CHANGE_ID"
    log "🎯 $DOMAIN_NAME now points to $INGRESS_HOSTNAME"
    log "⏳ DNS propagation may take a few minutes..."
else
    log "❌ Failed to update Route53 record: $CHANGE_ID"
    exit 1
fi