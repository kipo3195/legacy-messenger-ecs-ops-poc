# 01. Project Overview

## 1. 프로젝트 개요

이 프로젝트는 기존 온프레미스 기반으로 운영되던 Java 메신저 서비스를 AWS ECS 기반 컨테이너 운영 환경으로 전환하기 위한 POC입니다.

기존 Java 메신저 서비스는 jar 파일을 서버에 직접 배포하고, 서비스 재기동 및 상태 확인을 수동으로 처리하는 방식에 의존하고 있었습니다. 운영 환경에서 클러스터 환경을 구성하더라도 서버 또는 프로세스 단위로 수동 증설과 운영을 해야 했기 때문에, 트래픽 변화에 따라 Task를 자동으로 확장/축소하는 오토스케일링 기반의 효율적인 자원 운용까지 연결되기 어려운 구조였습니다.

이를 개선하기 위해 기존 서비스를 Docker 이미지로 패키징하고, ECR을 통한 이미지 관리, ECS Task Definition 및 ECS Service 기반 실행 관리, ALB/NLB 기반 외부 접근, Cloud Map 기반 내부 서비스 디스커버리, Auto Scaling 검증을 진행했습니다.

현재 단계에서는 ECS 기반 서비스 구동, 로드밸런서 연동, 내부 DNS 연결, 기존 클라이언트 로그인 및 기본 기능 동작 검증까지 완료했습니다. 이후에는 오토스케일링 환경에서 분산된 Task의 로그와 메트릭을 추적하기 위한 PLG 모니터링 구성과, jar 파일 수동 배포 및 서비스 재기동 절차를 줄이기 위한 GitHub Actions 기반 CI/CD 파이프라인 구성을 후속 작업으로 진행할 예정입니다.

## 2. 프로젝트 목표

본 POC의 주요 목표는 기존 Java 메신저 서비스를 AWS ECS 기반 컨테이너 운영 환경에서 실행하고, 클러스터 환경에서의 배포, 로드밸런싱, 서비스 디스커버리, 확장성, 장애 대응 가능성을 검증하는 것입니다.

### 현재 POC 목표

* 기존 Java 메신저 서비스를 Docker 기반으로 실행 가능하게 구성
* ECR을 통해 서비스 이미지를 버전 단위로 관리
* ECS Task Definition과 ECS Service를 통해 서비스 실행 상태 관리
* ALB/NLB를 활용해 HTTP/WebSocket 및 TCP 서비스 외부 접근 구성
* Cloud Map을 활용해 ECS 내부 서비스 간 DNS 기반 연결 구성
* ECS 네트워크 모드, Target Group, Security Group, Health Check 관련 운영 이슈 분석
* 트래픽 변화에 따른 ECS Service Auto Scaling 가능성 검증
* 기존 클라이언트 로그인 및 채팅, 쪽지 등 메신저 기능 동작 검증

### 후속 확장 목표

* GitHub Actions 기반 CI/CD를 통해 Docker build, ECR push, ECS Service update 자동화
* PLG 모니터링을 통해 오토스케일링 환경에서 분산된 Task의 로그와 메트릭 추적
* Go Controller Service를 통해 ECS Service 상태 조회, 기동/중지, scale, redeploy API 제공

## 3. 기존 구조의 한계

기존 서비스는 온프레미스 환경에서 jar 파일을 서버에 직접 배포하고, 서비스 재기동 및 상태 확인을 수동으로 처리하는 운영 방식에 의존하고 있었습니다.

고객사 환경에 따라 DNS를 구성하거나 여러 서버로 클러스터 환경을 구성할 수는 있었지만, 서비스 증설과 운영은 여전히 서버 또는 프로세스 단위의 수동 작업에 가까웠습니다. 이로 인해 트래픽 변화에 따라 서비스를 자동으로 확장/축소하고, 필요한 만큼만 자원을 사용하는 오토스케일링 기반의 효율적인 운영 구조로 연결되기 어려웠습니다.

주요 한계는 다음과 같습니다.

* jar 파일을 서버에 직접 배포하고 서비스 재기동을 수동으로 처리해야 함
* 클러스터 환경을 구성하더라도 서버 또는 프로세스 단위의 수동 증설이 필요함
* 트래픽 변화에 따라 서비스를 자동으로 확장/축소하는 자원 운용 구조가 부족함
* 서비스 상태 확인과 장애 대응이 프로세스 확인, 포트 확인, 개별 서버 로그 확인에 의존함
* 오토스케일링 환경에서 필요한 분산 로그 및 메트릭 관측 체계가 부족함
* 수동 배포, 수동 재기동, 수동 상태 확인 절차로 인해 반복 배포와 운영 자동화에 한계가 있음

## 4. 전환 방향

기존 구조를 다음과 같은 방향으로 전환했습니다.

| 구분 | 기존 방식 | 전환 방향 |
|---|---|---|
| 배포 방식 | jar 파일을 서버에 직접 반영하고 서비스 재기동 | Docker 이미지 기반 배포 |
| 산출물 관리 | 서버별 jar 파일 및 실행 파일 관리 | ECR 기반 Docker 이미지 버전 관리 |
| 실행 방식 | 서버 또는 프로세스 단위 실행 | ECS Task Definition 기반 실행 |
| 서비스 관리 | 수동 기동/중지 및 상태 확인 | ECS Service desired count 기반 관리 |
| 외부 접근 | 고객사 제공 DNS 또는 고정 서버 IP/포트 기반 접근 | ALB/NLB 기반 접근 및 Target Group 라우팅 |
| 내부 연결 | 환경별 서비스 주소/포트 설정 의존 | Cloud Map 기반 DNS 연결 |
| 확장성 | 서버 또는 프로세스 단위 수동 증설 | ECS Service 단위 scale-out/scale-in |
| 상태 확인 | 수동 로그 및 프로세스 확인 | Target Group, ECS Events, CloudWatch 기반 확인 |
| 배포 자동화 | 수동 배포 및 재기동 | GitHub Actions CI/CD 기반 자동화 예정 |
| 운영 관측 | 개별 서버 로그 확인 | PLG 기반 로그/메트릭 관측 예정 |

## 5. 서비스 구성 범위

본 POC에서는 기존 메신저 서비스를 구성하는 주요 서버를 ECS Service 단위로 분리하여 구동했습니다.
각 서비스는 기존 실행 구조를 유지한 상태에서 Docker 이미지로 패키징하고, ECS Task Definition 및 ECS Service를 통해 실행되도록 구성했습니다.

| 구분          | 대상 서비스                |
| ----------- | --------------------- | 
| 웹 클라이언트 접속 계층 | Websocket             |
| 서비스 간 이벤트 디스패치 계층 | Dispatcher            | 
| 인증 계층       | Certify               | 
| 실시간 처리 계층   | Notificator, Presence | 
| 데이터 조회 계층   | Fetch                 | 
| 파일 처리 계층    | File                  | 

서비스별 역할, 포트, ECS Network Mode, Load Balancer, Target Group, Health Check 구성은 `docs/02-architecture.md`와 `infra/` 디렉터리에서 상세히 정리합니다.

## 6. 현재 완료 범위

현재 단계에서는 AWS ECS 기반 운영 환경 구성과 기존 클라이언트 기능 검증까지 완료했습니다.

완료된 구축 범위는 다음과 같습니다.

* 기존 Java 메신저 서비스 Docker 이미지화
* ECR을 통한 서비스 이미지 push
* ECS Cluster 구성
* ECS Task Definition 구성
* ECS Service 기반 서비스 실행
* ALB/NLB 및 Target Group 구성
* Cloud Map 기반 내부 서비스 디스커버리 구성
* Security Group 및 Health Check 설정 조정
* WS 서비스 scale-out/scale-in 검증을 위한 ECS Service 구성
* ECS 운영 중 발생한 주요 이슈 분석 및 해결

Go Controller Service, GitHub Actions CI/CD, PLG Monitoring은 후속 작업으로 계획되어 있으며, 현재 완료 범위에는 포함하지 않았습니다.

## 7. 주요 검증 결과

구성된 ECS 운영 환경이 실제 서비스 흐름에서 동작하는지 다음 항목을 기준으로 검증했습니다.

| 검증 항목 | 검증 내용 | 결과 | 증적 |
|---|---|---|---|
| ECS Service 상태 | 주요 서비스의 desired/running count 정상화 확인 | 성공 | `추후 파일 개별 링크로 변경` |
| Target Group 상태 | ALB/NLB Target Group healthy 상태 확인 | 성공 | `추후 파일 개별 링크로 변경` |
| 외부 접근 | ALB/NLB를 통한 외부 연결 확인 | 성공 | `추후 파일 개별 링크로 변경` |
| 내부 연결 | Cloud Map DNS 기반 서비스 간 내부 연결 확인 | 성공 | `추후 파일 개별 링크로 변경` |
| 클라이언트 기능 | 기존 클라이언트 로그인 성공 확인 | 성공 | `추후 파일 개별 링크로 변경` |
| 메신저 기능 | 채팅, 쪽지 등 기본 기능 동작 확인 | 성공 | `추후 파일 개별 링크로 변경` |
| 확장성 | WS 서비스 scale-out/scale-in 동작 확인 | 성공 | `추후 파일 개별 링크로 변경` |

## 8. 주요 문제 해결 요약

ECS 전환 과정에서 서비스 실행, 로드밸런서 연동, 내부 DNS 연결, Health Check 구성 과정에서 여러 운영 이슈가 발생했습니다.
본 문서에서는 아키텍처 결정과 운영 검증에 직접적인 영향을 준 주요 이슈만 요약하고, 상세 원인 분석과 해결 과정은 `docs/05-troubleshooting.md`에서 정리합니다.

| 문제 | 원인 | 해결 방향 | 상태 | 상세 |
|---|---|---|---|---|
| awsvpc ENI 부족과 Network Mode 재설계 | 모든 서비스를 awsvpc mode로 구성할 경우 Task별 ENI가 필요하여 제한된 EC2 환경에서 다수 서비스 실행과 scale-out에 제약 발생 | Websocket, Certify, Notificator, Presence, Fetch, File은 bridge mode로 구성하고 Dispatcher는 awsvpc mode로 분리 | 해결 | `docs/05-troubleshooting.md` |
| Cloud Map SRV Record 호환 문제 | Cloud Map SRV Record는 host:port 해석이 필요하지만, 기존 레거시 서비스는 일반 Hostname/IP 기반 접근을 전제로 동작 | Dispatcher를 awsvpc mode로 구성하고 Cloud Map A Record 기반 접근으로 조정 | 해결 | `docs/05-troubleshooting.md` |
| NLB Multi-AZ timeout | NLB DNS가 여러 AZ IP로 응답하지만 특정 AZ에 healthy target이 없는 경우 일부 IP 접근 시 timeout 발생 | Target Group health, AZ별 target 배치 상태, NLB 연결 구조를 분석하여 원인 확인 | 분석 완료 | `docs/05-troubleshooting.md` |
| ALB/NLB Target unhealthy와 Health Check 조정 | Health Check path 불일치, Security Group 인바운드 누락, Target Group 포트 설정 오류 등으로 Target unhealthy 발생 | Health Check 경로, 서비스 응답, Target Group 포트, Security Group 규칙을 조정 | 해결 | `docs/05-troubleshooting.md` |

## 9. 향후 확장 계획

현재는 ECS 기반 운영 환경 구성과 기본 기능 검증까지 완료된 상태입니다. 이후 다음 항목을 추가하여 운영 포트폴리오를 확장할 예정입니다.

| 항목                    | 목적                                                | 상태      |
| --------------------- | ------------------------------------------------- | ------- |
| Go Controller Service | ECS 서비스 상태 조회, start/stop, scale, redeploy API 제공 | Planned |
| GitHub Actions CI/CD  | Docker build, ECR push, ECS Service update 자동화    | Planned |
| PLG Monitoring        | Prometheus, Loki, Grafana 기반 로그/메트릭 관측            | Planned |

## 10. 프로젝트 의의

이 프로젝트를 통해 기존 Java 메신저 서비스를 단순히 컨테이너로 실행하는 수준을 넘어, ECS 기반 서비스 실행 관리, 로드밸런싱, 내부 서비스 디스커버리, 확장성 검증, 운영 이슈 대응까지 포함한 클라우드 운영 전환 과정을 검증했습니다.

특히 기존 클라이언트 로그인과 채팅, 쪽지 등 기본 메신저 기능 동작까지 확인함으로써, 실제 서비스 흐름을 유지한 상태에서 ECS 기반 운영 구조로 전환 가능한지 검증했다는 점에 의미가 있습니다.

또한 기존의 jar 수동 배포, 서버 직접 반영, 서비스 재기동, 개별 서버 로그 확인 중심의 운영 방식에서 벗어나, 향후 CI/CD, 오토스케일링, PLG 모니터링, Go Controller Service 기반 운영 자동화로 확장할 수 있는 기반을 마련했습니다.