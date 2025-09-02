#!/bin/bash
set -euo pipefail

# Namespace where Grafana is running
NAMESPACE="kube-prometheus-stack"

# Resolve the repo root based on this script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Path to dashboards directory (relative to repo root)
DASHBOARD_DIR="$REPO_ROOT/monitoring_cluster/grafana/dashboards"

echo "📂 Using dashboard directory: $DASHBOARD_DIR"

cd "$DASHBOARD_DIR"

for json_file in *.json; do
    if [[ -f "$json_file" ]]; then
        dashboard_name=$(basename "$json_file" .json)
        configmap_name="dashboard-${dashboard_name}"

        echo "📦 Creating ConfigMap: $configmap_name from $json_file"

        kubectl create configmap "$configmap_name" \
            --from-file="$json_file" \
            --namespace="$NAMESPACE" \
            --dry-run=client -o yaml | \
        kubectl label --local -f - \
            grafana_dashboard=1 \
            -o yaml | \
        kubectl apply -f -
    fi
done

echo "✅ All dashboard ConfigMaps created with grafana_dashboard=1 label"
