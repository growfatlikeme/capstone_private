echo "🐳 Starting Kubernetes teardown (EKS Monitoring Stack)..."
echo "==============================================="

#------------------------------------------------------------------------------
# Cluster Connectivity Check
#------------------------------------------------------------------------------
echo "🔍 Checking Kubernetes cluster connectivity..."
if kubectl version --client >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  echo "✅ Kubernetes cluster is reachable."
  SKIP_K8S=false
else
  echo "⚠️ Kubernetes cluster not reachable. Skipping all kubectl operations."
  SKIP_K8S=true
fi

#------------------------------------------------------------------------------
# Phase A: Snake Game Application
#------------------------------------------------------------------------------
echo "🐍 Removing Snake Game application..."
if [ "$SKIP_K8S" = false ]; then
  kubectl delete namespace snakegame --ignore-not-found || echo "⚠️ Failed to delete namespace: snakegame"
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase B: Logging Stack
#------------------------------------------------------------------------------
echo "📝 Removing logging stack..."
if [ "$SKIP_K8S" = false ]; then
  helm uninstall promtail -n logging || echo "⚠️ Failed to uninstall promtail"
  helm uninstall loki -n logging || echo "⚠️ Failed to uninstall loki"
  kubectl delete namespace logging --ignore-not-found || echo "⚠️ Failed to delete namespace: logging"
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase C: Monitoring Stack
#------------------------------------------------------------------------------
echo "📈 Removing monitoring stack..."
if [ "$SKIP_K8S" = false ]; then
  kubectl delete -f monitoring_cluster/discord-bridge.yaml --ignore-not-found || echo "⚠️ Failed to delete Discord bridge"
  helm uninstall kube-prometheus-stack -n kube-prometheus-stack || echo "⚠️ Failed to uninstall Prometheus stack"
  kubectl delete namespace kube-prometheus-stack --ignore-not-found || echo "⚠️ Failed to delete namespace: kube-prometheus-stack"
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase D: Infrastructure Components
#------------------------------------------------------------------------------
echo "🏠 Removing infrastructure components..."
if [ "$SKIP_K8S" = false ]; then
  helm uninstall ingress-nginx -n ingress-nginx || echo "⚠️ Failed to uninstall ingress-nginx"
  kubectl delete namespace ingress-nginx --ignore-not-found || echo "⚠️ Failed to delete namespace: ingress-nginx"
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase E: KEDA Autoscaler
#------------------------------------------------------------------------------
echo "📦 Removing KEDA autoscaler..."
if [ "$SKIP_K8S" = false ]; then
  helm uninstall keda -n keda || echo "⚠️ Helm uninstall failed — trying manifest cleanup"
  kubectl delete -f keda/keda.yaml --ignore-not-found || echo "⚠️ Failed to delete KEDA manifest"
  kubectl delete namespace keda --ignore-not-found || echo "⚠️ Failed to delete namespace: keda"
else
  echo "  • Skipped — no cluster connection."
fi

#------------------------------------------------------------------------------
# Phase F: OpenLens Access
#------------------------------------------------------------------------------
echo "🔐 Removing OpenLens access..."
if [ "$SKIP_K8S" = false ]; then
  kubectl delete -f openlens.yaml --ignore-not-found || echo "⚠️ Failed to delete OpenLens manifest"
  kubectl delete clusterrolebinding openlens-access --ignore-not-found || echo "⚠️ Failed to delete OpenLens clusterrolebinding"
else
  echo "  • Skipped — no cluster connection."
fi

echo ""
echo "✅ Kubernetes teardown complete!"
echo "==============================================="
