#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# Grafana Dashboard Sync Script
# - Downloads latest revisions from Grafana.com
# - Creates/updates ConfigMaps with grafana_dashboard=1 label
# - Skips gracefully if a dashboard can't be fetched
#==============================================================================

NS="kube-prometheus-stack"
FOLDER="${1:-Community Dashboards}"   # Allow override via first arg
TMP="$(mktemp -d -t dashboards-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Track skipped dashboards
SKIPPED=()
SYNCED=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Download with retries
fetch_with_retries() {
  local url="$1" output="$2" retries=3 delay=5
  local attempt=1
  while (( attempt <= retries )); do
    if curl -fsSL "$url" -o "$output"; then
      return 0
    fi
    log "⚠️  Attempt $attempt to fetch $url failed. Retrying in ${delay}s..."
    sleep "$delay"
    (( attempt++ ))
  done
  return 1
}

download_latest() {
  local id="$1" name="$2"
  log "📥 Fetching latest for ${name} (ID ${id})"

  local rev
  rev=$(curl -s "https://grafana.com/api/dashboards/${id}" | jq -r '.latestRevision')

  if [[ -z "$rev" || "$rev" == "null" ]]; then
    log "⚠️  Skipping dashboard ID: $id — no latest revision found."
    SKIPPED+=("$id ($name)")
    return 0
  fi

  local json_file="${TMP}/${name}.json"
  if ! fetch_with_retries "https://grafana.com/api/dashboards/${id}/revisions/${rev}/download" "$json_file"; then
    log "⚠️  Skipping dashboard ID: $id — failed to download revision $rev."
    SKIPPED+=("$id ($name)")
    return 0
  fi

  kubectl -n "$NS" create configmap "${name}" \
    --from-file="${name}.json=${json_file}" \
    --dry-run=client -o yaml \
  | kubectl -n "$NS" label -f - grafana_dashboard=1 --overwrite \
  | kubectl -n "$NS" annotate -f - grafana_folder="$FOLDER" --overwrite \
  | kubectl apply -f -

  ((SYNCED++))
}

# Ensure namespace exists
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

#------------------------------------------------------------------------------
# Dashboards: ID -> stable name
#------------------------------------------------------------------------------
download_latest 23501 istio-envoy-listeners
download_latest 23502 istio-envoy-clusters
download_latest 23503 istio-envoy-http-conn-mgr
download_latest 23239 envoy-proxy-monitoring-grpc
download_latest 11022 envoy-global
download_latest 22128 hpa
download_latest 22874 k8s-app-logs-multi-cluster
download_latest 10604 host-overview
download_latest 15661 k8s-dashboard
download_latest 18283 kubernetes-dashboard
download_latest 16884 kubernetes-morning-dashboard
download_latest 21073 monitoring-golden-signals
download_latest 11074 node-exporter-dashboard

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
log "✅ Dashboards synced: $SYNCED"
if (( ${#SKIPPED[@]} > 0 )); then
  log "⚠️  Skipped dashboards:"
  for d in "${SKIPPED[@]}"; do
    log "   - $d"
  done
fi

# Fail if none succeeded
if (( SYNCED == 0 )); then
  log "❌ No dashboards were synced successfully."
  exit 1
fi
