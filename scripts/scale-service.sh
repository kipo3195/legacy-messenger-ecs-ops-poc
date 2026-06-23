#!/bin/bash

set -e

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
CLUSTER_NAME="${CLUSTER_NAME:-cluster}"

SERVICE_NAME="$1"
DESIRED_COUNT="$2"

if [ -z "$SERVICE_NAME" ] || [ -z "$DESIRED_COUNT" ]; then
  echo "Usage: $0 <ecs-service-name> <desired-count>"
  echo "Example: $0 ws-service 1"
  echo "Example: $0 ws-service 0"
  exit 1
fi

aws ecs update-service \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --desired-count "$DESIRED_COUNT" \
  --query "service.{Service:serviceName,Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount}" \
  --output table