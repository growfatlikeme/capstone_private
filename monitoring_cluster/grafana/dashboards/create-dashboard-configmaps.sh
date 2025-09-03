#!/bin/bash
set -euo pipefail

# Namespace where Grafana is running
NAMESPACE="kube-prometheus-stack"

# Use the script's directory directly (it's already in the dashboards directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="$SCRIPT_DIR"

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
