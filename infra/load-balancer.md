# Load Balancer Configuration

## 1. Load Balancer 구성 요약

| Service | Load Balancer | Protocol | Listener Port | Target Port | Health Check |
| --- | --- | --- | ---: | --- | --- |
| WS | ALB | HTTP/WebSocket | 80/443 | ECS registered port | HTTP /health |
| DS | NLB | TCP | 33001 | 33001 | TCP |
| CS | NLB | TCP | 33006 | 33006 | TCP |
| FETCH | NLB | TCP | 33007 | 33007 | TCP |
| FS | NLB | TCP | 33008 | 33008 | TCP |
| NS | NLB | TCP | 33004 | 33004 | TCP |
| PS | NLB | TCP | 33003 | 33003 | TCP |

## 2. ALB 적용 기준

- HTTP 요청 및 WebSocket Upgrade 요청 처리
- URL Path 기반 Health Check 적용 가능
- L7 기반 라우팅이 필요한 서비스

## 3. NLB 적용 기준

- HTTP가 아닌 TCP 기반 레거시 통신 구조 유지
- 기존 클라이언트가 서비스별 포트로 접근하던 방식 유지
- HTTP Path 기반 Health Check 적용이 어려운 서비스

## 4. Target Group 검증 기준

- Target Group에 ECS Task 또는 EC2 Instance가 정상 등록되었는지 확인
- Target Health 상태가 Healthy인지 확인
- NLB는 본 POC에서 기존 클라이언트 포트 접근 방식을 유지하기 위해 Listener Port와 Target Port를 동일하게 구성
- ALB는 외부 80/443 Listener로 요청을 수신하고, ECS가 Target Group에 등록한 포트로 요청을 전달
- bridge 모드에서는 containerPort와 hostPort가 다를 수 있으므로 Target Group에 등록된 실제 포트를 확인
- Target Port에 대해 ECS Task 또는 EC2 Instance의 Security Group inbound 허용 여부 확인