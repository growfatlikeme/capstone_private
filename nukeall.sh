#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# EKS Monitoring Stack Teardown Script (Nuke-All Edition)
# Description: Removes all workloads, Helm releases, namespaces, CRDs, and port-forwards
#==============================================================================

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

delete_if_exists() {
  local path="$1"
  if [ -f "$path" ]; then
    log "  • Deleting $path"
    kubectl delete -f "$path" --ignore-not-found
  else
    log "  • Skipping $path (file not found)"
  fi
}

log "💥 Starting Full EKS Teardown..."
log "==============================================="
log "⚠️  WARNING: This will remove ALL workloads, Helm releases, and namespaces!"
log "⚠️  The cluster itself will remain (destroy via Terraform/GitHub workflow)"
log "==============================================="

#------------------------------------------------------------------------------
# Cluster Connectivity Check
#------------------------------------------------------------------------------
log "🔍 Checking Kubernetes cluster connectivity..."
if kubectl version --client >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  log "✅ Kubernetes cluster is reachable."
  SKIP_K8S=false
else
  log "⚠️  Kubernetes cluster not reachable. Skipping all kubectl operations."
  SKIP_K8S=true
fi

#------------------------------------------------------------------------------
# Phase 1: Port Forward Cleanup
#------------------------------------------------------------------------------
log "🧹 Phase 1: Cleaning up port forwards..."
pkill -f "kubectl.*port-forward" 2>/dev/null || true
sleep 2

#------------------------------------------------------------------------------
# Phase 2: Workload & Manifest Cleanup
#------------------------------------------------------------------------------
log "🧼 Phase 2: Deleting workloads and applied manifests..."
if [ "$SKIP_K8S" = false ]; then
  # Snakegame
  delete_if_exists snakegame/snakegame.yaml
  delete_if_exists snakegame/ingress.yaml
  delete_if_exists snakegame/scaledobject.yaml
  delete_if_exists snakegame/karpenter.yaml

  # Discord bridge
  delete_if_exists monitoring_cluster/discord-bridge.yaml

  # Loki datasource
  delete_if_exists logging/loki-datasource.yaml

  # Custom dashboard
  delete_if_exists monitoring_cluster/grafana/dashboards/loki-promtail-enhanced-cm.yaml

  # Community dashboards created by sync script
  log "  • Deleting community dashboard ConfigMaps..."
  kubectl get cm -n kube-prometheus-stack -l grafana_dashboard=1 \
    -o name | xargs -r kubectl delete -n kube-prometheus-stack

  # OpenLens SA
  delete_if_exists openlens.yaml

  # Custom Prometheus rules
  delete_if_exists monitoring_cluster/custom-rules.yaml
else
  log "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 3: Helm Release Uninstall
#------------------------------------------------------------------------------
log "📦 Phase 3: Uninstalling Helm releases..."
if [ "$SKIP_K8S" = false ]; then
  helm uninstall promtail -n logging || log "⚠️ Promtail uninstall failed"
  helm uninstall loki -n logging || log "⚠️ Loki uninstall failed"
  helm uninstall kube-prometheus-stack -n kube-prometheus-stack || log "⚠️ Prometheus stack uninstall failed"
  helm uninstall ingress-nginx -n ingress-nginx || log "⚠️ Ingress uninstall failed"
  helm uninstall keda -n keda || log "⚠️ KEDA uninstall failed"
  helm uninstall karpenter -n kube-system || log "⚠️ Karpenter uninstall failed"
else
  log "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 4: CRD Cleanup
#------------------------------------------------------------------------------
log "🧽 Phase 4: Cleaning up CRDs and custom resources..."
if [ "$SKIP_K8S" = false ]; then
  # KEDA CRDs
  kubectl delete crd scaledobjects.keda.sh --ignore-not-found
  kubectl delete crd triggerauthentications.keda.sh --ignore-not-found
  kubectl delete crd clustertriggerauthentications.keda.sh --ignore-not-found
  kubectl delete scaledobject --all -n keda --ignore-not-found
  kubectl delete triggerauthentication --all -n keda --ignore-not-found
  kubectl delete clustertriggerauthentication --all --ignore-not-found
  
  # Karpenter CRDs and resources
  kubectl delete nodepool --all --ignore-not-found
  kubectl delete ec2nodeclass --all --ignore-not-found
  kubectl delete crd nodepools.karpenter.sh --ignore-not-found
  kubectl delete crd ec2nodeclasses.karpenter.k8s.aws --ignore-not-found
else
  log "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 5: Namespace Cleanup
#------------------------------------------------------------------------------
log "🧹 Phase 5: Deleting namespaces..."
if [ "$SKIP_K8S" = false ]; then
  for ns in snakegame logging kube-prometheus-stack ingress-nginx keda; do
    log "  • Deleting namespace: $ns"
    kubectl delete namespace "$ns" --ignore-not-found || log "⚠️ Failed to delete namespace: $ns"
  done
else
  log "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 6: Final Verification
#------------------------------------------------------------------------------
echo ""
log "🔍 Phase 6: Verifying cleanup..."
if [ "$SKIP_K8S" = false ]; then
  log "📊 Remaining Namespaces:"
  kubectl get namespaces || log "⚠️ Unable to list namespaces."

  echo ""
  log "🎯 Remaining Helm Releases:"
  helm list --all-namespaces || log "⚠️ Unable to list Helm releases."

  echo ""
  log "⚡ Remaining LoadBalancer Services:"
  kubectl get svc --all-namespaces --field-selector spec.type=LoadBalancer || log "⚠️ Unable to list LoadBalancer services."
else
  log "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Completion
#------------------------------------------------------------------------------
echo ""
log "✅ TEARDOWN COMPLETE!"
log "All workloads, Helm releases, namespaces, and sidecar-provisioned ConfigMaps have been removed (if reachable)."
echo ""
log "📝 Next steps:"
log "  • Cluster infrastructure remains running"
log "  • Use GitHub workflow to destroy Terraform resources"
log "  • Check AWS console for any leftover LoadBalancers or orphaned resources"
echo ""
log "💡 To redeploy: Run ./setup.sh"
echo ""
