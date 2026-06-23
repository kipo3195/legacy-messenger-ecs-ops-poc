#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${1:-}"
DESIRED_COUNT="${2:-}"

if [[ -z "$SERVICE_NAME" || -z "$DESIRED_COUNT" ]]; then
  echo "Usage: $0 <service-name> <desired-count>"
  echo "Example: $0 ws-service 1"
  exit 1
fi

if [[ -z "${AWS_REGION:-}" || -z "${CLUSTER_NAME:-}" ]]; then
  echo "AWS_REGION and CLUSTER_NAME must be set."
  echo "Run: source .env"
  exit 1
fi

aws ecs update-service \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --desired-count "$DESIRED_COUNT" \
  --query 'service.{
    serviceName:serviceName,
    desiredCount:desiredCount,
    runningCount:runningCount,
    pendingCount:pendingCount,
    status:status
  }' \
  --output table