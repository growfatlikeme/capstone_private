#!/bin/bash

#==============================================================================
# EKS Cluster Teardown Script (Enhanced)
# Description: Safely removes all applications, monitoring, logging, and 
#              infrastructure components from EKS cluster.
#              Does NOT destroy the cluster itself—use GitHub workflow for that.
#==============================================================================

set -e  # Exit on any error

echo "💥 Starting EKS Cluster Teardown..."
echo "==============================================="
echo "⚠️  WARNING: This will remove ALL applications from the cluster!"
echo "⚠️  The cluster itself will remain (use GitHub workflow to destroy)"
echo "==============================================="
echo ""

#------------------------------------------------------------------------------
# Phase 1: Stop Port Forwarding
#------------------------------------------------------------------------------
echo "🌐 Phase 1: Stopping port forwarding..."

echo "  • Killing all kubectl port-forward processes..."
pkill -f "kubectl.*port-forward" 2>/dev/null || true
sleep 2

#------------------------------------------------------------------------------
# Phase 2: Remove Applications
#------------------------------------------------------------------------------
echo "🐍 Phase 2: Removing applications..."

echo "  • Removing Snake Game application..."
kubectl delete namespace snakegame --ignore-not-found=true

#------------------------------------------------------------------------------
# Phase 3: Remove Logging Stack
#------------------------------------------------------------------------------
echo "📝 Phase 3: Removing logging stack..."

echo "  • Uninstalling Promtail..."
helm uninstall promtail -n logging 2>/dev/null || true

echo "  • Uninstalling Loki..."
helm uninstall loki -n logging 2>/dev/null || true

echo "  • Removing Loki datasource from Grafana..."
kubectl delete -f logging/loki-datasource.yaml --ignore-not-found=true

echo "  • Removing logging namespace..."
kubectl delete namespace logging --ignore-not-found=true

#------------------------------------------------------------------------------
# Phase 4: Remove Monitoring Stack
#------------------------------------------------------------------------------
echo "📈 Phase 4: Removing monitoring stack..."

echo "  • Removing Discord alerting bridge..."
kubectl delete -f monitoring_cluster/discord-bridge.yaml --ignore-not-found=true

echo "  • Removing Alertmanager config..."
kubectl delete -f monitoring_cluster/alertmanager-config.yaml --ignore-not-found=true

echo "  • Uninstalling Prometheus stack..."
helm uninstall kube-prometheus-stack -n kube-prometheus-stack 2>/dev/null || true

echo "  • Removing kube-prometheus-stack namespace..."
kubectl delete namespace kube-prometheus-stack --ignore-not-found=true

echo "  • Removing lingering CRDs..."
kubectl delete crd alertmanagers.monitoring.coreos.com \
  prometheuses.monitoring.coreos.com \
  servicemonitors.monitoring.coreos.com \
  podmonitors.monitoring.coreos.com \
  thanosrulers.monitoring.coreos.com 2>/dev/null || true

#------------------------------------------------------------------------------
# Phase 5: Remove Infrastructure
#------------------------------------------------------------------------------
echo "🏠 Phase 5: Removing infrastructure components..."

echo "  • Uninstalling Nginx Ingress Controller..."
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true

echo "  • Removing ingress-nginx namespace..."
kubectl delete namespace ingress-nginx --ignore-not-found=true

#------------------------------------------------------------------------------
# Phase 6: Remove Access Components
#------------------------------------------------------------------------------
echo "🔧 Phase 6: Removing access components..."

echo "  • Removing OpenLens service account..."
kubectl delete -f openlens.yaml --ignore-not-found=true

echo "  • Removing OpenLens clusterrolebinding..."
kubectl delete clusterrolebinding openlens-access --ignore-not-found=true

#------------------------------------------------------------------------------
# Phase 7: Clean Up Remaining Resources
#------------------------------------------------------------------------------
echo "🧹 Phase 7: Cleaning up remaining resources..."

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

echo "  • Cleaning Helm cache (optional)..."
rm -rf ~/.helm 2>/dev/null || true

#------------------------------------------------------------------------------
# Phase 8: Verification
#------------------------------------------------------------------------------
echo ""
echo "🔍 Phase 8: Verifying cleanup..."

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

echo ""
echo "==============================================="
echo "✅ TEARDOWN COMPLETE!"
echo "==============================================="
echo "All applications and components have been removed from the cluster."
echo ""
echo "📝 Next steps:"
echo "  • Cluster infrastructure remains running"
echo "  • Use GitHub workflow to destroy Terraform resources"
echo "  • Check AWS console for any remaining LoadBalancers"
echo ""
echo "💡 To redeploy: Run ./setup.sh"
echo ""
