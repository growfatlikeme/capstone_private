#!/usr/bin/env bash
# promtail-loki-check.sh
# Dynamically checks Promtail and Loki health end-to-end

set -euo pipefail

NAMESPACE_LOGGING="logging"
LOKI_SERVICE="loki-gateway"
TEST_NAMESPACE="snakegame"
TEST_POD_SELECTOR="app=snake-frontend"
TEST_CONTAINER="snake-frontend"

# Pick free local ports
PROMTAIL_LOCAL_PORT=$(shuf -i 20000-25000 -n 1)
LOKI_LOCAL_PORT=$(shuf -i 25001-30000 -n 1)

echo "=== 1. Checking Promtail DaemonSet status ==="
kubectl get pods -n "$NAMESPACE_LOGGING" -l app.kubernetes.io/name=promtail -o wide

echo
echo "=== 2. Checking Promtail active scrape targets (JSON API) ==="
PROMTAIL_POD=$(kubectl get pods -n "$NAMESPACE_LOGGING" -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n "$NAMESPACE_LOGGING" "$PROMTAIL_POD" ${PROMTAIL_LOCAL_PORT}:3101 >/tmp/pf-promtail.log 2>&1 &
PF_PROMTAIL_PID=$!

# Wait for port-forward to be ready
for i in {1..10}; do
  if nc -z localhost ${PROMTAIL_LOCAL_PORT}; then break; fi
  sleep 0.5
done

# Query Promtail's JSON API
if curl -s "http://localhost:${PROMTAIL_LOCAL_PORT}/api/v1/targets" | jq . >/dev/null 2>&1; then
  curl -s "http://localhost:${PROMTAIL_LOCAL_PORT}/api/v1/targets" \
    | jq '.data.activeTargets[] | {job: .labels.job, namespace: .labels.namespace, state: .health}'
else
  echo "Promtail JSON API not available — dumping HTML targets page:"
  curl -s "http://localhost:${PROMTAIL_LOCAL_PORT}/targets"
fi

kill $PF_PROMTAIL_PID
wait $PF_PROMTAIL_PID 2>/dev/null || true

echo
echo "=== 3. Checking Promtail batch sending activity ==="
for pod in $(kubectl get pods -n "$NAMESPACE_LOGGING" -l app.kubernetes.io/name=promtail -o name); do
  echo "--- $pod ---"
  kubectl logs -n "$NAMESPACE_LOGGING" "$pod" | grep "batch sent" || echo "No batches sent yet"
done

echo
echo "=== 4. Port-forwarding to Loki Gateway and checking labels ==="
kubectl port-forward -n "$NAMESPACE_LOGGING" svc/$LOKI_SERVICE ${LOKI_LOCAL_PORT}:3100 >/tmp/pf-loki.log 2>&1 &
PF_LOKI_PID=$!

for i in {1..10}; do
  if nc -z localhost ${LOKI_LOCAL_PORT}; then break; fi
  sleep 0.5
done

echo "--- All labels in Loki ---"
curl -s "http://localhost:${LOKI_LOCAL_PORT}/loki/api/v1/labels" | jq
echo "--- All namespaces in Loki ---"
curl -s "http://localhost:${LOKI_LOCAL_PORT}/loki/api/v1/label/namespace/values" | jq

echo
echo "=== 5. Generating a test log in $TEST_NAMESPACE ==="
TEST_POD=$(kubectl get pod -n "$TEST_NAMESPACE" -l "$TEST_POD_SELECTOR" -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n "$TEST_NAMESPACE" "$TEST_POD" -c "$TEST_CONTAINER" -- \
  sh -c "echo 'LokiTest $(date -u +%Y-%m-%dT%H:%M:%SZ)' >&2"

echo
echo "=== 6. Querying Loki for the test log ==="
START=$(date -u -d '-2 minutes' +%s%N)
END=$(date -u +%s%N)
curl -sG "http://localhost:${LOKI_LOCAL_PORT}/loki/api/v1/query_range" \
  --data-urlencode "query={namespace=\"$TEST_NAMESPACE\"}" \
  --data-urlencode "start=$START" \
  --data-urlencode "end=$END" \
  --data-urlencode "limit=20" | jq '.data.result'

kill $PF_LOKI_PID
wait $PF_LOKI_PID 2>/dev/null || true

echo
echo "=== Done ==="
