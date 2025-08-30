#!/bin/bash

#==============================================================================
# EKS Monitoring Stack Teardown Script (Nuke-All Edition)
# Description: Removes all workloads, Helm releases, namespaces, and port-forwards
#==============================================================================

echo "💥 Starting Full EKS Teardown..."
echo "==============================================="
echo "⚠️  WARNING: This will remove ALL workloads, Helm releases, and namespaces!"
echo "⚠️  The cluster itself will remain (destroy via Terraform/GitHub workflow)"
echo "==============================================="
echo ""

#------------------------------------------------------------------------------
# Cluster Connectivity Check
#------------------------------------------------------------------------------
echo "🔍 Checking Kubernetes cluster connectivity..."
if kubectl version --client >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  echo "✅ Kubernetes cluster is reachable."
  SKIP_K8S=false
else
  echo "⚠️  Kubernetes cluster not reachable. Skipping all kubectl operations."
  SKIP_K8S=true
fi

#------------------------------------------------------------------------------
# Phase 1: Port Forward Cleanup
#------------------------------------------------------------------------------
echo "🧹 Phase 1: Cleaning up port forwards..."
pkill -f "kubectl.*port-forward" 2>/dev/null || true
sleep 2

#------------------------------------------------------------------------------
# Phase 2: Workload Cleanup
#------------------------------------------------------------------------------
echo "🧼 Phase 2: Deleting workloads and manifests..."
if [ "$SKIP_K8S" = false ]; then
  kubectl delete -f snakegame/snakegame.yaml --ignore-not-found
  kubectl delete -f snakegame/ingress.yaml --ignore-not-found
  kubectl delete -f snakegame/scaledobject.yaml --ignore-not-found
  kubectl delete -f monitoring_cluster/discord-bridge.yaml --ignore-not-found
  kubectl delete -f logging/loki-datasource.yaml --ignore-not-found
  kubectl delete -f openlens.yaml --ignore-not-found
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 3: Helm Release Uninstall
#------------------------------------------------------------------------------
echo "📦 Phase 3: Uninstalling Helm releases..."
if [ "$SKIP_K8S" = false ]; then
  helm uninstall promtail -n logging || echo "⚠️ Promtail uninstall failed"
  helm uninstall loki -n logging || echo "⚠️ Loki uninstall failed"
  helm uninstall kube-prometheus-stack -n kube-prometheus-stack || echo "⚠️ Prometheus stack uninstall failed"
  helm uninstall ingress-nginx -n ingress-nginx || echo "⚠️ Ingress uninstall failed"
  helm uninstall keda -n keda || echo "⚠️ KEDA uninstall failed"
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 4: KEDA CRD Cleanup
#------------------------------------------------------------------------------
echo "🧽 Phase 4: Cleaning up KEDA CRDs and custom resources..."
if [ "$SKIP_K8S" = false ]; then
  kubectl delete crd scaledobjects.keda.sh --ignore-not-found
  kubectl delete crd triggerauthentications.keda.sh --ignore-not-found
  kubectl delete crd clustertriggerauthentications.keda.sh --ignore-not-found
  kubectl delete scaledobject --all -n keda --ignore-not-found
  kubectl delete triggerauthentication --all -n keda --ignore-not-found
  kubectl delete clustertriggerauthentication --all --ignore-not-found
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 5: Namespace Cleanup
#------------------------------------------------------------------------------
echo "🧹 Phase 5: Deleting namespaces..."
if [ "$SKIP_K8S" = false ]; then
  for ns in snakegame logging kube-prometheus-stack ingress-nginx keda; do
    echo "  • Deleting namespace: $ns"
    kubectl delete namespace "$ns" --ignore-not-found || echo "⚠️ Failed to delete namespace: $ns"
  done
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 6: Final Verification
#------------------------------------------------------------------------------
echo ""
echo "🔍 Phase 6: Verifying cleanup..."
if [ "$SKIP_K8S" = false ]; then
  echo "📊 Remaining Namespaces:"
  kubectl get namespaces || echo "⚠️ Unable to list namespaces."

  echo ""
  echo "🎯 Remaining Helm Releases:"
  helm list --all-namespaces || echo "⚠️ Unable to list Helm releases."

  echo ""
  echo "⚡ Remaining LoadBalancer Services:"
  kubectl get svc --all-namespaces --field-selector spec.type=LoadBalancer || echo "⚠️ Unable to list LoadBalancer services."
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Completion
#------------------------------------------------------------------------------
echo ""
echo "✅ TEARDOWN COMPLETE!"
echo "All workloads, Helm releases, and namespaces have been removed (if reachable)."
echo ""
echo "📝 Next steps:"
echo "  • Cluster infrastructure remains running"
echo "  • Use GitHub workflow to destroy Terraform resources"
echo "  • Check AWS console for any leftover LoadBalancers or orphaned resources"
echo ""
echo "💡 To redeploy: Run ./setup.sh"
echo ""
