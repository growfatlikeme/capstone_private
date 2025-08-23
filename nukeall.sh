#!/bin/bash

#==============================================================================
# EKS Cluster Teardown Script
# Description: Safely removes all applications and resources from EKS cluster
#              (Does NOT destroy the cluster itself - use GitHub workflow)
#==============================================================================

set -e  # Exit on any error

echo "💥 Starting EKS Cluster Teardown..."
echo "==============================================="
echo "⚠️  WARNING: This will remove ALL applications from the cluster!"
echo "⚠️  The cluster itself will remain (use GitHub workflow to destroy)"
echo "==============================================="
echo ""
echo "🔥 Beginning teardown process..."

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

# Remove Snake Game
echo "  • Removing Snake Game application..."
kubectl delete namespace snakegame --ignore-not-found=true

#------------------------------------------------------------------------------
# Phase 3: Remove Logging Stack
#------------------------------------------------------------------------------
echo "📝 Phase 3: Removing logging stack..."

# Remove Promtail
echo "  • Uninstalling Promtail..."
helm uninstall promtail -n logging 2>/dev/null || true

# Remove Loki
echo "  • Uninstalling Loki..."
helm uninstall loki -n logging 2>/dev/null || true

# Remove logging namespace
echo "  • Removing logging namespace..."
kubectl delete namespace logging --ignore-not-found=true

#------------------------------------------------------------------------------
# Phase 4: Remove Monitoring Stack
#------------------------------------------------------------------------------
echo "📈 Phase 4: Removing monitoring stack..."

# Remove Discord Bridge
echo "  • Removing Discord bridge..."
kubectl delete -f monitoring_cluster/discord-bridge.yaml --ignore-not-found=true

# Remove Prometheus Stack
echo "  • Uninstalling Prometheus stack..."
helm uninstall kube-prometheus-stack -n kube-prometheus-stack 2>/dev/null || true

# Remove monitoring namespace
echo "  • Removing kube-prometheus-stack namespace..."
kubectl delete namespace kube-prometheus-stack --ignore-not-found=true

#------------------------------------------------------------------------------
# Phase 5: Remove Infrastructure
#------------------------------------------------------------------------------
echo "🏠 Phase 5: Removing infrastructure components..."

# Remove Nginx Ingress
echo "  • Uninstalling Nginx Ingress Controller..."
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true

# Remove ingress namespace
echo "  • Removing ingress-nginx namespace..."
kubectl delete namespace ingress-nginx --ignore-not-found=true

#------------------------------------------------------------------------------
# Phase 6: Remove Access Components
#------------------------------------------------------------------------------
echo "🔧 Phase 6: Removing access components..."

# Remove OpenLens service account
echo "  • Removing OpenLens access..."
kubectl delete -f openlens.yaml --ignore-not-found=true

#------------------------------------------------------------------------------
# Phase 7: Clean Up Remaining Resources
#------------------------------------------------------------------------------
echo "🧹 Phase 7: Cleaning up remaining resources..."

# Remove any stuck finalizers (common with monitoring stack)
echo "  • Checking for stuck resources..."

# Force delete any remaining PVCs
kubectl get pvc --all-namespaces --no-headers 2>/dev/null | while read namespace name rest; do
    if [[ "$namespace" != "default" && "$namespace" != "kube-system" && "$namespace" != "kube-public" && "$namespace" != "kube-node-lease" ]]; then
        echo "    - Removing PVC: $namespace/$name"
        kubectl delete pvc "$name" -n "$namespace" --force --grace-period=0 2>/dev/null || true
    fi
done

# Remove any remaining configmaps/secrets from our namespaces
for ns in snakegame logging kube-prometheus-stack ingress-nginx; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
        echo "    - Force cleaning namespace: $ns"
        kubectl delete namespace "$ns" --force --grace-period=0 2>/dev/null || true
    fi
done

#------------------------------------------------------------------------------
# Phase 8: Verification
#------------------------------------------------------------------------------
echo "🔍 Phase 8: Verifying cleanup..."

echo ""
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
echo "All applications have been removed from the cluster."
echo ""
echo "📝 Next steps:"
echo "  • Cluster infrastructure remains running"
echo "  • Use GitHub workflow to destroy Terraform resources"
echo "  • Check AWS console for any remaining LoadBalancers"
echo ""
echo "💡 To redeploy: Run ./setup.sh"
echo ""