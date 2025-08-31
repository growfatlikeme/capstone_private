#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# EKS Monitoring Stack Setup Script (robust, idempotent)
# - Installs kube-prometheus-stack with Grafana sidecars
# - Installs Loki + Promtail
# - Provisions Loki datasource via sidecar
# - Loads custom dashboard ConfigMap
# - Syncs latest community dashboards into labeled ConfigMaps
# - Deploys Snakegame
#==============================================================================

CLUSTER_NAME="${CLUSTER_NAME:-growfattest-cluster}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"

# --- Helpers -----------------------------------------------------------------
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing required command: $1"; exit 1; }; }
wait_deploy_ready() {
  local ns="$1" name="$2" timeout="${3:-300s}"
  log "⏳ Waiting for deployment/$name in $ns to be ready..."
  kubectl -n "$ns" rollout status deploy/"$name" --timeout="$timeout"
}
wait_pods_ready() {
  local ns="$1" selector="$2" timeout="${3:-300s}"
  log "⏳ Waiting for pods in ns=$ns selector=$selector to be ready..."
  kubectl -n "$ns" wait --for=condition=ready pod -l "$selector" --timeout="$timeout"
}
install_jq_if_needed() {
  if command -v jq >/dev/null 2>&1; then return; fi
  log "🔧 Installing jq (required for dashboard sync)..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y jq
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y jq
  elif command -v apk >/dev/null 2>&1; then
    sudo apk add --no-cache jq
  elif command -v brew >/dev/null 2>&1; then
    brew install jq
  else
    echo "❌ Could not install jq (no supported package manager found). Install jq and re-run."
    exit 1
  fi
}

# --- Pre-flight ---------------------------------------------------------------
require_cmd aws
require_cmd kubectl
require_cmd helm
require_cmd curl

log "🚀 Starting EKS Monitoring Stack Setup"
log "==============================================="

# --- Phase 1: Cluster configuration ------------------------------------------
log "🔧 Phase 1: Configuring cluster access"
log "  • Updating kubeconfig for cluster: $CLUSTER_NAME ($AWS_REGION)"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

log "  • Setting up OpenLens access"
kubectl apply -f openlens.yaml
log "  • OpenLens token:"
kubectl -n kube-system get secret openlens-access-token -o jsonpath="{.data.token}" | base64 --decode || true
echo ""

# --- Phase 2: Infra components -----------------------------------------------
log "🏠 Phase 2: Installing infrastructure components"

log "  • Adding/Updating Helm repos"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
helm repo update

log "  • Installing/Upgrading Nginx Ingress Controller"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

log "  • Installing/Upgrading KEDA"
helm upgrade --install keda kedacore/keda \
  --namespace keda \
  --create-namespace

# --- Phase 3: Monitoring stack -----------------------------------------------
log "📈 Phase 3: Installing monitoring stack"

log "  • Installing/Upgrading kube-prometheus-stack (+ Grafana sidecars)"
helm upgrade --install kube-prometheus-stack \
  --create-namespace \
  --namespace kube-prometheus-stack \
  -f monitoring_cluster/alertmanager-config.yaml \
  -f monitoring_cluster/kube-prometheus-values.yaml \
  --set grafana.service.type=LoadBalancer \
  prometheus-community/kube-prometheus-stack

log "  • Applying Prometheus custom rules"
kubectl apply -f monitoring_cluster/custom-rules.yaml

log "  • Installing Discord alerting bridge"
kubectl apply -f monitoring_cluster/discord-bridge.yaml

# Wait for Grafana to be up (so sidecars can ingest)
wait_deploy_ready kube-prometheus-stack kube-prometheus-stack-grafana 600s

# --- Phase 4: Logging stack ---------------------------------------------------
log "📝 Phase 4: Installing logging stack"

log "  • Ensuring logging namespace exists"
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -

log "  • Installing/Upgrading Loki (log aggregation)"
helm upgrade --install loki grafana/loki \
  --namespace logging \
  -f logging/loki-values.yaml

log "  • Installing/Upgrading Promtail (log collection)"
helm upgrade --install promtail grafana/promtail \
  --namespace logging \
  -f logging/promtail-values.yaml

# Wait for Loki to be ready (ingesters or gateway)
wait_pods_ready logging "app.kubernetes.io/name=loki" 600s
# Small buffer for services/endpoints
sleep 10

# Configure Grafana Loki datasource via sidecar
log "  • Applying Loki datasource (sidecar will import)"
kubectl apply -f logging/loki-datasource.yaml

# Give Grafana’s datasource sidecar a moment to reconcile
sleep 10

# --- Phase 5: Dashboards ------------------------------------------------------
log "📊 Phase 5: Deploying dashboards"

log "  • Applying custom Snakegame dashboard ConfigMap"
kubectl apply -f monitoring_cluster/grafana/dashboards/loki-promtail-enhanced-cm.yaml

# Sync latest Grafana.com dashboards
log "  • Syncing community dashboards (latest revs)"
install_jq_if_needed
bash monitoring_cluster/grafana/dashboards/sync-dashboards.sh

# Optional: nudge Grafana to accelerate sidecar pickup (usually not needed)
# kubectl rollout restart deployment/kube-prometheus-stack-grafana -n kube-prometheus-stack

# --- Phase 6: Application -----------------------------------------------------
log "🐍 Phase 6: Deploying Snake Game application"

log "  • Ensuring snakegame namespace exists"
kubectl create namespace snakegame --dry-run=client -o yaml | kubectl apply -f -

log "  • Deploying Snake Game frontend + ingress + autoscaler"
kubectl apply -f snakegame/snakegame.yaml
kubectl apply -f snakegame/ingress.yaml
kubectl apply -f snakegame/scaledobject.yaml

# --- Phase 7: Access info -----------------------------------------------------
log ""
log "==============================================="
log "🎮 APPLICATION URLS"
log "==============================================="

log "🐍 Snake Game:"
echo "   LoadBalancer: http://$(kubectl get svc snake-frontend-service -n snakegame -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'pending...')"

log ""
log "📊 Grafana Dashboard:"
echo "   LoadBalancer: http://$(kubectl get svc kube-prometheus-stack-grafana -n kube-prometheus-stack -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'pending...')"
echo "   Username: admin"
echo "   Password: $(kubectl --namespace kube-prometheus-stack get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo 'retrieving...')"

log ""
log "==============================================="
log "✅ SETUP COMPLETE!"
log "==============================================="
