# ucware-ws-service

## 1. Service Overview

| 항목 | 값 |
| --- | --- |
| Cluster | ucware-cluster |
| Launch Type | ECS EC2 |
| Service Name | ucware-ws-service |
| Desired Count | 1~2 |
| Network Mode | bridge |
| Load Balancer | ALB |
| Target Group | ws-target-group |
| Health Check Path | /health |

## 2. 주요 구성 의도

Websocket Service는 HTTP/WebSocket 요청을 처리하므로 ALB에 연결했습니다.  
ECS EC2 환경에서 단일 인스턴스 자원 한계를 고려하여 bridge mode로 구성하고, Auto Scaling 검증 대상 서비스로 사용했습니다.

## 3. 검증 항목

- ALB Target Group Healthy 확인
- `/health` 200 응답 확인
- 로그인 요청 정상 처리
- Desired Count 1 → 2 변경 시 Task 증가 확인