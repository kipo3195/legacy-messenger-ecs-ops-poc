# WS Service Auto Scaling

## Target

- Cluster: cluster
- Service: ws-service
- Scalable Dimension: ecs:service:DesiredCount
- Min Capacity: 1
- Max Capacity: 2
- Policy Type: Target Tracking
- Metric: ECSServiceAverageCPUUtilization
- Target Value: 50%

## Verification Commands

-- 대상 서비스 정보 확인
```bash
aws application-autoscaling describe-scalable-targets \
  --service-namespace ecs \
  --resource-ids service/cluster/ws-service \
  --region ap-northeast-2
  ```

- 정책 확인
```bash
aws application-autoscaling describe-scaling-policies \
  --service-namespace ecs \
  --resource-id service/cluster/ws-service \
  --scalable-dimension ecs:service:DesiredCount \
  --region ap-northeast-2
```