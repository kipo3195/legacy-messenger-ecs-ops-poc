# Security Group Configuration

## 1. 보안그룹 구성 원칙

- 외부 접근은 ALB/NLB Listener Port 기준으로 제한
- ECS Worker Node는 필요한 서비스 포트만 허용
- 내부 서비스 간 통신은 VPC 내부 대역 기준으로 허용
- 테스트 목적의 전체 오픈 규칙은 운영 기준에서 제외

## 2. Port 정책

| Port | Service | 접근 주체 | 용도 |
| ---: | --- | --- | --- |
| 33000 | DS | Internal Services | 내부 Dispatcher 접근 |
| 33001 | DS | NLB | 외부 TCP 접근 |
| 33002 | WS | ALB | HTTP/WebSocket |
| 33003 | PS | NLB | 외부 TCP 접근 |
| 33004 | NS | NLB | 외부 TCP 접근 |
| 33006 | CS | NLB | 인증 TCP 접근 |
| 33007 | FETCH | NLB | 조회 서비스 접근 |
| 33008 | FS | NLB | 파일 서비스 접근 |

## 3. Troubleshooting 연계

Security Group 설정 오류는 Target Group Unhealthy, TCP Timeout, 내부 서비스 연결 실패의 주요 원인이었습니다.