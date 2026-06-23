#!/bin/bash

set -e

HOST="$1"
PORT="$2"

if [ -z "$HOST" ] || [ -z "$PORT" ]; then
  echo "Usage: $0 <host> <port>"
  echo "Example: $0 ds.service.local 33000"
  echo "Example: $0 nlb-example.elb.ap-northeast-2.amazonaws.com 33001"
  exit 1
fi

echo "Testing TCP connectivity"
echo "Host: $HOST"
echo "Port: $PORT"
echo

nc -vz "$HOST" "$PORT"