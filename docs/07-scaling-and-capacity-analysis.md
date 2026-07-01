# 07. Scaling and Capacity Analysis

## 1. 분석 목적

본 문서는 레거시 Java 메신저 서비스를 ECS 기반으로 전환하는 과정에서 Scale-out 시 발생했던 몇 가지 문제를 분석하고, ECS Auto Scaling을 메신저 서비스에 적용할 때 고려해야 할 한계와 보완 방향을 정리하기 위해 작성한다.

현재 POC에서 ECS Auto Scaling 검증은 CPU 기반 Target Tracking 정책을 적용했다. 그러나 레거시 메신저는 소켓(TCP/Websocket) 통신을 기반으로 데이터를 실시간으로 주고받는 구조이므로 일반적인 HTTP API 서버와 부하 특성이 다르다. 

클라이언트는 소켓 통신을 기반으로 long-lived connection을 유지하기 때문에 순간적인 request count나 CPU, memory 사용률만으로 Auto Scaling 정책을 세우기 어려운 측면이 있다. 따라서 ECS 환경에서 Auto Scaling이 실제로 동작하는 방식과 메신저 서비스의 부하 특성을 함께 고려하여 Scaling 정책을 검토할 필요가 있다.

본 문서에서는 다음 내용을 중심으로 분석한다.

* ECS Auto Scaling에서 desired count와 running task가 다르게 나타나는 이유
* Auto Scaling 이후 task 배치가 지연되거나 실패할 수 있는 원인
* CPU 기반 Target Tracking 정책이 레거시 메신저 기반 서비스에서 갖는 한계
* 메신저 서비스에 적합한 Scaling metric 후보
* 향후 connection 수 기반 Scaling 또는 별도 control plane 적용 가능성

본 분석의 핵심은 다음과 같다.

> ECS Auto Scaling은 desired count를 증가시키는 것만으로 완료되지 않는다.
> 실제 running task 증가를 위해서는 EC2 capacity, task placement, CPU/memory reservation, network mode, hostPort, Target Group health check 조건이 함께 충족되어야 한다.
> 또한 메신저 서비스는 long-lived connection 특성상 CPU 기반 Scaling만으로는 실제 부하를 충분히 표현하기 어렵다.

---

## 2. ECS Auto Scaling 동작 방식

ECS Service Auto Scaling은 CloudWatch metric을 기반으로 ECS Service의 desired count를 조정한다.

예를 들어 CPU 기반 Target Tracking 정책을 설정하면, ECS는 서비스의 평균 CPU 사용률이 목표값을 초과했을 때 desired count를 증가시킨다.

하지만 이 시점에서 바로 running task가 증가하는 것은 아니다.

동작 흐름은 다음과 같다.

```text
CloudWatch metric 수집
→ Auto Scaling policy 평가
→ ECS Service desired count 증가
→ ECS Scheduler가 task placement 시도
→ Container instance에 task 배치
→ Container 실행
→ Application boot
→ Target Group health check 통과
→ Service steady state 도달
```

따라서 ECS Auto Scaling을 검증할 때는 단순히 desired count가 증가했는지가 아니라, 다음 항목까지 함께 확인해야 한다.

```text
desired count 증가 여부
running task 증가 여부
pending task 상태
ECS service event
task placement 실패 여부
Target Group health 상태
```

---

## 3. 관찰된 문제

POC 환경에서 CPU 기반 부하를 발생시켰을 때, Auto Scaling 정책에 의해 desired count는 증가했지만 running task가 즉시 증가하지 않거나 지연되는 상황이 발생했다.

예시 상태는 다음과 같다.

```text
desired count: 3
running task: 1
pending task: 0 또는 1
```

이 경우 Auto Scaling 정책이 동작하지 않은 것이 아니라, desired count 증가 이후 실제 task placement 또는 health check 단계에서 병목이 발생한 것으로 볼 수 있다.

즉, 문제를 다음과 같이 분리해서 봐야 한다.

```text
Auto Scaling 정책 문제인가?
→ desired count가 증가하지 않는 경우

ECS placement 문제인가?
→ desired count는 증가했지만 running task가 증가하지 않는 경우

Application / Health Check 문제인가?
→ task는 실행됐지만 Target Group에서 unhealthy 상태인 경우
```

---

## 4. running task 증가가 지연되거나 실패하는 원인

### 4.1 EC2 Capacity 부족

ECS EC2 Launch Type에서는 task가 실행될 EC2 container instance의 리소스가 충분해야 한다.

Task Definition에 정의된 CPU/memory reservation을 만족하는 container instance가 없으면 desired count가 증가해도 task가 배치되지 못한다.

대표적인 ECS service event는 다음과 같다.

```text
was unable to place a task because no container instance met all of its requirements.
The closest matching container-instance has insufficient CPU units available.
```

이 경우 확인해야 할 항목은 다음과 같다.

```text
- EC2 instance type
- ECS container instance remaining CPU
- ECS container instance remaining memory
- 현재 실행 중인 다른 service task 수
- task definition의 CPU/memory reservation
```

개선 방향은 다음과 같다.

```text
- EC2 instance type 상향
- ECS cluster에 container instance 추가
- 불필요한 service desired count 조정
- task별 CPU/memory reservation 재검토
- Capacity Provider + Auto Scaling Group 연동 검토
```

본 POC에서는 테스트 목적상 Scale-out 대상이 아닌 service의 desired count를 낮추고, 각 task의 CPU/memory reservation을 실제 기동에 필요한 수준으로 재조정하여 추가 WS task가 배치될 수 있는 여유 capacity를 확보하였다.

---

### 4.2 CPU / Memory Reservation 과다

ECS는 실제 사용량뿐 아니라 Task Definition에 선언된 CPU/memory reservation을 기준으로 task placement 가능 여부를 판단한다.

따라서 실제 CPU 사용률이 낮아 보여도, 이미 예약된 CPU units가 많으면 새로운 task가 배치되지 못할 수 있다.

확인 명령 예시는 다음과 같다.

```bash
aws ecs describe-container-instances \
  --cluster <cluster-name> \
  --container-instances <container-instance-arn>
```

확인 대상은 다음과 같다.

```text
registeredResources
remainingResources
CPU
MEMORY
PORTS
```

---

### 4.3 Network Mode와 hostPort 제약

ECS EC2 기반에서는 network mode와 port mapping 방식이 task Scale-out 가능 여부에 직접적인 영향을 준다.

특히 bridge mode에서 hostPort를 고정하면 동일 EC2 instance에 같은 hostPort를 사용하는 task를 여러 개 배치할 수 없다.

예를 들어 다음과 같은 설정은 Scale-out에 불리하다.

```json
{
  "containerPort": 33002,
  "hostPort": 33002
}
```

반대로 ALB와 함께 사용하는 WebSocket 서비스는 dynamic hostPort를 사용할 수 있다.

```json
{
  "containerPort": 33002,
  "hostPort": 0
}
```

이 경우 ECS가 host의 가용 ephemeral port를 자동 할당하고, ALB Target Group에 동적으로 등록한다.

본 POC에서는 WS 서비스의 Scale-out 검증을 위해 bridge mode + dynamic hostPort 구성이 적합하다고 판단했다.

---

### 4.4 Target Group Health Check 실패

Task가 실행되더라도 Target Group health check를 통과하지 못하면 실제 트래픽을 받을 수 없다.

특히 ALB 기반 WS 서비스에서는 health check path와 application endpoint가 일치해야 한다.

확인 항목은 다음과 같다.

```text
- Target Group health check path
- application의 /health 응답 여부
- containerPort와 target group port mapping
- Security Group inbound/outbound
- health check grace period
```

본 POC에서는 `/health` endpoint가 없거나 404를 반환할 경우 Target Group이 unhealthy 상태가 될 수 있음을 확인했다.

---

## 5. CPU 기반 Scaling의 한계

CPU 기반 Target Tracking은 ECS에서 가장 단순하게 적용할 수 있는 Auto Scaling 방식이다. 하지만 WebSocket 또는 소켓 기반 메신저 서비스에서는 CPU 사용률이 실제 부하를 항상 정확하게 표현하지 못할 수 있다.

메신저 서비스는 다음과 같은 특성을 가진다.

```text
- 클라이언트가 장시간 연결을 유지한다.
- 연결 수가 증가해도 메시지 송수신이 적으면 CPU 사용률은 낮을 수 있다.
- 특정 task에 connection이 몰려도 평균 CPU만으로는 감지하기 어렵다.
- 최초 연결 이후에는 HTTP request count가 실제 연결 유지 비용을 표현하지 못한다.
- Scale-in 시 기존 socket connection이 끊길 수 있다.
```

따라서 CPU 기반 Scaling은 기본적인 보호 장치로는 사용할 수 있지만, WebSocket 서비스의 핵심 Scaling metric으로는 한계가 있다.

---

## 6. 메신저 서비스에 적합한 Scaling Metric 후보

메신저 서비스에서는 다음과 같은 metric을 함께 검토할 수 있다.

| Metric                       | 장점                                      | 한계                                  | 
| ---------------------------- | --------------------------------------- | ----------------------------------- |
| CPUUtilization               | ECS 기본 적용이 쉽다                           | connection 수와 직접 비례하지 않을 수 있다       | 
| MemoryUtilization            | JVM heap, connection 객체 증가를 간접 감지할 수 있다 | Scale-out 판단이 늦을 수 있다               | 
| ALBRequestCountPerTarget     | AWS predefined metric으로 설정이 쉽다          | long-lived connection 부하를 표현하기 어렵다  | 
| ActiveConnectionCount        | ALB 기준 활성 연결 수를 참고 할 수 있다                         | task별 WebSocket connection 수를 직접 표현하지는 못한다 | 
| Active WebSocket Connections | 메신저 부하를 가장 직접적으로 표현한다                   | 애플리케이션 metric 구현 필요                 |
| Connections Per Task         | task별 부하 분산 판단 가능                       | custom metric 또는 별도 집계 필요           | 

이 중 WebSocket 기반 메신저 서비스에 가장 적합한 지표는 다음과 같다.

```text
Active WebSocket Connections Per Task
```
예시 기준은 다음과 같이 설정할 수 있다. (실제 기준값은 task memory, JVM heap 사용량, connection 객체 비용, heartbeat 주기, 메시지 송수신 빈도에 따라 부하 테스트를 통해 조정해야 한다.)

```text
targetConnectionsPerTask = 500
ScaleOutThreshold = 400~450
hardLimit = 500
```

즉, task 1개당 500 connection을 한계로 본다면, 500에 도달한 뒤 Scale-out하는 것이 아니라 400~450 수준에서 선제적으로 Scale-out을 검토해야 한다.

---

## 7. Connection 기반 Scaling 보완 방향

Connection 수 기반 Scaling을 적용하려면 각 WS task의 active connection 수를 수집해야 한다.

가능한 방식은 다음과 같다.

### 7.1 애플리케이션 Metric 노출

각 WS task가 현재 active connection count를 `/metrics` 또는 내부 API로 노출한다.

```text
GET /internal/metrics
active_ws_connections: 420
```

이 방식은 단순하지만, ALB 뒤에 여러 task가 있을 경우 task별 metric을 직접 수집해야 한다.

---

### 7.2 Push 기반 Metric 수집

각 WS task가 주기적으로 Redis, CloudWatch, Prometheus 등에 자신의 connection count를 publish한다.

예시는 다음과 같다.

```text
key: ws:connections:{taskId}
value: 420
ttl: 10s
publish interval: 3~5s
```

이 방식은 다음 장점이 있다.

```text
- task가 자신의 connection 수를 직접 보고한다.
- 죽은 task의 metric은 TTL로 자연스럽게 제거할 수 있다.
- 중앙 집계 서비스는 task별 endpoint를 직접 알 필요가 없다.
- connection 기반 Scale-out 판단에 활용하기 쉽다.
```

---

## 8. Control Plane 적용 가능성

Connection 기반 Scaling을 적용하려면 단순 CloudWatch metric만으로 처리할 수도 있고, 별도 control plane을 둘 수도 있다.

단순한 ECS desired count 조정이나 scheduled operation은 Lambda + EventBridge로도 충분히 구현할 수 있다.

```text
CloudWatch Alarm / EventBridge
→ Lambda
→ ECS UpdateService
```

하지만 다음과 같은 요구가 있다면 control plane을 하나의 서비스로 구축하는 것을 검토할 수 있다.

```text
- ECS service 상태 조회
- Target Group health 조회
- service event 조회
- 운영자용 start/stop/redeploy API
- connection count 기반 Scale-out 판단
- Scaling decision log 기록
- cooldown, maxStep, min/max task 제한
- dry-run mode 제공
```
따라서 본 문서에서는 Control Plane을 즉시 구축 대상으로 확정하기보다, connection 기반 Scaling 자동화가 필요해질 경우 검토할 수 있는 확장 옵션으로 정리한다.

---

## 9. 결론

본 POC에서는 ECS Auto Scaling을 CPU 기반 Target Tracking으로 검증했다. 이를 통해 Auto Scaling 정책이 desired count를 증가시키더라도, 실제 running task 증가까지는 EC2 capacity, task placement, CPU/memory reservation, network mode, hostPort, Target Group health check 조건이 함께 충족되어야 한다는 점을 확인했다.

또한 레거시 메신저 서비스는 long-lived socket connection을 유지하는 구조이므로 일반적인 HTTP API 서버와 동일한 Scaling metric만으로는 한계가 있다. CPU 사용률은 기본적인 보호 지표로 사용할 수 있지만, WebSocket 기반 서비스에서는 active connection 수와 task당 connection 수를 함께 고려해야 한다.

따라서 향후 Scaling 전략은 다음 방향으로 확장할 수 있다.

```text
1. CPU 기반 Target Tracking은 기본 보호 장치로 유지
2. WS task별 active connection count 수집
3. Connections Per Task 기준으로 Scale-out 판단
4. Scale-out은 선제적으로, Scale-in은 보수적으로 수행
5. 단순한 Connections Per Task 기반 Scale-out 자동화는 Lambda/EventBridge 방식 우선 검토
6. 운영 API, 상태 조회, decision log까지 필요할 경우 별도 Control Plane 검토
```