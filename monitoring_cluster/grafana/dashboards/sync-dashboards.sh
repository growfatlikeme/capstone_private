#!/usr/bin/env bash
set -euo pipefail
set -x  # DEBUG: print each command before executing

#==============================================================================
# Grafana Dashboard Sync Script (Fixed Revisions, Continue on Error, Debug Mode)
#==============================================================================

NS="kube-prometheus-stack"
FOLDER="${1:-Community Dashboards}"
TMP="$(mktemp -d -t dashboards-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

SKIPPED=()
SYNCED=0

log() {
  { set +x; } 2>/dev/null  # temporarily disable xtrace for clean log lines
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
  set -x
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

  # DEBUG: show first 20 lines of downloaded JSON
  log "📄 First 20 lines of downloaded JSON for ${name}:"
  head -n 20 "${json_file}" || true

  # Create/update the ConfigMap
  kubectl -n "$NS" create configmap "${name}" \
    --from-file="${name}.json=${json_file}" \
    --dry-run=client -o yaml | kubectl apply -f - || {
      log "❌ Failed to apply ConfigMap for $name"
      SKIPPED+=("$id ($name)")
      return 0
    }

  # Label — ignore harmless "not labeled" cases
  kubectl -n "$NS" label configmap "${name}" grafana_dashboard=1 --overwrite || \
    log "ℹ️  Label already present or unchanged for ${name} — moving on"

  # Annotate — ignore harmless "not annotated" cases
  kubectl -n "$NS" annotate configmap "${name}" grafana_folder="$FOLDER" --overwrite || \
    log "ℹ️  Annotation already present or unchanged for ${name} — moving on"

  ((SYNCED++))
}

# Ensure namespace exists
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" || true

#------------------------------------------------------------------------------
# Dashboards: ID, Revision -> stable name
#------------------------------------------------------------------------------
download_revision 23501 2 istio-envoy-listeners || true
download_revision 23502 2 istio-envoy-clusters || true
download_revision 23503 2 istio-envoy-http-conn-mgr || true
download_revision 23239 1 envoy-proxy-monitoring-grpc || true
download_revision 11022 1 envoy-global || true
download_revision 22128 11 hpa || true
download_revision 22874 3 k8s-app-logs-multi-cluster || true
download_revision 10604 1 host-overview || true
download_revision 15661 2 k8s-dashboard || true
download_revision 18283 1 kubernetes-dashboard || true
download_revision 16884 1 kubernetes-morning-dashboard || true
download_revision 21073 1 monitoring-golden-signals || true
download_revision 11074 9 node-exporter-dashboard || true

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
