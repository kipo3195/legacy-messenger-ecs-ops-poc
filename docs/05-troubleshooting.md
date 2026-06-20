# 05. Troubleshooting

## 1. Troubleshooting 문서의 목적

본 문서는 기존 Java 메신저 서비스를 AWS ECS EC2 기반 환경으로 전환하는 과정에서 발생한 주요 이슈와 해결 과정을 정리합니다.

`docs/04-operation-scenarios.md`가 ECS 환경에서 서비스를 어떻게 기동, 중지, 재배포, 검증하는지에 대한 운영 절차를 다룬다면, 본 문서는 실제 구성 과정에서 발생한 문제를 기준으로 증상, 원인, 확인 방법, 해결 방향, 결과를 정리하는 것을 목적으로 합니다.

본 POC에서는 단순히 Java 서비스를 컨테이너로 실행하는 것뿐 아니라, 기존 레거시 서비스의 실행 구조와 통신 방식을 최대한 유지하면서 ECS Service, Task Definition, Load Balancer, Cloud Map 기반 운영 구조로 전환하는 것을 목표로 했습니다.

이 과정에서 발생한 문제는 대부분 다음 영역과 관련되어 있었습니다.

| 구분               | 주요 확인 대상                                      |
| ---------------- | --------------------------------------------- |
| ECS Task 배치      | Network Mode, ENI, CPU/Memory, Host Port      |
| Load Balancer 연동 | ALB/NLB, Listener, Target Group, Health Check |
| 내부 서비스 연결        | Cloud Map, DNS Record, 내부 포트                  |
| 보안 및 접근 제어       | Security Group, 인바운드 포트, Target 등록            |
| 레거시 호환성          | 기존 서비스의 Hostname/IP 기반 접근 방식                  |

본 문서에서는 그중 아키텍처 결정과 운영 검증에 직접적인 영향을 준 4개의 이슈를 중심으로 정리합니다.

---

## 2. 주요 이슈 요약

| 문제                                        | 주요 원인                                                                                        | 해결 방향                                                                      | 상태    |
| ----------------------------------------- | -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | ----- |
| awsvpc ENI 부족과 Network Mode 재설계           | 모든 서비스를 awsvpc mode로 구성할 경우 Task별 ENI가 필요하여 제한된 EC2 환경에서 다수 서비스 실행과 scale-out에 제약 발생         | 대부분의 서비스는 bridge mode로 구성하고, 내부 DNS 고정 접근이 필요한 Dispatcher만 awsvpc mode로 분리 | 해결    |
| Cloud Map SRV Record 호환 문제                | Cloud Map SRV Record는 host:port 해석이 필요하지만 기존 레거시 서비스는 일반 Hostname/IP 기반 접근을 전제로 동작           | Dispatcher를 awsvpc mode로 구성하고 Cloud Map A Record 기반 접근으로 조정                | 해결    |
| NLB Multi-AZ timeout 분석                   | NLB DNS가 여러 AZ IP로 응답하지만 특정 AZ에 healthy target이 없는 경우 일부 IP 접근 시 timeout 발생                  | Target Group health, AZ별 target 배치 상태, NLB 연결 구조를 분석하여 원인 확인               | 분석 완료 |
| ALB/NLB Target unhealthy와 Health Check 조정 | Health Check path 불일치, Security Group 인바운드 누락, Target Group 포트 설정 오류 등으로 Target unhealthy 발생 | Health Check 경로, 서비스 응답, Target Group 포트, Security Group 규칙 조정             | 해결    |

---

## 3. awsvpc ENI 부족과 Network Mode 재설계

### 3.1 증상

초기 ECS 구성 단계에서는 각 서비스를 ECS Task로 분리하고, 서비스별로 독립적인 네트워크 구성을 갖도록 `awsvpc` mode 적용을 검토했습니다.

하지만 제한된 ECS EC2 환경에서 여러 서비스를 동시에 실행하거나 Websocket 서비스의 desired count를 증가시키는 과정에서 Task 배치가 실패하거나, scale-out 가능한 수량에 제약이 발생했습니다.

대표적인 증상은 다음과 같습니다.

| 증상            | 설명                                           |
| ------------- | -------------------------------------------- |
| Task 배치 실패    | ECS Service가 desired count만큼 Task를 실행하지 못함   |
| pending 상태 지속 | 신규 Task가 RUNNING 상태로 전환되지 않음                 |
| scale-out 제한  | Websocket 등 일부 서비스의 desired count 증가 시 배치 실패 |
| ECS Event 오류  | Container Instance 리소스 또는 네트워크 리소스 부족 메시지 발생 |

ECS Service 상태 확인 시 다음과 같이 desired count와 running count가 일치하지 않는 상태를 확인할 수 있습니다.

```bash
aws ecs describe-services \
  --cluster cluster \
  --services <service-name> \
  --region ap-northeast-2 \
  --query "services[0].{
    service:serviceName,
    desired:desiredCount,
    running:runningCount,
    pending:pendingCount,
    events:events[0:5].message
  }" \
  --output json
```

---

### 3.2 원인

`awsvpc` mode는 ECS Task마다 별도의 ENI와 Private IP를 할당합니다.

이 방식은 Task 단위로 네트워크를 분리할 수 있고, Cloud Map A Record 기반 서비스 디스커버리와 잘 맞는 장점이 있습니다. 하지만 ECS EC2 환경에서는 Container Instance의 ENI 할당 한계와 리소스 제약을 고려해야 합니다.

본 POC는 제한된 EC2 리소스 내에서 Websocket, Dispatcher, Certify, Notificator, Presence, Fetch, File 등 여러 서비스를 동시에 실행해야 했습니다. 따라서 모든 서비스를 `awsvpc` mode로 구성할 경우 Task별 ENI가 필요해지고, 단일 또는 소수의 EC2 인스턴스에서 다수 Task 실행과 scale-out에 한계가 발생했습니다.

---

### 3.3 확인 방법

먼저 ECS Service Event를 통해 Task 배치 실패 원인을 확인합니다.

```bash
aws ecs describe-services \
  --cluster cluster \
  --services <service-name> \
  --region ap-northeast-2 \
  --query "services[0].events[0:10].message" \
  --output json
```

Container Instance의 가용 리소스도 함께 확인합니다.

```bash
aws ecs describe-container-instances \
  --cluster cluster \
  --container-instances <container-instance-arn> \
  --region ap-northeast-2 \
  --query "containerInstances[0].{
    remainingResources:remainingResources,
    registeredResources:registeredResources
  }" \
  --output json
```

확인해야 할 항목은 다음과 같습니다.

| 확인 항목                 | 설명                                   |
| --------------------- | ------------------------------------ |
| ECS Service Event     | Task 배치 실패 사유 확인                     |
| remaining CPU/Memory  | Container Instance의 남은 리소스 확인        |
| Network Mode          | 서비스별 Task Definition의 networkMode 확인 |
| desired/running count | 원하는 Task 수만큼 실행되었는지 확인               |
| pending count         | Task가 pending 상태로 남아 있는지 확인          |

---

### 3.4 해결 방법

모든 서비스를 동일한 Network Mode로 구성하지 않고, 서비스 특성에 따라 `bridge` mode와 `awsvpc` mode를 혼합하여 구성했습니다.

| 구분          | 적용 서비스                                                 | 선택 이유                                                               |
| ----------- | ------------------------------------------------------ | ------------------------------------------------------------------- |
| bridge mode | Websocket, Certify, Notificator, Presence, Fetch, File | 제한된 EC2 리소스 내에서 여러 서비스를 실행하고 scale-out 가능성을 검증하기 위해 선택              |
| awsvpc mode | Dispatcher                                             | Cloud Map A Record 기반 내부 DNS 접근을 위해 Task 단위 Private IP가 필요했기 때문에 선택 |

대부분의 서비스는 `bridge` mode로 구성하여 EC2 Container Instance의 네트워크를 활용하도록 했습니다. 이를 통해 단일 EC2 환경에서도 여러 서비스를 동시에 실행할 수 있었습니다.

반면 Dispatcher는 내부 서비스들이 고정 DNS 이름으로 접근해야 하는 중심 서비스였기 때문에 `awsvpc` mode로 유지했습니다. Dispatcher Task에 Private IP를 할당하고 Cloud Map A Record로 등록하여 내부 서비스들이 DNS 기반으로 접근할 수 있도록 구성했습니다.

---

### 3.5 결과

Network Mode를 혼합한 결과, 제한된 ECS EC2 환경에서도 주요 서비스를 동시에 실행할 수 있었고 Websocket 서비스의 scale-out / scale-in 검증도 가능해졌습니다.

| 항목                  | 결과                                             |
| ------------------- | ---------------------------------------------- |
| 다수 서비스 실행           | bridge mode 기반으로 여러 서비스 동시 실행 가능               |
| Dispatcher 내부 접근    | awsvpc mode + Cloud Map A Record로 내부 DNS 접근 가능 |
| Websocket scale-out | desired count 증가 및 ALB Target Group 연동 검증 가능   |
| ECS 리소스 사용          | 모든 Task에 ENI를 할당하는 구조보다 제한된 리소스에 적합            |

---

### 3.6 정리

이 이슈를 통해 모든 서비스를 동일한 방식으로 ECS에 올리는 것이 항상 적합한 것은 아니라는 점을 확인했습니다.

ECS 전환 시에는 서비스별 통신 특성, 내부 DNS 필요 여부, Task 배치 방식, EC2 리소스 제약을 함께 고려해야 합니다.

본 POC에서는 다음 기준으로 Network Mode를 결정했습니다.

```text
다수 서비스 실행과 제한된 EC2 리소스 활용이 중요한 서비스
→ bridge mode

내부 DNS 고정 접근과 Task 단위 Private IP가 필요한 서비스
→ awsvpc mode
```

결과적으로 이 이슈는 `bridge`와 `awsvpc`를 혼합한 현재 ECS 아키텍처 결정의 직접적인 근거가 되었습니다.

---

## 4. Cloud Map SRV Record 호환 문제와 A Record 전환

### 4.1 증상

ECS 내부 서비스 간 통신을 위해 Cloud Map 기반 Service Discovery를 구성하는 과정에서 DNS Record 방식에 대한 호환 문제가 발생했습니다.

초기에는 ECS Service Discovery에서 사용할 수 있는 SRV Record 방식도 검토했습니다. SRV Record는 IP뿐 아니라 포트 정보까지 함께 제공할 수 있으므로, 동적 포트 매핑이나 ECS Service Discovery에 유용할 수 있습니다.

하지만 기존 레거시 서비스는 SRV Record를 조회하고, 응답에 포함된 host와 port를 조합하여 연결하는 구조가 아니었습니다.

대표적인 증상은 다음과 같습니다.

| 증상                        | 설명                                                    |
| ------------------------- | ----------------------------------------------------- |
| 내부 서비스에서 Dispatcher 연결 실패 | Dispatcher 주소를 DNS로 해석하지 못하거나 기대한 방식으로 접근하지 못함        |
| UnknownHost 계열 오류         | 레거시 서비스가 기대하는 Hostname/IP 조회 방식과 SRV Record 방식이 맞지 않음 |
| 포트 처리 불일치                 | DNS 응답의 포트 정보를 애플리케이션에서 별도로 처리하지 못함                   |
| 설정 방식 충돌                  | 기존 설정은 Hostname과 Port를 분리해서 관리하는 구조에 가까움              |

---

### 4.2 원인

Cloud Map SRV Record는 서비스의 위치 정보를 `host:port` 형태로 활용할 수 있는 장점이 있습니다. 하지만 이 방식을 사용하려면 애플리케이션이 SRV Record를 조회하고, 응답에 포함된 포트 정보를 해석할 수 있어야 합니다.

기존 레거시 메신저 서비스는 일반적인 Hostname 또는 IP 기반 접근을 전제로 하고 있었습니다. 포트 정보는 DNS 응답에서 얻는 것이 아니라 설정 파일 또는 실행 인자에서 별도로 관리되는 구조였습니다.

따라서 SRV Record를 사용하려면 레거시 서비스의 연결 로직을 수정해야 할 가능성이 있었습니다. 본 POC의 목표는 기존 애플리케이션 코드를 크게 변경하지 않고 ECS 운영 환경으로 전환하는 것이었기 때문에 SRV Record 방식은 적합하지 않다고 판단했습니다.

| 항목        | SRV Record 적용 시 문제                  |
| --------- | ----------------------------------- |
| DNS 조회 방식 | 기존 코드가 SRV Record 조회를 전제로 하지 않음     |
| 포트 처리     | DNS 응답에 포함된 포트를 애플리케이션에서 별도로 처리해야 함 |
| 코드 수정 범위  | 레거시 서비스 연결 로직 변경 가능성 발생             |
| 기존 설정 호환성 | Hostname/IP + 별도 port 설정 방식과 맞지 않음  |

---

### 4.3 확인 방법

Cloud Map DNS가 실제로 어떤 방식으로 해석되는지 확인합니다.

A Record 조회는 다음과 같이 확인할 수 있습니다.

```bash
getent hosts ds.service.local
```

또는 다음과 같이 DNS 조회 도구를 사용할 수 있습니다.

```bash
dig ds.service.local A
```

SRV Record를 사용하는 경우에는 다음과 같이 확인할 수 있습니다.

```bash
dig _ds._tcp.service.local SRV
```

확인 기준은 다음과 같습니다.

| 확인 항목      | 정상 기준                                    |
| ---------- | ---------------------------------------- |
| A Record   | DNS 이름이 Dispatcher Task의 Private IP로 해석됨 |
| SRV Record | host와 port 정보가 함께 반환됨                    |
| 애플리케이션 호환성 | 기존 서비스가 해당 Record 방식을 해석할 수 있어야 함        |
| 내부 포트      | Dispatcher 내부 접근 포트와 설정 파일의 포트가 일치해야 함   |

---

### 4.4 해결 방법

최종적으로 Dispatcher는 Cloud Map A Record 기반으로 접근하도록 조정했습니다.

이를 위해 Dispatcher는 `awsvpc` mode로 구성했습니다. `awsvpc` mode에서는 ECS Task마다 Private IP가 할당되므로, Dispatcher Task의 Private IP를 Cloud Map A Record에 등록할 수 있습니다.

내부 서비스들은 SRV Record를 해석하지 않고, 기존 방식과 유사하게 다음 형태로 Dispatcher에 접근할 수 있습니다.

```text
ds.service.local:33000
```

Dispatcher의 접근 경로는 내부와 외부를 분리했습니다.

| 구분    | 접근 방식              |  Port | 설명                      |
| ----- | ------------------ | ----: | ----------------------- |
| 내부 접근 | Cloud Map A Record | 33000 | 내부 서비스들이 Dispatcher에 접근 |
| 외부 접근 | NLB Listener       | 33001 | 외부 클라이언트 또는 외부 연동 접근    |

이 방식은 기존 레거시 서비스의 Hostname/IP 기반 접근 방식과 잘 맞았고, 애플리케이션 코드 수정 범위를 최소화할 수 있었습니다.

---

### 4.5 결과

Cloud Map A Record 기반으로 조정한 결과, 내부 서비스들이 Dispatcher를 고정 DNS 이름으로 접근할 수 있게 되었습니다.

| 항목       | 결과                                                    |
| -------- | ----------------------------------------------------- |
| 내부 DNS   | `ds.service.local` 이름으로 Dispatcher 접근 가능              |
| 레거시 호환성  | 기존 Hostname/IP 기반 접근 방식 유지                            |
| 코드 변경 범위 | SRV Record 해석 로직 추가 없이 구성 가능                          |
| 네트워크 구성  | Dispatcher는 awsvpc mode, 내부 통신은 Cloud Map A Record 사용 |

---

### 4.6 정리

이 이슈를 통해 ECS의 기능을 그대로 적용하는 것보다, 기존 애플리케이션의 연결 방식과 호환되는 형태로 조정하는 것이 중요하다는 점을 확인했습니다.

SRV Record는 ECS Service Discovery에서 유용한 방식이지만, 기존 서비스가 SRV Record를 해석하지 못한다면 오히려 코드 수정 범위를 키울 수 있습니다.

본 POC에서는 레거시 서비스의 Hostname/IP 기반 접근 방식을 유지하기 위해 다음과 같이 조정했습니다.

```text
Cloud Map SRV Record 미적용
→ Dispatcher awsvpc mode 구성
→ Cloud Map A Record 등록
→ 내부 서비스는 ds.service.local:33000 형태로 접근
```

이 결정은 Dispatcher를 awsvpc mode로 유지한 이유와도 직접 연결됩니다.

---

## 5. NLB Multi-AZ timeout 분석

### 5.1 증상

TCP 기반 서비스는 NLB Listener를 통해 외부 접근을 구성했습니다. 하지만 NLB DNS로 TCP 연결을 확인하는 과정에서 일부 연결은 성공하고, 일부 연결은 timeout이 발생하는 현상이 있었습니다.

대표적인 확인 명령은 다음과 같습니다.

```bash
nc -vz <nlb-dns-name> 33001
```

증상은 다음과 같이 정리할 수 있습니다.

| 증상                       | 설명                                          |
| ------------------------ | ------------------------------------------- |
| NLB DNS 연결 불안정           | 같은 NLB DNS로 접근해도 연결 결과가 다르게 나타남             |
| 특정 IP timeout            | NLB DNS가 반환한 여러 IP 중 일부 IP로 접근 시 timeout 발생 |
| Target Group은 일부 healthy | 특정 AZ 또는 특정 Target만 healthy 상태              |
| 서비스 자체는 정상               | ECS Task 또는 특정 Target은 정상 실행 중              |

---

### 5.2 원인

NLB는 하나의 DNS 이름을 제공하지만, 내부적으로는 여러 Availability Zone의 IP로 응답할 수 있습니다.

이때 특정 AZ에 healthy target이 없거나, 해당 AZ에 등록된 target이 정상 상태가 아니라면 NLB DNS가 반환한 일부 IP로 접근할 때 timeout이 발생할 수 있습니다.

즉, NLB DNS가 하나라고 해서 모든 AZ 경로가 동일하게 정상이라고 볼 수 없습니다. 실제 운영에서는 NLB DNS, AZ별 IP, Target Group health, Task 배치 상태를 함께 확인해야 합니다.

| 원인 후보                  | 설명                                             |
| ---------------------- | ---------------------------------------------- |
| AZ별 healthy target 불균형 | 특정 AZ에는 정상 Target이 없을 수 있음                     |
| Task 배치 편중             | ECS Task가 일부 AZ 또는 일부 Container Instance에만 배치됨 |
| Target Group 등록 누락     | 대상 Instance 또는 IP가 Target Group에 등록되지 않음       |
| Security Group 제한      | NLB에서 Target으로 접근하는 포트가 허용되지 않음                |
| Health Check 실패        | Target이 NLB Health Check를 통과하지 못함              |

---

### 5.3 확인 방법

먼저 NLB DNS가 반환하는 IP를 확인합니다.

```bash
dig +short <nlb-dns-name>
```

각 IP에 대해 직접 연결을 확인합니다.

```bash
nc -vz <nlb-ip-1> 33001
nc -vz <nlb-ip-2> 33001
```

Target Group 상태를 확인합니다.

```bash
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region ap-northeast-2
```

ECS Task가 어느 Container Instance 또는 어떤 네트워크 위치에 배치되어 있는지도 확인합니다.

```bash
aws ecs describe-tasks \
  --cluster cluster \
  --tasks <task-arn> \
  --region ap-northeast-2
```

확인 기준은 다음과 같습니다.

| 확인 항목         | 설명                                      |
| ------------- | --------------------------------------- |
| NLB DNS IP 목록 | NLB가 여러 IP로 응답하는지 확인                    |
| IP별 TCP 연결    | 특정 IP에서만 timeout이 발생하는지 확인              |
| Target Health | 각 Target이 healthy 상태인지 확인               |
| Target AZ     | Target이 어느 AZ에 등록되어 있는지 확인              |
| Task 배치       | ECS Task가 특정 AZ 또는 Instance에만 몰려 있는지 확인 |

---

### 5.4 해결 및 조정 방향

POC 단계에서는 NLB Multi-AZ timeout 현상을 통해 NLB와 Target Group의 동작 구조를 분석하는 데 중점을 두었습니다.

운영 환경에서는 다음 방향으로 보완이 필요합니다.

| 보완 방향                 | 설명                                    |
| --------------------- | ------------------------------------- |
| AZ별 healthy target 확보 | NLB가 활성화된 AZ마다 정상 Target을 확보          |
| Task 분산 배치            | ECS Service가 여러 AZ에 Task를 분산 배치하도록 구성 |
| Target Group 상태 상시 확인 | 배포 또는 재기동 후 Target health 확인          |
| Security Group 정리     | NLB → ECS Service 포트 허용 여부 확인         |
| NLB 설정 검토             | Cross-zone load balancing 등 운영 정책 검토  |

POC 환경에서는 제한된 EC2 리소스와 단일 또는 소수의 Task 배치로 인해 AZ별 Target이 균등하지 않을 수 있었습니다. 따라서 timeout을 단순한 서비스 장애로 판단하지 않고, NLB DNS 응답 IP와 Target Group의 AZ별 healthy 상태를 함께 확인했습니다.

---

### 5.5 결과

NLB Multi-AZ timeout 현상을 분석하면서 다음 내용을 확인했습니다.

| 항목      | 결과                                                 |
| ------- | -------------------------------------------------- |
| NLB DNS | 하나의 DNS가 여러 AZ IP로 응답할 수 있음                        |
| 연결 결과   | IP별로 연결 성공/timeout이 다르게 나타날 수 있음                   |
| 원인 범위   | 서비스 코드 문제보다는 Target Group, AZ 배치, NLB 경로 문제로 범위 축소 |
| 운영 보완점  | AZ별 healthy target 확보와 Task 분산 배치 필요성 확인           |

---

### 5.6 정리

이 이슈는 단순히 NLB 연결이 실패한 문제가 아니라, NLB DNS, Availability Zone, Target Group, ECS Task 배치의 관계를 확인한 사례입니다.

운영 환경에서는 NLB DNS 접근 결과만 보는 것이 아니라 다음 순서로 확인해야 합니다.

```text
NLB DNS 해석
→ IP별 연결 결과 확인
→ Target Group healthy 상태 확인
→ AZ별 Target 존재 여부 확인
→ ECS Task 배치 상태 확인
→ Security Group 및 포트 확인
```

이 과정을 통해 NLB 기반 TCP 서비스 운영 시 AZ별 healthy target 확보와 배치 전략이 중요하다는 점을 확인했습니다.

---

## 6. ALB/NLB Target unhealthy와 Health Check 조정

### 6.1 증상

ECS Service의 Task가 RUNNING 상태임에도 ALB 또는 NLB Target Group에서 unhealthy 상태가 발생했습니다.

또는 외부에서 ALB/NLB DNS로 접근했을 때 연결이 실패하거나, 기대한 응답이 반환되지 않는 문제가 있었습니다.

대표적인 증상은 다음과 같습니다.

| 증상                     | 설명                                          |
| ---------------------- | ------------------------------------------- |
| ECS Task는 RUNNING      | ECS Service 기준으로 Task는 정상 실행 중              |
| Target Group unhealthy | ALB/NLB Target Group에서 Target이 unhealthy 상태 |
| ALB Health Check 404   | Health Check path와 서비스 응답 경로가 맞지 않음         |
| TCP 연결 실패              | NLB Listener 포트 또는 Target 포트 연결 실패          |
| 외부 요청 실패               | ALB/NLB DNS로 접근해도 클라이언트 요청 실패               |

---

### 6.2 원인

ECS Service가 RUNNING 상태라고 해서 Load Balancer 관점에서도 정상이라는 의미는 아닙니다.

Load Balancer를 통해 요청이 정상 처리되려면 다음 조건이 모두 맞아야 합니다.

| 조건              | 설명                                                  |
| --------------- | --------------------------------------------------- |
| Task 실행 상태      | ECS Task가 RUNNING 상태여야 함                            |
| Port Mapping    | Container Port, Host Port, Target Group Port가 맞아야 함 |
| Target 등록       | Task 또는 Instance가 Target Group에 등록되어야 함             |
| Health Check 응답 | ALB/NLB Health Check를 통과해야 함                        |
| Security Group  | Load Balancer에서 ECS Service 포트로 접근 가능해야 함           |
| 서비스 응답          | Health Check path 또는 TCP 포트에서 정상 응답해야 함             |

본 POC에서는 다음과 같은 원인이 복합적으로 발생할 수 있었습니다.

| 원인                     | 설명                                            |
| ---------------------- | --------------------------------------------- |
| Health Check path 불일치  | ALB가 확인하는 path에서 서비스가 200 응답을 반환하지 않음         |
| Security Group 인바운드 누락 | ALB/NLB에서 ECS Service 포트로 접근할 수 없음            |
| Target Group 포트 불일치    | Target Group이 실제 서비스 포트와 다른 포트로 확인            |
| Target 등록 누락           | 대상 Task 또는 Instance가 Target Group에 등록되지 않음    |
| Config mount 누락        | 설정 파일 또는 보안 키가 컨테이너에 마운트되지 않아 서비스가 정상 동작하지 않음 |

---

### 6.3 확인 방법

먼저 ECS Service 상태를 확인합니다.

```bash
aws ecs describe-services \
  --cluster cluster \
  --services <service-name> \
  --region ap-northeast-2 \
  --query "services[0].{
    desired:desiredCount,
    running:runningCount,
    pending:pendingCount,
    deployments:deployments[*].rolloutState,
    events:events[0:5].message
  }" \
  --output json
```

Target Group 상태를 확인합니다.

```bash
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region ap-northeast-2
```

ALB HTTP Health Check의 경우 실제 path 응답을 확인합니다.

```bash
curl -v --connect-timeout 5 "http://<alb-dns-name>/"
```

또는 Health Check path를 직접 호출합니다.

```bash
curl -v --connect-timeout 5 "http://<alb-dns-name>/<health-check-path>"
```

NLB TCP 서비스는 포트 연결을 확인합니다.

```bash
nc -vz <nlb-dns-name> <port>
```

Task Definition의 portMappings와 mountPoints도 확인합니다.

```bash
aws ecs describe-task-definition \
  --task-definition <task-definition-name>:<revision> \
  --region ap-northeast-2
```

확인 기준은 다음과 같습니다.

| 확인 항목            | 정상 기준                                      |
| ---------------- | ------------------------------------------ |
| ECS Service      | runningCount가 desiredCount와 일치             |
| Task 상태          | RUNNING                                    |
| Target Group     | TargetHealth.State가 healthy                |
| ALB Health Check | Health Check path에서 200 응답                 |
| NLB 연결           | 대상 포트 TCP Connected                        |
| Security Group   | LB → ECS Service 포트 허용                     |
| Port Mapping     | Container/Host/Target Group 포트 일치          |
| Mount Points     | `/config`, `/security_key` 등 필요한 파일 경로 마운트 |

---

### 6.4 해결 방법

이 이슈는 단일 원인으로 보기보다, Load Balancer에서 ECS Task까지 이어지는 경로를 단계별로 확인하면서 해결했습니다.

#### 6.4.1 ALB Health Check 404 조정

Websocket 서비스는 HTTP/WebSocket 요청을 처리하기 때문에 ALB를 사용했습니다.

ALB Health Check가 특정 path를 호출했을 때 서비스가 404를 반환하면 Target은 unhealthy 상태가 됩니다. 따라서 Health Check path를 서비스가 정상 응답할 수 있는 경로로 조정하거나, 해당 경로에 200 응답을 반환하도록 애플리케이션 응답을 맞췄습니다.

| 항목                | 조정 방향                               |
| ----------------- | ----------------------------------- |
| Health Check path | 서비스가 200 응답 가능한 경로로 조정              |
| 서비스 응답            | Health Check 요청에 정상 응답하도록 확인        |
| Target Group      | ALB Target Group Health Check 설정 확인 |

---

#### 6.4.2 Security Group 인바운드 조정

Load Balancer에서 ECS Service의 대상 포트로 접근할 수 있도록 Security Group 인바운드 규칙을 확인했습니다.

| 통신 구간                    | 확인 포인트              |
| ------------------------ | ------------------- |
| Client → ALB             | HTTP 접근 포트 허용       |
| Client → NLB             | TCP Listener 포트 허용  |
| ALB → ECS Service        | Websocket 서비스 포트 허용 |
| NLB → ECS Service        | TCP 서비스별 포트 허용      |
| ECS Service → Dispatcher | 내부 33000 포트 허용      |

POC 단계에서는 기능 검증을 우선하여 필요한 포트를 허용했고, 운영 환경에서는 최소 권한 기준으로 Security Group을 재정리해야 합니다.

---

#### 6.4.3 Target Group 포트 및 등록 상태 확인

Target Group이 실제 서비스 포트와 일치하는지 확인했습니다.

bridge mode 서비스의 경우 Container Instance의 Host Port와 Target Group 포트가 맞아야 하며, awsvpc mode 서비스의 경우 Task의 ENI Private IP와 포트 기준으로 Target이 등록되어야 합니다.

| Network Mode | Target 등록 기준         | 확인 항목                        |
| ------------ | -------------------- | ---------------------------- |
| bridge       | Instance + Host Port | Host Port, Target Group Port |
| awsvpc       | IP + Container Port  | Task ENI IP, Container Port  |

---

#### 6.4.4 Config mount 누락 보완

일부 Task에서는 외부 설정 파일 또는 보안 키가 컨테이너 내부에 마운트되지 않아 서비스가 정상 동작하지 않는 문제가 발생할 수 있었습니다.

기존 서비스는 외부 설정 파일에 의존하고 있었기 때문에 ECS Task Definition에서도 해당 파일 경로를 volume과 mountPoints로 명시해야 했습니다.

확인 대상은 다음과 같습니다.

| 항목              | 예시                               |
| --------------- | -------------------------------- |
| 설정 파일           | `/config/dbConfiguation.ini`     |
| 서버 설정           | `/config/serverConfiguation.xml` |
| 보안 키            | `/security_key/uc.key`           |
| Task Definition | volumes, mountPoints 설정          |

Task Definition에서 mountPoints를 확인합니다.

```bash
aws ecs describe-task-definition \
  --task-definition <task-definition-name>:<revision> \
  --region ap-northeast-2 \
  --query "taskDefinition.containerDefinitions[0].mountPoints" \
  --output json
```

---

### 6.5 결과

ALB/NLB Target unhealthy 문제를 조정한 결과, ECS Service 상태와 Load Balancer 상태를 분리해서 확인할 수 있게 되었습니다.

| 항목               | 결과                                                       |
| ---------------- | -------------------------------------------------------- |
| ALB Health Check | Health Check path 조정 후 Target healthy 확인                 |
| NLB TCP 연결       | Listener / Target Group / Security Group 확인 후 연결 검증      |
| Target Group     | 서비스별 Target 등록 및 healthy 상태 확인                           |
| Config mount     | 필요한 설정 파일을 Task Definition에 mountPoint로 반영               |
| 운영 기준            | ECS RUNNING 상태뿐 아니라 Target Group healthy 여부를 함께 확인하도록 정리 |

---

### 6.6 정리

이 이슈를 통해 ECS Service가 RUNNING 상태인 것과 실제 외부 요청을 처리할 수 있는 상태는 다르다는 점을 확인했습니다.

운영 시에는 다음 순서로 확인해야 합니다.

```text
ECS Service desired/running count 확인
→ Task RUNNING 상태 확인
→ Target Group 등록 상태 확인
→ Target Group health 확인
→ Health Check path 또는 TCP port 확인
→ Security Group 인바운드 확인
→ Port Mapping 및 Config mount 확인
```

특히 Load Balancer를 사용하는 ECS 환경에서는 Target Group의 healthy 상태가 실제 서비스 접근 가능 여부를 판단하는 핵심 기준이 됩니다.

---

## 7. Troubleshooting Summary

본 POC에서 발생한 주요 문제는 단순 설정 오류라기보다, 기존 레거시 서비스의 실행 방식과 ECS 운영 모델을 맞추는 과정에서 발생한 구조적 이슈에 가까웠습니다.

| 이슈                   | 최종 판단                                                      |
| -------------------- | ---------------------------------------------------------- |
| awsvpc ENI 부족        | 모든 서비스를 awsvpc로 구성하지 않고, 서비스 특성에 따라 bridge/awsvpc를 혼합해야 함  |
| Cloud Map SRV 호환 문제  | ECS 기능보다 기존 레거시 서비스의 DNS 해석 방식과 호환되는 A Record 구성이 적합함      |
| NLB Multi-AZ timeout | NLB DNS 하나만 볼 것이 아니라 AZ별 Target health와 Task 배치를 함께 확인해야 함 |
| Target unhealthy     | ECS Task RUNNING 여부와 Load Balancer healthy 여부는 별도로 확인해야 함  |

이 과정을 통해 현재 아키텍처의 주요 결정이 도출되었습니다.

| 아키텍처 결정               | 근거가 된 Troubleshooting                               |
| --------------------- | --------------------------------------------------- |
| ECS EC2 선택            | 기존 포트 구조, Host Port 매핑, Task 배치 상태를 직접 검증하기 위함      |
| bridge mode 적용        | 제한된 EC2 리소스 내에서 다수 서비스 실행과 scale-out 검증 필요          |
| Dispatcher awsvpc 적용  | Cloud Map A Record 기반 내부 DNS 접근 필요                  |
| ALB/NLB 분리            | HTTP/WebSocket 서비스와 TCP 기반 서비스를 구분해 라우팅하기 위함        |
| Cloud Map A Record 적용 | 기존 레거시 서비스의 Hostname/IP 기반 접근 방식과 호환하기 위함           |
| Target Group 중심 운영    | ECS Service RUNNING 상태만으로는 외부 접근 가능 여부를 판단할 수 없기 때문 |

결과적으로 본 POC에서는 단순히 Java 서비스를 ECS에 올리는 것뿐 아니라, ECS 환경에서 실제로 서비스를 운영할 때 발생할 수 있는 네트워크, 로드밸런서, 서비스 디스커버리, Health Check 문제를 분석하고 해결했습니다.

이를 통해 기존 온프레미스 기반 Java Process 운영 방식에서 ECS Service, Task Definition, Target Group, Cloud Map 중심의 운영 방식으로 전환 가능한지 검증했습니다.
