#!/bin/bash

#==============================================================================
# EKS Cluster Teardown Script (Simplified & Resilient)
# Description: Uninstalls Helm releases and deletes namespaces for a clean
#              teardown. Skips kubectl operations if cluster is unreachable.
#==============================================================================

echo "💥 Starting EKS Cluster Teardown..."
echo "==============================================="
echo "⚠️  WARNING: This will remove ALL workloads and namespaces from the cluster!"
echo "⚠️  The cluster itself will remain (use GitHub workflow to destroy)"
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
# Phase 1: Uninstall Helm Releases
#------------------------------------------------------------------------------
echo "📦 Phase 1: Uninstalling Helm releases..."
if [ "$SKIP_K8S" = false ]; then
  helm uninstall promtail -n logging || echo "⚠️ Failed to uninstall promtail"
  helm uninstall loki -n logging || echo "⚠️ Failed to uninstall loki"
  helm uninstall kube-prometheus-stack -n kube-prometheus-stack || echo "⚠️ Failed to uninstall Prometheus stack"
  helm uninstall ingress-nginx -n ingress-nginx || echo "⚠️ Failed to uninstall ingress-nginx"
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 2: Delete Namespaces
#------------------------------------------------------------------------------
echo "🧹 Phase 2: Deleting namespaces..."
if [ "$SKIP_K8S" = false ]; then
  for ns in snakegame logging kube-prometheus-stack ingress-nginx; do
    echo "  • Deleting namespace: $ns"
    kubectl delete namespace "$ns" --ignore-not-found || echo "⚠️ Failed to delete namespace: $ns"
  done
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 3: Verification
#------------------------------------------------------------------------------
echo ""
echo "🔍 Phase 3: Verifying cleanup..."
if [ "$SKIP_K8S" = false ]; then
  echo "==============================================="
  echo "📊 REMAINING NAMESPACES"
  echo "==============================================="
  kubectl get namespaces || echo "⚠️ Unable to list namespaces."

  echo ""
  echo "==============================================="
  echo "🎯 REMAINING HELM RELEASES"
  echo "==============================================="
  helm list --all-namespaces || echo "⚠️ Unable to list Helm releases."

  echo ""
  echo "==============================================="
  echo "⚡ REMAINING LOADBALANCER SERVICES"
  echo "==============================================="
  kubectl get svc --all-namespaces --field-selector spec.type=LoadBalancer || echo "⚠️ Unable to list LoadBalancer services."
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Completion
#------------------------------------------------------------------------------
echo ""
echo "==============================================="
echo "✅ TEARDOWN COMPLETE!"
echo "==============================================="
echo "All Helm releases and namespaces have been removed (if reachable)."
echo ""
echo "📝 Next steps:"
echo "  • Cluster infrastructure remains running"
echo "  • Use GitHub workflow to destroy Terraform resources"
echo "  • Check AWS console for any remaining LoadBalancers"
echo ""
echo "💡 To redeploy: Run ./setup.sh"
echo ""
