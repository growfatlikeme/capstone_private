#!/usr/bin/env bash
set -euo pipefail

NS="${1:-logging}"

get_pod() {
  kubectl get pod -n "$NS" -l app.kubernetes.io/name=promtail \
    -o jsonpath='{.items[0].metadata.name}'
}

POD="$(get_pod)"
echo
echo "🛠 Promtail pod: $POD (ns: $NS)"
echo "-------------------------------------------------------"

echo
echo "🔍 Checking mounts for /var/log or /var/log/pods"
if kubectl exec -n "$NS" "$POD" -- grep -E " /(var/log|var/log/pods) " /proc/mounts >/dev/null; then
  kubectl exec -n "$NS" "$POD" -- awk '$2 ~ /\/var\/log(\/pods)?/ {print "   ✓ mount:", $2, "->", $1}' /proc/mounts
else
  echo "   ✗ Neither /var/log nor /var/log/pods is mounted; Promtail can't see host pod logs"
  exit 1
fi

echo
echo "📂 Listing a few pod log dirs"
kubectl exec -n "$NS" "$POD" -- sh -lc 'ls -1 /var/log/pods 2>/dev/null | head -n 5 || true'

echo
echo "📄 Checking for container 0.log files"
kubectl exec -n "$NS" "$POD" -- sh -lc '
  for d in $(ls -1 /var/log/pods 2>/dev/null | head -n 3); do
    ls -1 /var/log/pods/"$d"/*/0.log 2>/dev/null | head -n 2
  done || true
'

echo
echo "📡 Checking live config URL"
kubectl exec -n "$NS" "$POD" -- grep -E "url: .*loki-gateway" /etc/promtail/promtail.yaml || true

echo
echo "🧪 Hitting Loki push endpoint from inside the pod (expect 405)"
kubectl exec -n "$NS" "$POD" -- sh -lc 'wget -S -O- http://loki-gateway.logging.svc.cluster.local:3100/loki/api/v1/push 2>&1 | sed -n "1,10p"' || true

echo
echo "📦 Checking Promtail logs for tailing/batch activity"
if kubectl logs -n "$NS" "$POD" --tail=400 | grep -E "Tailing file|tail routine: started" >/dev/null; then
  echo "   ✓ Tailing detected"
else
  echo "   ⚠ No tailing lines in last 400 lines (yet)"; fi

if kubectl logs -n "$NS" "$POD" --tail=400 | grep -E "client: batch sent" >/dev/null; then
  echo "   ✓ Batches sent"
else
  echo "   ⚠ No 'batch sent' yet — generating a quick test line…"
  # Best-effort: find a workload pod and emit a line to stderr (goes to container log)
  ANY_NS=$(kubectl get ns -o jsonpath='{.items[0].metadata.name}')
  ANY_POD=$(kubectl get pod -A --no-headers | awk 'NR==1{print $1,$2}')
  if [ -n "$ANY_POD" ]; then
    NS2=$(echo "$ANY_POD" | awk '{print $1}'); POD2=$(echo "$ANY_POD" | awk '{print $2}')
    echo "   → Emitting test log in $NS2/$POD2 (if shell exists)"
    kubectl exec -n "$NS2" "$POD2" -- sh -lc 'echo "PromtailTest $(date -u +%FT%TZ)" 1>&2' >/dev/null 2>&1 || true
    sleep 3
    kubectl logs -n "$NS" "$POD" --tail=400 | grep -E "client: batch sent" >/dev/null && echo "   ✓ Batches now sending" || echo "   ⚠ Still no 'batch sent' visible"
  fi
fi

echo
echo "✅ Done"
