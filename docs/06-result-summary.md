# 06. Result Summary

## 1. 프로젝트 결과 요약

본 POC는 기존 온프레미스 기반 Java 메신저 서비스를 AWS ECS EC2 기반 컨테이너 운영 환경으로 전환하기 위한 검증 프로젝트입니다.

기존 구조는 서버에 jar 파일을 직접 배포하고, 관리자 페이지와 Switch Service를 통해 Java Process를 기동/중지하는 방식이었습니다. 이 구조는 단순 운영에는 익숙했지만, 서비스 증설, 배포 이력 관리, 장애 추적, 오토스케일링, 분산 로그/메트릭 관측 측면에서는 한계가 있었습니다.

본 POC에서는 기존 애플리케이션 코드를 크게 변경하지 않고, 실행 단위를 Java Process에서 ECS Task / ECS Service로 전환했습니다. 또한 서비스별 통신 특성에 따라 ALB, NLB, Cloud Map, Target Group, Security Group, Network Mode를 조합하여 기존 메신저 서비스가 ECS 환경에서도 정상 동작할 수 있는지 검증했습니다.

최종적으로 다음 항목을 검증했습니다.

| 구분                        | 결과                                              |
| ------------------------- | ----------------------------------------------- |
| Docker 이미지 기반 실행          | 기존 Java 서비스를 컨테이너 이미지로 패키징                      |
| ECR 이미지 관리                | 서비스 이미지를 ECR에 push하여 ECS에서 참조                   |
| ECS Service 실행            | 주요 메신저 서비스를 ECS Service 단위로 구동                  |
| ALB/NLB 연동                | HTTP/WebSocket 서비스와 TCP 서비스를 분리하여 로드밸런서 구성      |
| Cloud Map 내부 DNS          | Dispatcher 내부 접근을 Private DNS 기반으로 구성           |
| Target Group Health Check | 서비스별 Target 등록 및 healthy 상태 확인                  |
| Scale-out / Scale-in      | Websocket 서비스 기준 desired count 증감 검증            |
| 기존 기능 검증                  | 클라이언트 로그인, 채팅, 쪽지 등 기본 기능 동작 확인                 |
| 운영 이슈 분석                  | ENI, DNS, NLB Multi-AZ, Health Check 문제 분석 및 해결 |

이 프로젝트는 단순히 “Java 서비스를 Docker로 실행했다”는 수준이 아니라, 기존 레거시 운영 구조를 ECS 기반 실행 관리, 로드밸런싱, 내부 서비스 디스커버리, 운영 제어, 장애 분석이 가능한 구조로 전환하기 위한 실질적인 검증입니다.

---

## 2. 최종 구성 요약

본 POC에서는 기존 메신저 서비스를 ECS Service 단위로 분리하여 구성했습니다.

| Service     | 주요 역할                             |          Port | Network Mode | 접근 방식                    |
| ----------- | --------------------------------- | ------------: | ------------ | ------------------------ |
| Websocket   | 웹 클라이언트 로그인, HTTP/WebSocket 요청 처리 |         33002 | bridge       | ALB                      |
| Dispatcher  | 클라이언트 공통 정보 제공 및 서비스 간 Gateway    | 33000 / 33001 | awsvpc       | Cloud Map A Record / NLB |
| Presence    | 사용자 상태 및 정보 관리                    |         33003 | bridge       | NLB                      |
| Notificator | 실시간 이벤트 송수신 처리                    |         33004 | bridge       | NLB                      |
| Certify     | 클라이언트 인증 처리                       |         33006 | bridge       | NLB                      |
| Fetch       | 채팅, 쪽지 등 데이터 조회                   |         33007 | bridge       | NLB                      |
| File        | 파일 관련 요청 처리                       |         33008 | bridge       | NLB                      |

구성의 핵심은 모든 서비스를 동일한 방식으로 ECS에 올리지 않고, 서비스 특성에 따라 네트워크 모드와 접근 방식을 다르게 설계한 점입니다.

Websocket 서비스는 HTTP/WebSocket 요청을 처리하므로 ALB를 적용했습니다. 반면 Dispatcher, Presence, Notificator, Certify, Fetch, File 서비스는 TCP 기반 통신 구조를 유지해야 하므로 NLB를 적용했습니다.

Dispatcher는 내부 서비스들이 공통으로 접근하는 Gateway 역할을 하기 때문에 `awsvpc` mode와 Cloud Map A Record를 적용했습니다. 이를 통해 내부 서비스들은 Task IP를 직접 알 필요 없이 DNS 이름으로 Dispatcher에 접근할 수 있습니다.

---

## 3. 주요 전환 성과

### 3.1 Java Process 중심 운영에서 ECS Service 중심 운영으로 전환

기존 운영 방식은 서버에 접속하여 Java Process, 포트, 로그를 직접 확인하는 구조였습니다.

ECS 전환 후에는 운영 기준을 다음과 같이 변경했습니다.

| 기존 운영 기준             | ECS 운영 기준                               |
| -------------------- | --------------------------------------- |
| Java Process 실행 여부   | ECS Service desired / running count     |
| process start / kill | desired count 변경                        |
| script restart       | force new deployment                    |
| jar 파일 교체            | Docker Image / Task Definition revision |
| 포트 직접 확인             | Target Group health 확인                  |
| 서버 로그 확인             | 컨테이너 로그 및 향후 PLG 기반 로그 추적               |
| 서버 단위 증설             | ECS Service scale-out / scale-in        |

이를 통해 기존 수동 프로세스 운영 방식을 ECS의 표준 운영 모델로 전환할 수 있음을 확인했습니다.

---

### 3.2 기존 single jar 실행 구조를 Task Definition으로 매핑

기존 메신저 서비스는 서비스별로 완전히 다른 jar를 사용하는 구조가 아니라, 동일한 single jar를 기반으로 Main Class, 서비스명, 포트, 실행 인자를 조합하여 실행되는 구조였습니다.

이 구조를 ECS 전환 과정에서도 유지했습니다.

| 기존 실행 요소     | ECS 반영 방식               |
| ------------ | ----------------------- |
| jar path     | Docker Image 내부 app.jar |
| Main Class   | container entryPoint    |
| service name | container command       |
| port         | portMappings            |
| config path  | mountPoints             |
| 실행 스크립트      | Task Definition         |
| Java Process | ECS Task                |

이 방식은 레거시 코드 변경을 최소화하면서도, 실행 단위를 ECS가 관리할 수 있는 Task Definition으로 전환했다는 점에서 의미가 있습니다.

---

### 3.3 ALB/NLB 분리 적용

서비스의 프로토콜 특성에 따라 Load Balancer를 분리했습니다.

| 구분  | 적용 대상                                                   | 선택 이유                                       |
| --- | ------------------------------------------------------- | ------------------------------------------- |
| ALB | Websocket                                               | HTTP/WebSocket 요청 처리 및 HTTP Health Check 적용 |
| NLB | Dispatcher, Presence, Notificator, Certify, Fetch, File | TCP 기반 레거시 포트 통신 유지                         |

이 구성을 통해 HTTP 계층에서 처리해야 하는 Websocket 서비스와, TCP 포트 기반으로 동작하는 레거시 서비스를 분리하여 운영할 수 있었습니다.

---

### 3.4 bridge / awsvpc Network Mode 혼합 구성

초기에는 모든 서비스를 `awsvpc` mode로 구성하는 방식을 검토했지만, 제한된 ECS EC2 환경에서 Task별 ENI가 필요하여 다수 서비스 실행과 scale-out에 제약이 발생했습니다.

이에 따라 서비스 특성에 맞게 Network Mode를 분리했습니다.

| Network Mode | 적용 서비스                                                 | 선택 이유                                                  |
| ------------ | ------------------------------------------------------ | ------------------------------------------------------ |
| bridge       | Websocket, Presence, Notificator, Certify, Fetch, File | 제한된 EC2 리소스 내에서 여러 서비스를 동시에 실행                         |
| awsvpc       | Dispatcher                                             | Cloud Map A Record 기반 내부 DNS 접근을 위해 Task Private IP 필요 |

이 결정은 단순 설정 변경이 아니라, ECS EC2의 리소스 제약, 레거시 서비스의 포트 구조, 내부 서비스 디스커버리 요구사항을 함께 고려한 결과입니다.

---

### 3.5 Cloud Map 기반 내부 서비스 디스커버리 구성

ECS 환경에서는 Task가 재시작되거나 재배치될 수 있으므로, 특정 Task IP를 직접 설정하는 방식은 적합하지 않았습니다.

Dispatcher는 여러 내부 서비스가 공통으로 접근하는 중심 서비스이기 때문에, Cloud Map 기반 Private DNS를 적용했습니다.

초기에는 SRV Record도 검토했지만, 기존 레거시 서비스가 SRV Record를 해석하여 `host:port` 형태로 사용하는 구조가 아니었습니다. 따라서 기존 Hostname/IP 기반 접근 방식과 호환되는 A Record 방식을 선택했습니다.

| 구분               | 최종 선택                    |
| ---------------- | ------------------------ |
| 내부 DNS 방식        | Cloud Map A Record       |
| Dispatcher 내부 접근 | `ds.service.local:33000` |
| Dispatcher 외부 접근 | NLB Listener `33001`     |
| SRV Record       | 기존 코드 호환성 문제로 미적용        |

이를 통해 기존 서비스의 연결 로직을 크게 수정하지 않고, ECS 환경의 동적 Task IP 변경에 대응할 수 있는 구조를 만들었습니다.

---

## 4. 검증 결과

본 POC에서는 ECS 환경에서 서비스가 정상적으로 실행되는지만 확인한 것이 아니라, 실제 운영 관점에서 다음 항목을 검증했습니다.

| 검증 항목           | 검증 내용                                          | 결과 |
| --------------- | ---------------------------------------------- | -- |
| ECS Service 상태  | desired count, running count, pending count 확인 | 성공 |
| Task 실행 상태      | 주요 서비스 Task가 RUNNING 상태인지 확인                   | 성공 |
| Target Group 상태 | ALB/NLB Target Group healthy 상태 확인             | 성공 |
| 외부 접근           | ALB/NLB DNS 및 Listener를 통한 접근 확인               | 성공 |
| 내부 접근           | Cloud Map DNS 기반 Dispatcher 접근 확인              | 성공 |
| 기능 검증           | 기존 클라이언트 로그인, 채팅, 쪽지 기능 확인                     | 성공 |
| Scale-out       | Websocket 서비스 desired count 증가 및 Target 추가 확인  | 성공 |
| Scale-in        | desired count 감소 후 남은 Task 정상 동작 확인            | 성공 |
| 장애 분석           | 주요 ECS 운영 이슈 원인 분석 및 해결                        | 완료 |

특히 기존 클라이언트 기능 검증까지 수행했다는 점이 중요합니다. 단순히 인프라 리소스를 생성한 것이 아니라, 기존 메신저 서비스 흐름이 ECS 환경에서도 유지되는지 확인했습니다.

---

## 5. 주요 문제 해결 결과

ECS 전환 과정에서는 단순 설정 오류뿐 아니라, 레거시 서비스의 실행 방식과 ECS 운영 모델을 맞추는 과정에서 여러 구조적 문제가 발생했습니다.

본 POC에서는 다음 4개 이슈를 중심으로 원인을 분석하고 해결했습니다.

| 이슈                         | 원인                                                                    | 해결 또는 판단                                                |
| -------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------- |
| awsvpc ENI 부족              | 모든 Task에 ENI가 필요하여 제한된 EC2 환경에서 다수 서비스 실행에 제약 발생                      | 대부분의 서비스는 bridge mode, Dispatcher만 awsvpc mode로 분리      |
| Cloud Map SRV Record 호환 문제 | 기존 코드가 SRV Record의 host:port 정보를 해석하지 못함                              | Dispatcher를 awsvpc mode로 구성하고 A Record 기반 접근으로 조정       |
| NLB Multi-AZ timeout       | NLB DNS가 여러 AZ IP로 응답하지만 특정 AZ에 healthy target이 없는 경우 timeout 발생      | IP별 연결 결과, Target Group health, AZ별 Target 배치 상태를 함께 분석 |
| ALB/NLB Target unhealthy   | Health Check path, Security Group, Target Group port, config mount 문제 | Health Check 경로, 인바운드 포트, Target 등록 상태, mountPoint 조정   |

이 과정에서 확인한 핵심은 다음과 같습니다.

```text
ECS Task가 RUNNING 상태라고 해서
서비스가 실제로 외부 요청을 처리할 수 있는 상태라고 단정할 수 없다.

운영 판단 기준은 ECS Service 상태와 함께
Target Group health, Security Group, Health Check, DNS, Port Mapping까지 함께 확인해야 한다.
```

---

## 6. 운영 시나리오 정리

ECS 전환 후 주요 운영 행위는 다음과 같이 정리할 수 있습니다.

| 운영 시나리오   | ECS 처리 방식                             | 확인 기준                                      |
| --------- | ------------------------------------- | ------------------------------------------ |
| 서비스 기동    | desired count를 1 이상으로 변경              | runningCount, Task RUNNING, Target healthy |
| 서비스 중지    | desired count를 0으로 변경                 | runningCount 0, Task STOPPED               |
| 서비스 재기동   | force new deployment                  | 신규 Task RUNNING, rollout COMPLETED         |
| 서비스 재배포   | Task Definition revision 변경           | 신규 revision 반영, Target healthy             |
| Scale-out | desired count 증가                      | 복수 Task RUNNING, Target healthy            |
| Scale-in  | desired count 감소                      | 남은 Task healthy                            |
| 외부 접근 확인  | ALB/NLB DNS 접근                        | HTTP 응답 또는 TCP Connected                   |
| 내부 접근 확인  | Cloud Map DNS 접근                      | Dispatcher DNS 해석 및 내부 포트 연결               |
| 장애 기본 확인  | LB → TG → ECS → Task → SG → DNS 순서 확인 | 원인 범위 축소                                   |

결과적으로 운영의 중심을 개별 서버의 프로세스 확인에서 ECS Service, Task, Deployment, Target Group 중심으로 전환했습니다.

---

## 7. 프로젝트를 통해 확인한 역량

본 POC를 통해 다음과 같은 역량을 검증했습니다.

| 구분        | 내용                                                           |
| --------- | ------------------------------------------------------------ |
| 컨테이너화     | 기존 Java single jar 서비스를 Docker 이미지로 패키징                      |
| ECS 운영    | ECS Cluster, Task Definition, Service, Deployment 구성         |
| 네트워크 설계   | bridge / awsvpc mode 차이 분석 및 서비스별 적용                         |
| 로드밸런싱     | ALB/NLB 분리 구성 및 Target Group 연동                              |
| 서비스 디스커버리 | Cloud Map Private DNS 및 A Record 기반 내부 접근 구성                 |
| 운영 자동화 설계 | desired count, force deployment, revision update 기반 제어 흐름 설계 |
| 장애 분석     | ENI, DNS, NLB, Health Check, Security Group 문제 원인 분석         |
| 운영 검증     | 서비스 기동/중지/재배포/확장/내부 연결/외부 접근 시나리오 정리                         |
| 레거시 전환    | 기존 서비스 구조를 크게 변경하지 않고 ECS 운영 모델로 전환                          |

이 프로젝트의 핵심은 신규 서비스를 처음부터 클라우드 네이티브로 만든 것이 아니라, 이미 존재하는 레거시 Java 서비스를 ECS 기반 운영 모델로 점진적으로 전환했다는 점입니다.

따라서 단순한 인프라 구성 경험뿐 아니라, 기존 시스템의 제약을 이해하고, ECS의 기능을 그대로 적용하는 것이 아니라 레거시 호환성과 운영 가능성을 고려해 구조를 조정한 경험을 담고 있습니다.

---

## 8. 현재 한계와 후속 작업

현재 POC는 ECS 기반 실행, 로드밸런서 연동, 내부 DNS 연결, 주요 기능 검증, 운영 시나리오 정리까지 완료된 상태입니다.

다만 실제 운영 수준으로 확장하기 위해서는 다음 항목을 추가로 구성해야 합니다.

| 항목                         | 목적                                                                          | 상태 |
| -------------------------- | --------------------------------------------------------------------------- | -- |
| ECS API Controller Service | 관리자 페이지에서 ECS Service 상태 조회, 기동, 중지, 재기동, 스케일 조정 수행                         | 예정 |
| 관리자 페이지 연동                 | 기존 운영자가 UI에서 서비스를 켜고 끌 수 있도록 제어 흐름 연결                                       | 예정 |
| GitHub Actions CI/CD       | Docker build, ECR push, Task Definition revision 등록, ECS Service update 자동화 | 예정 |
| PLG Monitoring             | Prometheus, Loki, Grafana 기반 로그 및 메트릭 관측                                    | 예정 |
| Security Group 정리          | POC 검증용 인바운드 규칙을 운영 기준 최소 권한으로 정리                                           | 예정 |
| Multi-AZ 보완                | AZ별 healthy target 확보 및 Task 분산 배치 전략 수립                                    | 예정 |

---

## 9. ECS API Controller Service 확장 계획

기존 운영 구조에서는 관리자 페이지가 Redis Pub/Sub을 통해 Switch Service에 이벤트를 전달하고, Switch Service가 실행 스크립트를 호출하여 Java Process를 제어했습니다.

ECS 전환 후에는 이 개념을 유지하되, 제어 대상을 Java Process가 아니라 ECS Service로 변경할 계획입니다.

```text
관리자 페이지
    ↓
ECS API Controller Service
    ↓
AWS ECS API
    ↓
ECS Service desired count / deployment / task definition 제어
```

Controller Service에서 제공할 주요 기능은 다음과 같습니다.

| 기능                  | 설명                                         |
| ------------------- | ------------------------------------------ |
| service status      | ECS Service의 desired/running/pending 상태 조회 |
| start service       | desired count를 1 이상으로 변경                   |
| stop service        | desired count를 0으로 변경                      |
| restart service     | force new deployment 수행                    |
| scale service       | desired count 증가 또는 감소                     |
| redeploy service    | 특정 Task Definition revision으로 update       |
| target health check | Target Group healthy 상태 조회                 |
| recent events       | ECS Service event 조회                       |

이 기능이 추가되면 기존 관리자 페이지의 “서비스 기동/중지” 운영 경험은 유지하면서, 실제 제어 방식은 ECS API 기반으로 전환할 수 있습니다.

즉, 운영자는 기존과 유사하게 UI에서 서비스를 제어하지만, 내부적으로는 ECS의 표준 운영 방식인 desired count, deployment, Task Definition revision을 사용하게 됩니다.

---

## 10. CI/CD 파이프라인 확장 계획

현재 POC에서는 Java 애플리케이션 빌드, Docker Image 생성, ECR push, Task Definition revision 반영, ECS Service update 흐름을 수동으로 검증했습니다.

후속 작업에서는 이 과정을 GitHub Actions 기반 CI/CD 파이프라인으로 자동화할 계획입니다.

```text
GitHub Push 또는 수동 Workflow 실행
    ↓
Java Application Build
    ↓
Docker Image Build
    ↓
Amazon ECR Push
    ↓
Task Definition revision 등록
    ↓
ECS Service update
    ↓
Target Group Health Check
    ↓
Client Function Validation
```

CI/CD 파이프라인에서 처리할 주요 항목은 다음과 같습니다.

| 구성 항목    | 설명                                               |
| -------- | ------------------------------------------------ |
| Build    | Java application jar build                       |
| Image    | Docker Image build 및 tag 생성                      |
| Registry | Amazon ECR push                                  |
| Deploy   | Task Definition revision 등록 후 ECS Service update |
| Verify   | ECS Service 상태, Target Group health, 기본 기능 확인    |
| Rollback | 실패 시 이전 Task Definition revision으로 복구            |

초기에는 기존 single jar 구조를 고려하여 공통 Docker Image를 생성하고, 서비스별 Task Definition의 command, port, mountPoint를 분리하는 방식으로 구성할 계획입니다.

이 구성이 완료되면 기존 jar 수동 배포와 서버별 재기동 절차를 줄이고, Git commit, image tag, Task Definition revision 기준으로 배포 이력을 추적할 수 있습니다.

---

## 11. 모니터링 시스템 확장 계획

현재 POC에서는 ECS Service, Task, Target Group, Cloud Map DNS를 기준으로 서비스 상태를 수동 검증했습니다.

하지만 운영 환경에서는 Task가 재시작되거나 scale-out될 수 있으므로, 개별 서버 로그 확인 방식만으로는 장애 추적이 어렵습니다. 따라서 후속 작업으로 PLG 기반 모니터링 구성을 추가할 계획입니다.

| 구성 요소                | 역할                                      |
| -------------------- | --------------------------------------- |
| Prometheus           | ECS/Container/JVM/Application metric 수집 |
| Loki                 | 컨테이너 로그 수집 및 검색                         |
| Grafana              | 로그와 메트릭 시각화                             |
| Promtail 또는 로그 수집기   | 컨테이너 로그를 Loki로 전달                       |
| cAdvisor 또는 Exporter | 컨테이너 리소스 지표 수집                          |

우선적으로 관측할 항목은 다음과 같습니다.

| 관측 대상         | 주요 지표                                                  |
| ------------- | ------------------------------------------------------ |
| ECS Service   | desired/running count, deployment 상태                   |
| Container     | CPU, Memory, restart 여부                                |
| JVM           | heap 사용량, GC, thread count                             |
| Load Balancer | Target healthy/unhealthy, request count, response code |
| Application   | 로그인 성공/실패, 메시지 처리 흐름, 주요 에러 로그                         |
| Network       | NLB TCP 연결, ALB 응답 상태, 내부 DNS 연결 오류                    |

모니터링 시스템이 추가되면 현재의 수동 상태 확인 절차를 대시보드 기반으로 전환하고, 장애 발생 시 로그와 메트릭을 함께 추적할 수 있습니다.

---

## 12. 최종 정리

본 POC에서는 기존 온프레미스 Java 메신저 서비스를 AWS ECS EC2 기반 운영 환경으로 전환하기 위한 핵심 구성을 검증했습니다.

최종적으로 다음을 확인했습니다.

| 구분    | 결과                                                                     |
| ----- | ---------------------------------------------------------------------- |
| 실행 구조 | Java Process 중심에서 ECS Task / Service 중심으로 전환                           |
| 배포 구조 | jar 직접 배포에서 Docker Image / ECR 기반 배포로 전환                               |
| 외부 접근 | ALB/NLB 기반 접근 구성                                                       |
| 내부 연결 | Cloud Map A Record 기반 Dispatcher 내부 접근 구성                              |
| 확장성   | Websocket 서비스 scale-out / scale-in 검증                                  |
| 운영 모델 | desired count, force deployment, Task Definition revision 기반 제어 가능성 확인 |
| 장애 대응 | ENI, DNS, NLB, Health Check, Security Group 이슈 분석 및 해결                 |
| 기능 검증 | 기존 클라이언트 로그인, 채팅, 쪽지 기능 동작 확인                                          |

이번 프로젝트의 의미는 단순히 ECS 리소스를 생성한 것이 아니라, 실제 레거시 서비스의 실행 구조, 포트 구조, 내부 연결 방식, 운영 제어 흐름을 고려하여 ECS 기반 운영 모델로 전환 가능한지 검증했다는 점입니다.

향후 ECS API Controller Service, 관리자 페이지 연동, GitHub Actions CI/CD, PLG Monitoring까지 추가하면 기존 수동 운영 중심의 레거시 서비스를 컨테이너 기반 운영 자동화 구조로 확장할 수 있습니다.
