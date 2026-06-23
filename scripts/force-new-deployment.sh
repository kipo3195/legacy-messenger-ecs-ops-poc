#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${1:-}"

if [[ -z "$SERVICE_NAME" ]]; then
  echo "Usage: $0 <service-name>"
  echo "Example: $0 ws-service"
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
  --force-new-deployment \
  --query 'service.{
    serviceName:serviceName,
    desiredCount:desiredCount,
    runningCount:runningCount,
    pendingCount:pendingCount,
    status:status,
    taskDefinition:taskDefinition
  }' \
  --output table