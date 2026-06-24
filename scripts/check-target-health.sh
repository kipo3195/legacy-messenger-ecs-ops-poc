#!/usr/bin/env bash
set -euo pipefail

TARGET_GROUP_NAME_OR_ARN="${1:?Usage: ./check-target-health.sh <target-group-name-or-arn>}"

if [[ "$TARGET_GROUP_NAME_OR_ARN" == arn:* ]]; then
  TARGET_GROUP_ARN="$TARGET_GROUP_NAME_OR_ARN"
else
  TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
    --names "$TARGET_GROUP_NAME_OR_ARN" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)
fi

aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,Target.Port,TargetHealth.State,TargetHealth.Reason,TargetHealth.Description]' \
  --output table