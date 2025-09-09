#!/usr/bin/env bash
set -euo pipefail

# Configuration
DOMAIN_NAME="g3-dashboard.sctp-sandbox.com"
CLUSTER_NAME="${CLUSTER_NAME:-group3-SRE-cluster}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# Get Grafana load balancer hostname with retries
log "🔍 Getting Grafana load balancer hostname..."
for i in {1..10}; do
    GRAFANA_HOSTNAME=$(kubectl get svc kube-prometheus-stack-grafana -n kube-prometheus-stack -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [[ -n "$GRAFANA_HOSTNAME" && "$GRAFANA_HOSTNAME" != "<none>" ]]; then
        break
    fi
    log "⏳ Attempt $i/10: Waiting for LoadBalancer hostname..."
    sleep 10
done

if [[ -z "$GRAFANA_HOSTNAME" || "$GRAFANA_HOSTNAME" == "<none>" ]]; then
    log "❌ Could not get Grafana hostname after 10 attempts. Skipping Route53 update."
    exit 1
fi

log "✅ Found Grafana hostname: $GRAFANA_HOSTNAME"

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
                        "Value": "$GRAFANA_HOSTNAME"
                    }
                ]
            }
        }
    ]
}
EOF
)

# Update Route53 record
log "🔄 Updating Route53 record for $DOMAIN_NAME to point to $GRAFANA_HOSTNAME..."
if CHANGE_ID=$(aws route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "$CHANGE_BATCH" \
    --query 'ChangeInfo.Id' \
    --output text 2>&1); then
    log "✅ Route53 update initiated. Change ID: $CHANGE_ID"
    log "🎯 $DOMAIN_NAME now points to $GRAFANA_HOSTNAME"
    log "⏳ DNS propagation may take a few minutes..."
else
    log "❌ Failed to update Route53 record: $CHANGE_ID"
    exit 1
fi