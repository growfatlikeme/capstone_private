#!/bin/bash

echo "🚀 Starting EKS Monitoring Stack Setup..."

# Update kubeconfig
aws eks update-kubeconfig --name growfattest-cluster --region ap-southeast-1

# Install OpenLens service account
echo "💬 Adding OpenLens access..."
kubectl apply -f openlens.yaml
kubectl -n kube-system get secret openlens-access-token -o jsonpath="{.data.token}" | base64 --decode


# Install EBS CSI driver addon early (required for PVCs)
echo "💾 Installing EBS CSI driver..."
aws eks create-addon --cluster-name growfattest-cluster --addon-name aws-ebs-csi-driver --region ap-southeast-1 2>/dev/null || echo "EBS CSI driver already exists"
echo "⏳ Waiting for EBS CSI driver to be ready..."
sleep 30  # Give it time to install


# Phase 2: Setup EKS Observability
# Add Helm repos
echo "📋 Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ 2>/dev/null || true
helm repo update

# Install Nginx Ingress Controller
echo "🌐 Installing Nginx Ingress Controller..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# Install cert-manager
echo "🔒 Installing cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

# Install external-dns
echo "🌍 Installing external-dns..."
helm upgrade --install external-dns external-dns/external-dns \
  --namespace kube-system \
  --set provider=aws \
  --set aws.region=ap-southeast-1 \
  --set txtOwnerId=growfattest-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::255945442255:role/external-dns-role

# Wait for cert-manager to be ready
echo "⏳ Waiting for cert-manager to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=300s

# Apply ClusterIssuer
echo "🔐 Applying ClusterIssuer..."
kubectl apply -f snakegame/clusterissuer.yaml

# Install Prometheus Stack
echo "📊 Installing Prometheus Stack..."
helm upgrade --install kube-prometheus-stack \
  --create-namespace \
  --namespace kube-prometheus-stack \
  -f monitoring_cluster/alertmanager-config.yaml \
  --set grafana.service.type=LoadBalancer \
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

# Wait for Loki to be ready
echo "⏳ Waiting for Loki to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=loki -n logging --timeout=300s
sleep 30  # Additional buffer for Loki to fully initialize

# Add Loki datasource to Grafana
echo "🔗 Adding Loki datasource to Grafana..."
kubectl apply -f logging/loki-datasource.yaml
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n kube-prometheus-stack

# Deploy Snake Game Frontend
echo "🐍 Deploying Snake Game Frontend..."
kubectl create namespace snakegame --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f snakegame/snakegame.yaml
kubectl apply -f snakegame/ingress.yaml

# Get Snake Game URLs
echo "🎮 Snake Game URLs:"
echo "🐍 DNS URL: https://g3-snakegame.sctp-sandbox.com"
echo "🐍 LoadBalancer URL:"
kubectl get svc snake-frontend-service -n snakegame -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' && echo



# Port Forwarding for UI Access
echo "🌐 Cleaning up existing port forwards..."
pkill -f "kubectl.*port-forward" 2>/dev/null || true
sleep 2

echo "🌐 Setting up port forwarding for UI access..."
echo "📊 Grafana UI: http://localhost:3000"
kubectl --namespace kube-prometheus-stack port-forward svc/kube-prometheus-stack-grafana 3000:80 &

echo "📈 Prometheus UI: http://localhost:8081"
kubectl --namespace kube-prometheus-stack port-forward svc/kube-prometheus-stack-prometheus 8081:9090 &

echo "🚨 Alertmanager UI: http://localhost:8082"
kubectl --namespace kube-prometheus-stack port-forward svc/kube-prometheus-stack-alertmanager 8082:9093 &

echo "✅ All services are now accessible via port forwarding!"

# Get Grafana LoadBalancer endpoint
echo "🔗 Getting Grafana LoadBalancer endpoint..."
echo "📊 Grafana LoadBalancer URL:"
kubectl get svc kube-prometheus-stack-grafana -n kube-prometheus-stack -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' && echo
echo "   Username: admin"
echo "   Password: $(kubectl --namespace kube-prometheus-stack get secrets kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d)"