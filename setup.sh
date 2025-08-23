#!/bin/bash

echo "🚀 Starting EKS Monitoring Stack Setup..."

# Update kubeconfig
aws eks update-kubeconfig --name growfattest-cluster --region ap-southeast-1

# Install EBS CSI driver addon early (required for PVCs)
echo "💾 Installing EBS CSI driver..."
aws eks create-addon --cluster-name growfattest-cluster --addon-name aws-ebs-csi-driver --region ap-southeast-1 2>/dev/null || echo "EBS CSI driver already exists"
echo "⏳ Waiting for EBS CSI driver to be ready..."
sleep 30  # Give it time to install

# Install OpenLens service account
echo "💬 Adding OpenLens access..."
kubectl apply -f openlens.yaml
kubectl -n kube-system get secret openlens-access-token -o jsonpath="{.data.token}" | base64 --decode

# Phase 2: Setup EKS Observability
# Add Helm repos
echo "📋 Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

# Install Prometheus Stack
echo "📊 Installing Prometheus Stack..."
helm upgrade --install kube-prometheus-stack \
  --create-namespace \
  --namespace kube-prometheus-stack \
  -f monitoring_cluster/alertmanager-config.yaml \
  --set grafana.service.type=LoadBalancer \
  --set grafana.additionalDataSources[0].name=Loki \
  --set grafana.additionalDataSources[0].type=loki \
  --set grafana.additionalDataSources[0].url=http://loki.logging.svc.cluster.local:3100 \
  prometheus-community/kube-prometheus-stack

# Retrieving Grafana 'admin' user password
echo "🔑 Retrieving Grafana 'admin' user password..."
kubectl --namespace kube-prometheus-stack get secrets kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo

# Install Discord Bridge
echo "💬 Installing Discord Bridge..."
kubectl apply -f monitoring_cluster/discord-bridge.yaml

# Install Loki Stack
echo "📝 Installing Loki for logging..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create logging namespace
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -

# Install Loki
helm upgrade --install loki grafana/loki \
  --namespace logging \
  -f logging/loki-values.yaml

# Install Promtail
helm upgrade --install promtail grafana/promtail \
  --namespace logging \
  -f logging/promtail-values.yaml
