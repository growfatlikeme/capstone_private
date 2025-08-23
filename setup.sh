#!/bin/bash

#==============================================================================
# EKS Monitoring Stack Setup Script
# Description: Deploys complete monitoring stack with Prometheus, Grafana, 
#              Loki, and Snake Game application on EKS cluster
#==============================================================================

set -e  # Exit on any error

echo "🚀 Starting EKS Monitoring Stack Setup..."
echo "==============================================="

#------------------------------------------------------------------------------
# Phase 1: Cluster Configuration
#------------------------------------------------------------------------------
echo "🔧 Phase 1: Configuring cluster access..."

# Update kubeconfig
echo "  • Updating kubeconfig..."
aws eks update-kubeconfig --name growfattest-cluster --region ap-southeast-1

# Install OpenLens service account
echo "  • Setting up OpenLens access..."
kubectl apply -f openlens.yaml
echo "  • OpenLens token:"
kubectl -n kube-system get secret openlens-access-token -o jsonpath="{.data.token}" | base64 --decode
echo ""

#------------------------------------------------------------------------------
# Phase 2: Infrastructure Components
#------------------------------------------------------------------------------
echo "🏠 Phase 2: Installing infrastructure components..."

# Add Helm repositories
echo "  • Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update

# Install Nginx Ingress Controller
echo "  • Installing Nginx Ingress Controller..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

#------------------------------------------------------------------------------
# Phase 3: Monitoring Stack
#------------------------------------------------------------------------------
echo "📈 Phase 3: Installing monitoring stack..."

# Install Prometheus Stack
echo "  • Installing Prometheus + Grafana stack..."
helm upgrade --install kube-prometheus-stack \
  --create-namespace \
  --namespace kube-prometheus-stack \
  -f monitoring_cluster/alertmanager-config.yaml \
  --set grafana.service.type=LoadBalancer \
  prometheus-community/kube-prometheus-stack

# Install Discord Bridge
echo "  • Installing Discord alerting bridge..."
kubectl apply -f monitoring_cluster/discord-bridge.yaml

#------------------------------------------------------------------------------
# Phase 4: Logging Stack
#------------------------------------------------------------------------------
echo "📝 Phase 4: Installing logging stack..."

# Create logging namespace
echo "  • Creating logging namespace..."
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -

# Install Loki
echo "  • Installing Loki (log aggregation)..."
helm upgrade --install loki grafana/loki \
  --namespace logging \
  -f logging/loki-values.yaml

# Install Promtail
echo "  • Installing Promtail (log collection)..."
helm upgrade --install promtail grafana/promtail \
  --namespace logging \
  -f logging/promtail-values.yaml

# Wait for Loki to be ready
echo "  • Waiting for Loki to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=loki -n logging --timeout=300s
sleep 30

# Configure Grafana datasource
echo "  • Adding Loki datasource to Grafana..."
kubectl apply -f logging/loki-datasource.yaml
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n kube-prometheus-stack

#------------------------------------------------------------------------------
# Phase 5: Application Deployment
#------------------------------------------------------------------------------
echo "🐍 Phase 5: Deploying Snake Game application..."

# Deploy Snake Game
echo "  • Creating snakegame namespace..."
kubectl create namespace snakegame --dry-run=client -o yaml | kubectl apply -f -

echo "  • Deploying Snake Game frontend..."
kubectl apply -f snakegame/snakegame.yaml
kubectl apply -f snakegame/ingress.yaml

#------------------------------------------------------------------------------
# Phase 6: Access Information
#------------------------------------------------------------------------------
echo "🔗 Phase 6: Gathering access information..."

# Get service URLs
echo ""
echo "==============================================="
echo "🎮 APPLICATION URLS"
echo "==============================================="

echo "🐍 Snake Game:"
echo "   LoadBalancer: http://$(kubectl get svc snake-frontend-service -n snakegame -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'pending...')"

echo ""
echo "📊 Grafana Dashboard:"
echo "   LoadBalancer: http://$(kubectl get svc kube-prometheus-stack-grafana -n kube-prometheus-stack -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'pending...')"
echo "   Username: admin"
echo "   Password: $(kubectl --namespace kube-prometheus-stack get secrets kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d 2>/dev/null || echo 'retrieving...')"

#------------------------------------------------------------------------------
# Phase 7: Port Forwarding Setup
#------------------------------------------------------------------------------
echo ""
echo "==============================================="
echo "🌐 LOCAL ACCESS (Port Forwarding)"
echo "==============================================="

# Clean up existing port forwards
echo "  • Cleaning up existing port forwards..."
pkill -f "kubectl.*port-forward" 2>/dev/null || true
sleep 2

# Setup port forwarding
echo "  • Setting up port forwarding..."
kubectl --namespace kube-prometheus-stack port-forward svc/kube-prometheus-stack-grafana 3000:80 >/dev/null 2>&1 &
kubectl --namespace kube-prometheus-stack port-forward svc/kube-prometheus-stack-prometheus 8081:9090 >/dev/null 2>&1 &
kubectl --namespace kube-prometheus-stack port-forward svc/kube-prometheus-stack-alertmanager 8082:9093 >/dev/null 2>&1 &

echo ""
echo "📊 Grafana:      http://localhost:3000"
echo "📈 Prometheus:   http://localhost:8081"
echo "🚨 Alertmanager: http://localhost:8082"

echo ""
echo "==============================================="
echo "✅ SETUP COMPLETE!"
echo "==============================================="
echo "Your EKS monitoring stack is now ready!"
echo "Access the applications using the URLs above."
echo ""