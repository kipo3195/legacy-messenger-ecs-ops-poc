#!/bin/bash

set -e

AWS_REGION="${AWS_REGION:-ap-northeast-2}"

TARGET_GROUP_ARN="$1"

if [ -z "$TARGET_GROUP_ARN" ]; then
  echo "Usage: $0 <target-group-arn>"
  echo "Example: $0 arn:aws:elasticloadbalancing:ap-northeast-2:xxxx:targetgroup/xxx/xxx"
  exit 1
fi

aws elbv2 describe-target-health \
  --region "$AWS_REGION" \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --query "TargetHealthDescriptions[*].{TargetId:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason,Description:TargetHealth.Description}" \
  --output table