#!/usr/bin/env bash
set -euo pipefail
#MISE description="Forward the shared Postgres to localhost, restarting after every dropped connection"

port="${1:-15432}"

echo "postgres: localhost:$port, user app, password:"
echo "  kubectl -n postgres get secret main-app -o jsonpath='{.data.password}' | base64 -d"

# kubectl exits when a single forwarded connection is reset, so restart it until Ctrl-C.
trap 'exit 0' INT
while true; do
  kubectl -n postgres port-forward svc/main-rw "$port:5432" || true
  sleep 1
done
