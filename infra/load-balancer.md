# Load Balancer Configuration

## 1. Load Balancer 구성 요약

| Service | Load Balancer | Protocol | Listener Port | Target Port | Health Check |
| --- | --- | --- | ---: | ---: | --- |
| WS | ALB | HTTP/WebSocket | 80/443 | 33002 | HTTP /health |
| DS | NLB | TCP | 33001 | 33001 | TCP |
| CS | NLB | TCP | 33006 | 33006 | TCP |
| FETCH | NLB | TCP | 33007 | 33007 | TCP |
| FS | NLB | TCP | 33008 | 33008 | TCP |
| NS | NLB | TCP | 33004 | 33004 | TCP |
| PS | NLB | TCP | 33003 | 33004 | TCP |

## 2. ALB 적용 기준

- HTTP / WebSocket 기반 요청 처리
- Health Check Path 사용 가능
- L7 라우팅이 필요한 서비스

## 3. NLB 적용 기준

- TCP 기반 레거시 프로토콜 유지
- 기존 클라이언트 포트 접근 방식 유지
- HTTP Health Check를 적용하기 어려운 서비스

## 4. Target Group 검증 기준

- Target 등록 여부
- Healthy 상태 여부
- Listener Port와 Target Port 일치 여부
- Security Group inbound 허용 여부