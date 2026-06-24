#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-}"
PORT="${2:-}"

if [[ -z "$HOST" || -z "$PORT" ]]; then
  echo "Usage: $0 <host> <port>"
  echo "Example: $0 ds.ucware.local 33000"
  exit 1
fi

echo "Testing TCP connectivity"
echo "Host: $HOST"
echo "Port: $PORT"

if command -v nc >/dev/null 2>&1; then
  echo "Method: nc -vz"
  nc -vz "$HOST" "$PORT"
else
  echo "Method: bash /dev/tcp"
  timeout 3 bash -c "echo > /dev/tcp/$HOST/$PORT"
fi

echo "Connection: SUCCESS"