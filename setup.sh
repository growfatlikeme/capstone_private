#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Portability: resolve repo root & dashboard dir
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
DASHBOARD_DIR="$REPO_ROOT/monitoring_cluster/grafana/dashboards"

# -----------------------------
# Cluster & datasource settings
# -----------------------------
CLUSTER_NAME="${CLUSTER_NAME:-growfattest-cluster}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
PROM_UID="prometheus"
LOKI_UID="loki"

# -----------------------------
# Dashboards to fetch
# -----------------------------
DASHBOARDS_TO_FETCH=(
  "23501:2:istio-envoy-listeners.json"
  "23502:2:istio-envoy-clusters.json"
  "23503:2:istio-envoy-http-conn-mgr.json"
  "23239:1:envoy-proxy-monitoring-grpc.json"
  "11022:1:envoy-global.json"
  "22128:11:hpa.json"
  "22874:3:k8s-app-logs-multi-cluster.json"
  "10604:1:host-overview.json"
  "15661:2:k8s-dashboard-en.json"
  "18283:1:kubernetes-dashboard.json"
  "16884:1:kubernetes-morning-dashboard.json"
  "21073:1:monitoring-golden-signals.json"
  "11074:9:node-exporter-dashboard.json"
)

# -----------------------------
# Helper functions
# -----------------------------
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
  log "🔧 Installing jq..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y jq
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y jq
  elif command -v apk >/dev/null 2>&1; then
    sudo apk add --no-cache jq
  elif command -v brew >/dev/null 2>&1; then
    brew install jq
  else
    echo "❌ Could not install jq"; exit 1
  fi
}

# -----------------------------
# Clean dashboard JSON
# -----------------------------
clean_dashboard_json() {
  local infile="$1"
  local outfile="$2"
  jq --arg prom_uid "$PROM_UID" \
     --arg loki_uid "$LOKI_UID" '
    (if has("dashboard") then .dashboard else . end)
    | .id = null
    | del(.uid)
    | del(.dashboard.uid)
    | del(.__inputs)
    | del(.dashboard.__inputs)
    | (.__requires // []) |= map(
        if .type == "datasource" and (.id | type) == "string" and (.id | test("prometheus"; "i")) then
          .id = "prometheus" | .name = "Prometheus"
        elif .type == "datasource" and (.id | type) == "string" and (.id | test("loki"; "i")) then
          .id = "loki" | .name = "Loki"
        else .
        end
      )
    | (.. | objects | select(has("datasource"))) |= (
        if (.datasource | type) == "object" then
          if (.datasource.uid | type) == "string" and (.datasource.uid | test("\\$\\{"; "i")) then
            if (.datasource.type | type) == "string" and (.datasource.type | test("loki"; "i")) then
              .datasource.uid = $loki_uid
            else
              .datasource.uid = $prom_uid
            end
          elif (.datasource.uid | type) == "string" and .datasource.uid != $prom_uid and .datasource.uid != $loki_uid then
            if (.datasource.type | type) == "string" and (.datasource.type | test("loki"; "i")) then
              .datasource.uid = $loki_uid
            else
              .datasource.uid = $prom_uid
            end
          else .
          end
        elif (.datasource | type) == "string" then
          if (.datasource | test("loki"; "i")) then
            .datasource = $loki_uid
          elif (.datasource | test("\\$\\{"; "i")) then
            .datasource = $prom_uid
          elif .datasource != $prom_uid and .datasource != $loki_uid then
            .datasource = $prom_uid
          else .
          end
        else .
        end
      )
  ' "$infile" > "$outfile"
}

# -----------------------------
# Fetch & clean dashboards
# -----------------------------
fetch_and_clean_dashboards() {
  install_jq_if_needed
  mkdir -p "$DASHBOARD_DIR"
  for entry in "${DASHBOARDS_TO_FETCH[@]}"; do
    IFS=":" read -r gnetId rev filename <<< "$entry"
    log "🌐 Downloading dashboard $gnetId (rev $rev) -> $filename"
    tmpfile="$(mktemp)"
    if curl -sSL "https://grafana.com/api/dashboards/${gnetId}/revisions/${rev}/download" -o "$tmpfile"; then
      log "🧹 Cleaning $filename"
      if ! clean_dashboard_json "$tmpfile" "$DASHBOARD_DIR/$filename"; then
        log "⚠️ Failed to clean $filename — skipping"
      fi
    else
      log "⚠️ Failed to download $filename — skipping"
    fi
    rm -f "$tmpfile"
  done
}

clean_existing_custom_dashboards() {
  install_jq_if_needed
  if [ -d "$DASHBOARD_DIR" ]; then
    find "$DASHBOARD_DIR" -type f -name "*.json" | while read -r file; do
      log "🧹 Cleaning existing custom dashboard: $file"
      tmpfile="$(mktemp)"
      clean_dashboard_json "$file" "$tmpfile"
      mv "$tmpfile" "$file"
    done
  fi
}

# --- Pre-flight checks ---
require_cmd aws
require_cmd kubectl
require_cmd helm
require_cmd curl

log "🚀 Starting EKS Monitoring Stack Setup"

# --- Phase 1: Cluster config ---
log "🔧 Phase 1: Configuring cluster access"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

log "  • Setting up OpenLens access"
kubectl apply -f "$REPO_ROOT/openlens.yaml"
OPENLENS_TOKEN="$(kubectl -n kube-system get secret openlens-access-token -o jsonpath="{.data.token}" 2>/dev/null | base64 --decode || true)"
echo "🔑 OpenLens token (plaintext): ${OPENLENS_TOKEN}"
echo "::notice title=OpenLens Token::${OPENLENS_TOKEN}"
echo ""

# --- Phase 2: Infra components ---
log "🏠 Phase 2: Installing infrastructure components"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo add kedacore https://kedacore.github.io/charts || true
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer

helm upgrade --install keda kedacore/keda \
  --namespace keda --create-namespace

# --- Phase 3: Monitoring stack ---
log "📈 Phase 3: Installing monitoring stack"
helm upgrade --install kube-prometheus-stack \
  --create-namespace --namespace kube-prometheus-stack \
  -f "$REPO_ROOT/monitoring_cluster/alertmanager-config.yaml" \
  -f "$REPO_ROOT/monitoring_cluster/kube-prometheus-values.yaml" \
  --set grafana.service.type=LoadBalancer \
  prometheus-community/kube-prometheus-stack

kubectl apply -f "$REPO_ROOT/monitoring_cluster/custom-rules.yaml"
kubectl apply -f "$REPO_ROOT/monitoring_cluster/discord-bridge.yaml"

wait_deploy_ready kube-prometheus-stack kube-prometheus-stack-grafana 600s

# --- Phase 4: Logging stack ---
log "📝 Phase 4: Installing logging stack"
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install loki grafana/loki \
  --namespace logging -f "$REPO_ROOT/logging/loki-values.yaml"

helm upgrade --install promtail grafana/promtail \
  --namespace logging -f "$REPO_ROOT/logging/promtail-values.yaml"

wait_pods_ready logging "app.kubernetes.io/name=loki" 600s
sleep 10

# --- Phase 5: Dashboard fetch + clean + ConfigMaps ---
log "📊 Phase 5: Fetching and cleaning dashboards from Grafana.com"
fetch_and_clean_dashboards

log "📄 Phase 5b: Cleaning existing custom dashboards"
clean_existing_custom_dashboards

log "📋 Phase 5c: Creating dashboard ConfigMaps"
CREATE_CM_SCRIPT="$DASHBOARD_DIR/create-dashboard-configmaps.sh"
if [[ -f "$CREATE_CM_SCRIPT" ]]; then
  chmod +x "$CREATE_CM_SCRIPT"
  "$CREATE_CM_SCRIPT"
else
  log "⚠️ ConfigMap creation script not found at $CREATE_CM_SCRIPT — skipping"
fi

# Apply any static custom dashboards (already cleaned now)
if [[ -f "$DASHBOARD_DIR/loki-promtail-enhanced-cm.yaml" ]]; then
  kubectl apply -f "$DASHBOARD_DIR/loki-promtail-enhanced-cm.yaml"
fi

# --- Phase 6: Application ---
log "🐍 Phase 6: Deploying Snake Game application"
kubectl create namespace snakegame --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$REPO_ROOT/snakegame/snakegame.yaml"
kubectl apply -f "$REPO_ROOT/snakegame/ingress.yaml"
kubectl apply -f "$REPO_ROOT/snakegame/scaledobject.yaml"

# --- Phase 7: Access info ---
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

