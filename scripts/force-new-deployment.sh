#!/bin/bash

set -e

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
CLUSTER_NAME="${CLUSTER_NAME:-ucware-cluster}"

SERVICE_NAME="$1"

if [ -z "$SERVICE_NAME" ]; then
  echo "Usage: $0 <ecs-service-name>"
  echo "Example: $0 ucware-ws-service"
  exit 1
fi

aws ecs update-service \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --force-new-deployment \
  --query "service.{Service:serviceName,Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount,TaskDefinition:taskDefinition}" \
  --output table