# 02. Architecture

## 1. Target Architecture

## 2. 서비스 구성

| Service | Role | Port | ECS Network Mode | Load Balancer | 비고 |
|---|---|---:|---|---|---|

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