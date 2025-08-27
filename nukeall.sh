#!/bin/bash

#==============================================================================
# EKS Cluster Teardown Script (Resilient)
# Description: Safely removes all applications, monitoring, logging, and 
#              infrastructure components from EKS cluster.
#              Skips kubectl operations if cluster is unreachable.
#==============================================================================

set -e  # Exit on any error

echo "💥 Starting EKS Cluster Teardown..."
echo "==============================================="
echo "⚠️  WARNING: This will remove ALL applications from the cluster!"
echo "⚠️  The cluster itself will remain (use GitHub workflow to destroy)"
echo "==============================================="
echo ""

#------------------------------------------------------------------------------
# Cluster Connectivity Check
#------------------------------------------------------------------------------
echo "🔍 Checking Kubernetes cluster connectivity..."
if kubectl version --short >/dev/null 2>&1; then
  echo "✅ Kubernetes cluster is reachable."
  SKIP_K8S=false
else
  echo "⚠️  Kubernetes cluster not reachable. Skipping all kubectl operations."
  SKIP_K8S=true
fi

#------------------------------------------------------------------------------
# Phase 1: Remove Applications
#------------------------------------------------------------------------------
echo "🐍 Phase 1: Removing applications..."
if [ "$SKIP_K8S" = false ]; then
  echo "  • Removing Snake Game application..."
  kubectl delete namespace snakegame --ignore-not-found=true
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 2: Remove Logging Stack
#------------------------------------------------------------------------------
echo "📝 Phase 2: Removing logging stack..."
if [ "$SKIP_K8S" = false ]; then
  helm uninstall promtail -n logging 2>/dev/null || true
  helm uninstall loki -n logging 2>/dev/null || true
  kubectl delete -f logging/loki-datasource.yaml --ignore-not-found=true
  kubectl delete namespace logging --ignore-not-found=true
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 3: Remove Monitoring Stack
#------------------------------------------------------------------------------
echo "📈 Phase 3: Removing monitoring stack..."
if [ "$SKIP_K8S" = false ]; then
  kubectl delete -f monitoring_cluster/discord-bridge.yaml --ignore-not-found=true
  kubectl delete -f monitoring_cluster/alertmanager-config.yaml --ignore-not-found=true
  helm uninstall kube-prometheus-stack -n kube-prometheus-stack 2>/dev/null || true
  kubectl delete namespace kube-prometheus-stack --ignore-not-found=true
  kubectl delete crd alertmanagers.monitoring.coreos.com \
    prometheuses.monitoring.coreos.com \
    servicemonitors.monitoring.coreos.com \
    podmonitors.monitoring.coreos.com \
    thanosrulers.monitoring.coreos.com 2>/dev/null || true
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 4: Remove Infrastructure
#------------------------------------------------------------------------------
echo "🏠 Phase 4: Removing infrastructure components..."
if [ "$SKIP_K8S" = false ]; then
  helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true
  kubectl delete namespace ingress-nginx --ignore-not-found=true
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 5: Remove Access Components
#------------------------------------------------------------------------------
echo "🔧 Phase 5: Removing access components..."
if [ "$SKIP_K8S" = false ]; then
  kubectl delete -f openlens.yaml --ignore-not-found=true
  kubectl delete clusterrolebinding openlens-access --ignore-not-found=true
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase 6: Clean Up Remaining Resources
#------------------------------------------------------------------------------
echo "🧹 Phase 6: Cleaning up remaining resources..."
if [ "$SKIP_K8S" = false ]; then
  echo "  • Checking for stuck PVCs..."
  kubectl get pvc --all-namespaces --no-headers 2>/dev/null | while read namespace name rest; do
    if [[ "$namespace" != "default" && "$namespace" != "kube-system" && "$namespace" != "kube-public" && "$namespace" != "kube-node-lease" ]]; then
      echo "    - Removing PVC: $namespace/$name"
      kubectl delete pvc "$name" -n "$namespace" --force --grace-period=0 2>/dev/null || true
    fi
  done

  echo "  • Force deleting remaining namespaces..."
  for ns in snakegame logging kube-prometheus-stack ingress-nginx; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
      echo "    - Force cleaning namespace: $ns"
      kubectl delete namespace "$ns" --force --grace-period=0 2>/dev/null || true
    fi
  done
else
  echo "  • Skipped — no cluster connection."
fi

echo "  • Cleaning Helm cache (optional)..."
rm -rf ~/.helm 2>/dev/null || true

#------------------------------------------------------------------------------
# Phase 7: Verification
#------------------------------------------------------------------------------
echo ""
echo "🔍 Phase 7: Verifying cleanup..."
if [ "$SKIP_K8S" = false ]; then
  echo "==============================================="
  echo "📊 REMAINING NAMESPACES"
  echo "==============================================="
  kubectl get namespaces

  echo ""
  echo "==============================================="
  echo "🎯 REMAINING HELM RELEASES"
  echo "==============================================="
  helm list --all-namespaces

  echo ""
  echo "==============================================="
  echo "⚡ REMAINING LOADBALANCER SERVICES"
  echo "==============================================="
  kubectl get svc --all-namespaces --field-selector spec.type=LoadBalancer
else
  echo "  • Skipped — no cluster connection."
fi

echo ""
echo "==============================================="
echo "✅ TEARDOWN COMPLETE!"
echo "==============================================="
echo "All applications and components have been removed from the cluster (if reachable)."
echo ""
echo "📝 Next steps:"
echo "  • Cluster infrastructure remains running"
echo "  • Use GitHub workflow to destroy Terraform resources"
echo "  • Check AWS console for any remaining LoadBalancers"
echo ""
echo "💡 To redeploy: Run ./setup.sh"
echo ""
