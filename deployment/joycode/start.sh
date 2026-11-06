#!/bin/bash
set -euo pipefail
: "${MYSQL_URL:?MYSQL_URL is required}"
: "${MYSQL_PASSWORD:?MYSQL_PASSWORD is required}"
: "${MINIO_SECRET_KEY:?MINIO_SECRET_KEY is required}"
: "${JWT_SIGNING_SECRET:?JWT_SIGNING_SECRET is required}"
if [[ "${SECURITY_ENABLED:-true}" != "true" || "${APP_E2E_FIXTURES_ENABLED:-false}" != "false" ]]; then
  printf '%s\n' 'Competition cloud requires authenticated access and disabled synthetic identity fixtures.' >&2
  exit 1
fi
export SERVER_PORT=8081 SERVER_ADDRESS=127.0.0.1 PORT=3000 HOSTNAME=127.0.0.1
export BUSINESS_API_BASE_URL=http://127.0.0.1:8081
api_pid='' web_pid='' nginx_pid=''
cleanup() {
  trap - TERM INT EXIT
  for pid in "$nginx_pid" "$web_pid" "$api_pid"; do
    if [[ -n "$pid" ]]; then kill -TERM "$pid" 2>/dev/null || true; fi
  done
  wait 2>/dev/null || true
}
trap cleanup TERM INT EXIT
java -XX:MaxRAMPercentage=45 -jar /app/api.jar & api_pid=$!
node /app/web/server.js & web_pid=$!
ready=false
for ((attempt=0; attempt<110; attempt++)); do
  kill -0 "$api_pid" "$web_pid" 2>/dev/null || exit 1
  if curl --fail --silent http://127.0.0.1:8081/actuator/health >/dev/null \
      && curl --fail --silent http://127.0.0.1:3000/assistant >/dev/null; then ready=true; break; fi
  sleep 1
done
[[ "$ready" == "true" ]] || exit 1
nginx -c /app/nginx.conf -g 'daemon off;' & nginx_pid=$!
set +e
wait -n "$api_pid" "$web_pid" "$nginx_pid"
result=$?
set -e
# Even a child exiting successfully unexpectedly means the combined application is no longer available.
if [[ "$result" == "0" ]]; then result=1; fi
exit "$result"
