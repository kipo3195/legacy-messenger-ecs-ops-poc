# 02. Architecture

## 1. Target Architecture

![ECS Architecture](../architecture/ecs-architecture.png)

본 POC에서는 기존 레거시 메신저 서비스를 ECS EC2 기반 클러스터 위에서 실행하도록 구성했다.
HTTP/Websocket 기반 WS 서비스는 ALB를 통해 라우팅하고, TCP 기반 서비스는 NLB Listener를 통해 외부 접근을 구성했다.

ECS Task는 서비스 특성에 따라 bridge mode와 awsvpc mode를 혼합하여 사용했다.
다수 서비스는 제한된 EC2 리소스 내에서 여러 서비스를 실행하기 위해 bridge mode를 사용했다.
Dispatcher 서비스는 내부 서비스들이 고정 DNS 기반으로 접근해야 하는 특성이 있어 awsvpc mode로 구성했다.

## 2. 서비스 구성

| Service | Role              |        Port | ECS Network Mode | Load Balancer | 비고                |
| ------- | ----------------- | ----------: | ---------------- | ------------- | ----------------- |
| Websocket      | 웹 클라이언트 로그인, HTTP/WebSocket 요청 처리  |       33002 | bridge           | ALB           | HTTP / WebSocket         |
| Dispatcher      | 클라이언트 공통 정보 제공 및 서비스 간 이벤트 전송  | 33000/33001 | awsvpc           | NLB           | 내부/외부 TCP         |
| Certify      | 클라이언트 인증 처리     |       33006 | bridge           | NLB           | TCP            |
| Notificator      | 클라이언트 실시간 이벤트 송수신    |       33004 | bridge           | NLB           | TCP |
| Presence      | 사용자 상태 및 정보 관리       |       33003 | bridge           | NLB           | TCP               |
| Fetch   | 채팅, 쪽지 등 데이터 조회   |       33007 | bridge           | NLB           | TCP               |
| File      | 파일 관련 요청 처리      |       33008 | bridge           | NLB           | TCP               |


## 3. ECS Cluster 구성

## 4. Network Mode 설계

### 4.1 bridge mode 적용 서비스

### 4.2 awsvpc mode 적용 서비스

### 4.3 bridge와 awsvpc를 혼합한 이유

## 5. Load Balancer 설계

### 5.1 ALB 적용 대상

### 5.2 NLB 적용 대상

### 5.3 ALB/NLB를 분리한 이유

## 6. Service Discovery 설계

### 6.1 Cloud Map 적용 목적

### 6.2 SRV Record 검토

### 6.3 A Record 기반 접근으로 조정한 이유

## 7. Security Group 설계

## 8. Architecture Decision Summary