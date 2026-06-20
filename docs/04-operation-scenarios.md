# 04. Operation Scenarios

## 1. 운영 시나리오 문서의 목적

본 문서는 기존 Java 메신저 서비스를 AWS ECS EC2 기반 환경으로 전환한 이후, 운영자가 실제로 수행할 수 있는 주요 운영 시나리오를 정리합니다.

`docs/03-deployment-flow.md`가 기존 jar 배포 및 SCS 기반 제어 구조를 ECS Service 중심의 배포/제어 흐름으로 전환하는 과정을 설명한다면, 본 문서는 ECS 환경에서 서비스를 기동, 중지, 재기동, 확장, 상태 확인, 기능 검증하는 실제 운영 절차를 정리하는 것을 목적으로 합니다.

운영 시나리오는 다음 기준으로 검증합니다.

| 검증 기준           | 설명                                             |
| --------------- | ---------------------------------------------- |
| ECS Service 상태  | desired count, running count, pending count 확인 |
| Deployment 상태   | rollout state 및 신규 Task 반영 여부 확인               |
| Task 상태         | Task가 정상적으로 RUNNING 상태인지 확인                    |
| Target Group 상태 | ALB/NLB Target Group의 healthy 상태 확인            |
| 내부 DNS          | Cloud Map 기반 내부 서비스 주소 해석 확인                   |
| 외부 접근           | ALB/NLB를 통한 서비스 접근 확인                          |
| 기능 검증           | 기존 클라이언트 로그인, 채팅, 쪽지 등 기본 기능 확인                |

---

## 2. 운영 기준

ECS 전환 후 운영의 기준은 기존 Java Process가 아니라 ECS Service입니다.

기존에는 서버에 접속하여 프로세스 실행 여부, 포트 Listen 상태, 로그 파일을 직접 확인하는 방식이 중심이었습니다. ECS 전환 후에는 ECS Service, Task, Deployment, Target Group 상태를 기준으로 서비스 정상 여부를 판단합니다.

| 운영 항목   | 기존 기준               | ECS 기준                                    |
| ------- | ------------------- | ----------------------------------------- |
| 서비스 기동  | Java Process 실행 여부  | ECS Service desired count / running count |
| 서비스 중지  | Process kill 여부     | desired count 0                           |
| 서비스 재기동 | script restart      | force new deployment                      |
| 배포 반영   | jar 파일 교체 여부        | Task Definition revision 반영 여부            |
| 서비스 상태  | ps, netstat, log 확인 | ECS Service / Task / Target Group 확인      |
| 외부 접근   | 서버 IP:Port 직접 접근    | ALB/NLB DNS 또는 Listener 접근                |
| 내부 접근   | 설정 파일의 서버 IP/Host   | Cloud Map Private DNS                     |

---

## 3. 공통 상태 확인 명령어

운영 시나리오에서 반복적으로 사용하는 공통 명령어는 다음과 같습니다.

### 3.1 ECS Service 상태 확인

```bash
aws ecs describe-services \
  --cluster cluster \
  --services <service-name> \
  --region ap-northeast-2 \
  --query "services[0].{
    service:serviceName,
    taskDef:taskDefinition,
    desired:desiredCount,
    running:runningCount,
    pending:pendingCount,
    deployments:deployments[*].{
      status:status,
      taskDef:taskDefinition,
      desired:desiredCount,
      running:runningCount,
      pending:pendingCount,
      rolloutState:rolloutState
    },
    events:events[0:5].message
  }" \
  --output json
```

정상 기준은 다음과 같습니다.

| 항목           | 정상 기준                         |
| ------------ | ----------------------------- |
| desiredCount | 의도한 서비스 개수와 일치                |
| runningCount | desiredCount와 일치              |
| pendingCount | 0                             |
| rolloutState | COMPLETED                     |
| events       | 최근 배치 실패, 포트 충돌, 리소스 부족 오류 없음 |

---

### 3.2 ECS Task 목록 확인

```bash
aws ecs list-tasks \
  --cluster cluster \
  --service-name <service-name> \
  --region ap-northeast-2
```

Task 상세 확인은 다음과 같이 수행합니다.

```bash
aws ecs describe-tasks \
  --cluster cluster \
  --tasks <task-arn> \
  --region ap-northeast-2
```

정상 기준은 Task가 `RUNNING` 상태이며, container의 `lastStatus`도 `RUNNING`인 상태입니다.

---

### 3.3 Target Group 상태 확인

```bash
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region ap-northeast-2
```

정상 기준은 다음과 같습니다.

| 항목                 | 정상 기준                                      |
| ------------------ | ------------------------------------------ |
| TargetHealth.State | healthy                                    |
| Target 등록 여부       | 대상 Task 또는 Instance가 Target Group에 등록되어 있음 |
| Port               | 서비스별 Target Group 포트와 일치                   |

---

### 3.4 Dispatcher 내부 DNS 확인

Dispatcher는 내부 서비스들이 Cloud Map A Record를 통해 접근하는 중심 서비스입니다.

```bash
getent hosts ds.service.local
```

정상 기준은 `ds.service.local`이 Dispatcher Task의 Private IP로 해석되는 것입니다.

---

## 4. 서비스 기동 / 중지 시나리오

### 4.1 시나리오 목적

기존 운영 구조에서는 관리자 페이지 또는 실행 스크립트를 통해 Java Process를 기동하거나 중지했습니다.

ECS 전환 후에는 ECS Service의 desired count를 변경하여 서비스를 기동하거나 중지합니다.

| 운영 행위  | ECS 처리 방식                |
| ------ | ------------------------ |
| 서비스 기동 | desired count를 1 이상으로 변경 |
| 서비스 중지 | desired count를 0으로 변경    |

---

### 4.2 서비스 기동

```bash
aws ecs update-service \
  --cluster cluster \
  --service <service-name> \
  --desired-count 1 \
  --region ap-northeast-2
```

기동 후에는 다음 순서로 확인합니다.

1. ECS Service의 desired/running count 확인
2. Task가 RUNNING 상태인지 확인
3. Target Group에 등록되었는지 확인
4. Target Group health가 healthy인지 확인
5. 서비스별 기능 검증 수행

정상 기준은 다음과 같습니다.

| 확인 항목         | 정상 기준   |
| ------------- | ------- |
| desiredCount  | 1       |
| runningCount  | 1       |
| pendingCount  | 0       |
| Task status   | RUNNING |
| Target status | healthy |

---

### 4.3 서비스 중지

```bash
aws ecs update-service \
  --cluster cluster \
  --service <service-name> \
  --desired-count 0 \
  --region ap-northeast-2
```

중지 후에는 다음 항목을 확인합니다.

| 확인 항목        | 정상 기준                                    |
| ------------ | ---------------------------------------- |
| desiredCount | 0                                        |
| runningCount | 0                                        |
| Task 상태      | STOPPED                                  |
| Target Group | Target deregistration 또는 unhealthy 상태 전환 |

서비스 중지는 운영 중 의도적으로 서비스를 내리는 행위이므로, 외부 접근 실패 자체는 문제가 아닙니다. 중요한 것은 ECS Service 상태가 의도한 desired count와 일치하는지 확인하는 것입니다.

---

## 5. 서비스 재기동 / 재배포 시나리오

### 5.1 시나리오 목적

서비스 설정 변경, 일시적인 오류 복구, 신규 Task 반영이 필요한 경우에는 ECS Service에 force new deployment를 수행합니다.

기존 구조의 script restart 또는 process kill 후 재기동에 해당하는 작업입니다.

---

### 5.2 Force new deployment

```bash
aws ecs update-service \
  --cluster cluster \
  --service <service-name> \
  --force-new-deployment \
  --region ap-northeast-2
```

재기동 후 확인 순서는 다음과 같습니다.

1. 새로운 deployment가 생성되었는지 확인
2. 신규 Task가 RUNNING 상태인지 확인
3. 기존 Task가 정상적으로 drain 또는 stop 되었는지 확인
4. Target Group health가 healthy 상태인지 확인
5. 클라이언트 기능 검증 수행

정상 기준은 다음과 같습니다.

| 확인 항목                   | 정상 기준               |
| ----------------------- | ------------------- |
| deployment rolloutState | COMPLETED           |
| 신규 Task                 | RUNNING             |
| runningCount            | desiredCount와 일치    |
| Target Group            | healthy             |
| 기능 검증                   | 로그인, 채팅, 쪽지 등 정상 동작 |

---

### 5.3 Task Definition revision 변경 후 재배포

새로운 Docker Image 또는 실행 설정을 반영한 Task Definition revision을 배포할 경우 다음 명령을 사용합니다.

```bash
aws ecs update-service \
  --cluster cluster \
  --service <service-name> \
  --task-definition <task-definition-name>:<revision> \
  --region ap-northeast-2
```

확인 항목은 다음과 같습니다.

| 확인 항목          | 설명                                   |
| -------------- | ------------------------------------ |
| taskDefinition | ECS Service가 신규 revision을 참조하는지 확인   |
| deployment     | 신규 deployment가 생성되었는지 확인             |
| Task 상태        | 신규 revision 기반 Task가 RUNNING 상태인지 확인 |
| Target Group   | 신규 Task가 healthy 상태인지 확인             |
| 기능 검증          | 클라이언트 기능 정상 동작 여부 확인                 |

---

## 6. Scale-out / Scale-in 시나리오

### 6.1 시나리오 목적

본 POC에서는 ECS Service 기반 scale-out / scale-in 가능성을 검증했습니다.

기존 구조에서는 서버 또는 Java Process 단위로 수동 증설해야 했지만, ECS 전환 후에는 desired count를 변경하여 서비스 Task 수를 조정할 수 있습니다.

---

### 6.2 Websocket 서비스 Scale-out

Websocket 서비스는 HTTP/WebSocket 요청을 처리하며 ALB Target Group과 연결됩니다.

Scale-out 예시는 다음과 같습니다.

```bash
aws ecs update-service \
  --cluster cluster \
  --service ws-service \
  --desired-count 2 \
  --region ap-northeast-2
```

Scale-out 후 확인 항목은 다음과 같습니다.

| 확인 항목            | 정상 기준                 |
| ---------------- | --------------------- |
| desiredCount     | 2                     |
| runningCount     | 2                     |
| pendingCount     | 0                     |
| ALB Target Group | Target 2개 healthy     |
| 클라이언트 기능         | 로그인 및 WebSocket 연결 정상 |

---

### 6.3 Websocket 서비스 Scale-in

Scale-in 예시는 다음과 같습니다.

```bash
aws ecs update-service \
  --cluster cluster \
  --service ws-service \
  --desired-count 1 \
  --region ap-northeast-2
```

Scale-in 후 확인 항목은 다음과 같습니다.

| 확인 항목            | 정상 기준               |
| ---------------- | ------------------- |
| desiredCount     | 1                   |
| runningCount     | 1                   |
| 기존 Task          | 정상 종료               |
| ALB Target Group | 남아있는 Target healthy |
| 기능 검증            | 클라이언트 기능 정상 동작      |

---

### 6.4 Scale-out 시 고려사항

본 POC에서는 제한된 EC2 리소스 내에서 여러 서비스를 실행했기 때문에 scale-out 시 다음 사항을 함께 확인해야 합니다.

| 고려 사항           | 설명                                               |
| --------------- | ------------------------------------------------ |
| CPU / Memory    | Container Instance의 가용 리소스 부족 여부 확인              |
| Host Port 충돌    | bridge mode 서비스의 동일 Host Port 중복 사용 여부 확인        |
| Target Group 등록 | 신규 Task가 Target Group에 정상 등록되는지 확인               |
| Health Check    | 신규 Target이 healthy 상태로 전환되는지 확인                  |
| Auto Scaling 정책 | TargetTracking 정책 적용 시 desired count 자동 조정 여부 확인 |

---

## 7. 외부 접근 검증 시나리오

### 7.1 Websocket ALB 접근 확인

Websocket 서비스는 ALB를 통해 외부 접근을 구성했습니다.

```bash
curl -v --connect-timeout 5 "http://<alb-dns-name>/"
```

또는 실제 로그인 API를 호출하여 기능 검증을 수행합니다.

```bash
curl -v --connect-timeout 5 "http://<alb-dns-name>/rest/login"
```

정상 기준은 다음과 같습니다.

| 확인 항목        | 정상 기준                    |
| ------------ | ------------------------ |
| DNS 해석       | ALB DNS가 정상 해석됨          |
| TCP 연결       | ALB 80 포트 연결 성공          |
| HTTP 응답      | 서비스에서 기대한 응답 반환          |
| Target Group | Websocket Target healthy |

---

### 7.2 TCP 서비스 NLB 접근 확인

Dispatcher, Certify, Notificator, Presence, Fetch, File과 같은 TCP 기반 서비스는 NLB Listener를 통해 접근합니다.

```bash
nc -vz <nlb-dns-name> <port>
```

예시는 다음과 같습니다.

```bash
nc -vz <nlb-dns-name> 33001
nc -vz <nlb-dns-name> 33006
nc -vz <nlb-dns-name> 33007
```

정상 기준은 다음과 같습니다.

| 확인 항목          | 정상 기준                   |
| -------------- | ----------------------- |
| DNS 해석         | NLB DNS 정상 해석           |
| TCP 연결         | 대상 포트 Connected         |
| Target Group   | 해당 서비스 Target healthy   |
| Security Group | NLB → ECS Service 포트 허용 |

---

## 8. 내부 서비스 연결 검증 시나리오

### 8.1 시나리오 목적

ECS 환경에서는 Task가 재시작되거나 재배치될 수 있으므로, 내부 서비스 간 통신에서 고정 IP에 직접 의존하는 구조는 적합하지 않습니다.

본 POC에서는 Dispatcher를 Cloud Map A Record 기반으로 구성하여 내부 서비스들이 `ds.service.local`과 같은 DNS 이름으로 접근할 수 있도록 구성했습니다.

---

### 8.2 Dispatcher DNS 확인

ECS Task 또는 같은 VPC 내부 EC2에서 다음 명령을 수행합니다.

```bash
getent hosts ds.service.local
```

정상 응답 예시는 다음과 같습니다.

```text
172.31.xx.xx ds.service.local
```

정상 기준은 다음과 같습니다.

| 확인 항목  | 정상 기준                           |
| ------ | ------------------------------- |
| DNS 해석 | ds.service.local이 Private IP로 해석 |
| IP 대상  | Dispatcher Task Private IP      |
| 내부 포트  | 33000 접근 가능                     |
| 연결 방식  | 외부 NLB가 아닌 VPC 내부 통신            |

---

### 8.3 Dispatcher 내부 포트 연결 확인

```bash
nc -vz ds.service.local 33000
```

정상 기준은 `Connected` 응답입니다.

만약 DNS 해석은 되지만 연결이 실패한다면 다음 항목을 확인합니다.

| 확인 항목              | 설명                                       |
| ------------------ | ---------------------------------------- |
| Dispatcher Task 상태 | Task가 RUNNING 상태인지 확인                    |
| Cloud Map 등록       | Dispatcher Task IP가 A Record로 등록되었는지 확인  |
| Security Group     | 내부 서비스 → Dispatcher 33000 허용 여부 확인       |
| Port listen        | Dispatcher 컨테이너가 33000 포트로 Listen 중인지 확인 |

---

## 9. Target Group Health Check 시나리오

### 9.1 시나리오 목적

ECS Service가 RUNNING 상태이더라도 Target Group에서 unhealthy 상태라면 외부 요청은 정상 처리되지 않을 수 있습니다.

따라서 서비스 기동, 재배포, scale-out 이후에는 Target Group health를 반드시 확인합니다.

---

### 9.2 ALB Health Check 확인

Websocket 서비스는 HTTP 기반 Health Check를 사용합니다.

```bash
aws elbv2 describe-target-health \
  --target-group-arn <websocket-target-group-arn> \
  --region ap-northeast-2
```

정상 기준은 다음과 같습니다.

| 확인 항목              | 정상 기준                                   |
| ------------------ | --------------------------------------- |
| TargetHealth.State | healthy                                 |
| Health Check path  | 서비스가 200 응답 가능한 경로                      |
| Security Group     | ALB → ECS Service 포트 허용                 |
| Port Mapping       | Target Group 포트와 Container/Host Port 일치 |

---

### 9.3 NLB Health Check 확인

TCP 기반 서비스는 NLB Target Group을 통해 Health Check를 수행합니다.

```bash
aws elbv2 describe-target-health \
  --target-group-arn <tcp-service-target-group-arn> \
  --region ap-northeast-2
```

정상 기준은 다음과 같습니다.

| 확인 항목              | 정상 기준                      |
| ------------------ | -------------------------- |
| TargetHealth.State | healthy                    |
| Target 등록          | 대상 Instance 또는 IP가 등록되어 있음 |
| Port               | 서비스별 포트와 일치                |
| Security Group     | NLB → ECS Service 포트 허용    |

---

## 10. 장애 발생 시 기본 확인 순서

장애가 발생했을 때는 원인 분석을 바로 시작하기보다, 다음 순서로 상태를 좁혀가며 확인합니다.

### 10.1 기본 확인 흐름

```text
Client 요청 실패
        ↓
ALB/NLB 연결 여부 확인
        ↓
Target Group healthy 여부 확인
        ↓
ECS Service desired/running/pending 확인
        ↓
Task RUNNING 여부 확인
        ↓
ECS Service event 확인
        ↓
Security Group / Port / Health Check 확인
        ↓
Cloud Map DNS 또는 외부 의존 시스템 연결 확인
        ↓
클라이언트 기능 재검증
```

---

### 10.2 확인 항목별 판단 기준

| 단계 | 확인 항목          | 판단 기준                            |
| -- | -------------- | -------------------------------- |
| 1  | 외부 연결          | ALB/NLB DNS 접근 가능 여부             |
| 2  | Target Group   | healthy target 존재 여부             |
| 3  | ECS Service    | desiredCount와 runningCount 일치 여부 |
| 4  | Task           | RUNNING 상태 여부                    |
| 5  | Events         | 배치 실패, 리소스 부족, 포트 충돌 메시지 확인      |
| 6  | Security Group | 필요한 포트가 허용되어 있는지 확인              |
| 7  | 내부 DNS         | Cloud Map DNS가 정상 해석되는지 확인       |
| 8  | 기능 검증          | 로그인, 채팅, 쪽지 등 실제 기능 정상 여부 확인     |

상세한 장애 원인과 해결 과정은 `docs/05-troubleshooting.md`에서 별도로 정리합니다. 본 문서에서는 운영자가 장애 상황에서 어떤 순서로 확인해야 하는지에 초점을 둡니다.

---

## 11. 운영 시나리오 정리

본 문서에서는 ECS 전환 후 운영자가 수행할 수 있는 주요 운영 시나리오를 정리했습니다.

| 시나리오      | ECS 운영 방식                             | 검증 기준                                      |
| --------- | ------------------------------------- | ------------------------------------------ |
| 서비스 기동    | desired count 증가                      | runningCount, Task RUNNING, Target healthy |
| 서비스 중지    | desired count 0                       | runningCount 0, Task STOPPED               |
| 서비스 재기동   | force new deployment                  | 신규 Task RUNNING, rollout COMPLETED         |
| 서비스 재배포   | Task Definition revision 변경           | 신규 revision 반영, Target healthy             |
| Scale-out | desired count 증가                      | 복수 Task RUNNING, Target healthy            |
| Scale-in  | desired count 감소                      | 남은 Task healthy                            |
| 외부 접근 확인  | ALB/NLB DNS 접근                        | HTTP 응답 또는 TCP Connected                   |
| 내부 연결 확인  | Cloud Map DNS 접근                      | ds.service.local 해석 및 연결                    |
| 장애 기본 확인  | LB → TG → ECS → Task → SG → DNS 순서 확인 | 원인 범위 축소                                   |

결과적으로 ECS 전환 후 운영의 핵심은 개별 서버의 Java Process를 직접 확인하는 방식에서 벗어나, ECS Service와 Target Group을 기준으로 서비스 상태를 판단하는 것입니다.

본 POC를 통해 기존 SCS 기반 서비스 제어 개념을 ECS Service의 desired count, deployment, Task Definition revision, Target Group health 중심의 운영 모델로 전환할 수 있음을 확인했습니다.
