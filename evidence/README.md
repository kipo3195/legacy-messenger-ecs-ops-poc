# Evidence Index

이 디렉터리는 Legacy Messenger ECS Ops POC에서 수행한 주요 검증 결과를 정리합니다.

| Category | Evidence | Validates | Related Docs |
|---|---|---|---|
| Final State | `01-final-state/ecs-services-list.png` | ECS Service 기반 실행 상태 | `docs/01-overview.md`, `docs/06-result-summary.md` |
| Final State | `01-final-state/ecr-images.png` | ECR 이미지 기반 배포 구조 | `docs/03-deployment-flow.md` |
| Load Balancer | `02-load-balancer/alb-ws-target-healthy.png` | WS ALB Target Group healthy | `infra/load-balancer.md`, `docs/02-architecture.md` |
| Load Balancer | `02-load-balancer/tg-ds-33001-healthy.png` | DS NLB 33001 Target healthy | `infra/load-balancer.md`, `docs/05-troubleshooting.md` |
| Operation Scripts | `03-operation-scripts/scale-service-ws-1-to-2.txt` | ECS desired count 기반 scale-out | `docs/04-operation-scenarios.md` |
| Operation Scripts | `03-operation-scripts/force-new-deployment-ws.txt` | force new deployment 기반 재배포 | `docs/03-deployment-flow.md` |
| Troubleshooting | `04-troubleshooting/4.1-resource-constraint-network-mode/03-network-mode-decision-summary.md` | bridge/awsvpc 혼합 설계 근거 | `docs/02-architecture.md`, `docs/05-troubleshooting.md` |
| Troubleshooting | `04-troubleshooting/4.2-cloudmap-srv-compatibility/02-cloudmap-ds-nslookup-success.txt` | Cloud Map A Record DNS 해석 | `infra/service-discovery.md` |
| Troubleshooting | `04-troubleshooting/4.2-cloudmap-srv-compatibility/03-cloudmap-ds-port-connectivity-success.txt` | 내부 DS 33000 연결 성공 | `docs/05-troubleshooting.md` |
| Troubleshooting | `04-troubleshooting/4.3-nlb-dns-connectivity/04-nlb-ip-connectivity-test.txt` | NLB 응답 IP별 TCP 연결 검증 | `docs/05-troubleshooting.md` |