#!/usr/bin/env sh
set -eu

AZMCP_URL="${AZMCP_URL:-http://127.0.0.1:5001}"
PROXY_URL="${PROXY_URL:-http://0.0.0.0:8080}"

export AZURE_MCP_INCLUDE_PRODUCTION_CREDENTIALS="${AZURE_MCP_INCLUDE_PRODUCTION_CREDENTIALS:-true}"
export ALLOW_INSECURE_EXTERNAL_BINDING="${ALLOW_INSECURE_EXTERNAL_BINDING:-true}"

if [ -n "${APPLICATIONINSIGHTS_CONNECTION_STRING:-}" ] && [ "${AZURE_MCP_COLLECT_TELEMETRY:-}" = "true" ]; then
    echo "[entrypoint] Application Insights telemetry enabled with connection string"
fi

echo "[entrypoint] Starting Azure Mcp Server on ${AZMCP_URL} with namespace: postgres"
AZURE_TOKEN_CREDENTIALS=managedidentitycredential ASPNETCORE_URLS="${AZMCP_URL}" /opt/azmcp/azmcp server start --enable-insecure-transports --namespace postgres --mode all &
AZMCP_PID=$!

echo "[entrypoint] Starting Proxy Mcp Server on ${PROXY_URL}"
ASPNETCORE_URLS="${PROXY_URL}" dotnet AzMcpPostgresServer.dll &
PROXY_PID=$!

term() {
  echo "[entrypoint] Termination signal received. Shutting down..."
  kill $AZMCP_PID $PROXY_PID 2>/dev/null || true
  wait $AZMCP_PID $PROXY_PID 2>/dev/null || true
  exit 0
}

trap term INT TERM

echo "[entrypoint] Both processes started (azmcp PID=$AZMCP_PID, proxy PID=$PROXY_PID)"

while kill -0 $AZMCP_PID 2>/dev/null && kill -0 $PROXY_PID 2>/dev/null; do
  sleep 5
done

wait $AZMCP_PID || AZMCP_STATUS=$?
wait $PROXY_PID || PROXY_STATUS=$?

echo "[entrypoint] azmcp exit code: ${AZMCP_STATUS:-0}"
echo "[entrypoint] proxy exit code: ${PROXY_STATUS:-0}"

if [ "${AZMCP_STATUS:-0}" -ne 0 ]; then exit "$AZMCP_STATUS"; fi
if [ "${PROXY_STATUS:-0}" -ne 0 ]; then exit "$PROXY_STATUS"; fi
exit 0