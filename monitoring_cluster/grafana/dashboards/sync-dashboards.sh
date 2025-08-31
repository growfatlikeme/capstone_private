#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# Grafana Dashboard Sync Script (Fixed Revisions)
# - Downloads specific revisions from Grafana.com
# - Creates/updates ConfigMaps with grafana_dashboard=1 label
#==============================================================================

NS="kube-prometheus-stack"
FOLDER="${1:-Community Dashboards}"   # Allow override via first arg
TMP="$(mktemp -d -t dashboards-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

SKIPPED=()
SYNCED=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

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

download_revision() {
  local id="$1" rev="$2" name="$3"
  log "📥 Fetching ${name} (ID ${id}, rev ${rev})"

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
# Dashboards: ID, Revision -> stable name
#------------------------------------------------------------------------------
download_revision 23501 2 istio-envoy-listeners
download_revision 23502 2 istio-envoy-clusters
download_revision 23503 2 istio-envoy-http-conn-mgr
download_revision 23239 1 envoy-proxy-monitoring-grpc
download_revision 11022 1 envoy-global
download_revision 22128 11 hpa
download_revision 22874 3 k8s-app-logs-multi-cluster
download_revision 10604 1 host-overview
download_revision 15661 2 k8s-dashboard
download_revision 18283 1 kubernetes-dashboard
download_revision 16884 1 kubernetes-morning-dashboard
download_revision 21073 1 monitoring-golden-signals
download_revision 11074 9 node-exporter-dashboard

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

if (( SYNCED == 0 )); then
  log "❌ No dashboards were synced successfully."
  exit 1
fi
