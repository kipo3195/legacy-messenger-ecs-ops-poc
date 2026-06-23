#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-}"
PORT="${2:-}"

if [[ -z "$HOST" || -z "$PORT" ]]; then
  echo "Usage: $0 <host> <port>"
  echo "Example: $0 ds.service.local 33000"
  exit 1
fi

echo "Testing TCP connectivity"
echo "Host: $HOST"
echo "Port: $PORT"

nc -vz "$HOST" "$PORT"