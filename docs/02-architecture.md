# 02. Architecture

## 1. Target Architecture

![ECS Architecture](../architecture/ecs-architecture.png)

본 POC에서는 기존 레거시 메신저 서비스를 AWS ECS EC2 기반 클러스터 위에서 실행하도록 구성했습니다.

기존 서비스는 서버별 Java 프로세스를 직접 실행하는 구조였지만, ECS 전환 후에는 각 서버 프로세스를 ECS Task와 ECS Service 단위로 분리하여 실행하도록 구성했습니다.

HTTP/WebSocket 기반 Websocket 서비스는 ALB를 통해 라우팅하고, Dispatcher, Certify, Notificator, Presence, Fetch, File과 같은 TCP 기반 서비스는 NLB Listener를 통해 외부 접근을 구성했습니다.

또한 내부 서비스 간 통신은 Cloud Map 기반 Private DNS를 활용하여 구성했습니다. 이를 통해 기존 클라이언트와 서비스 간 통신 방식을 크게 변경하지 않으면서, ECS 기반 실행 관리, 로드밸런서 연동, 내부 서비스 디스커버리 구성을 검증했습니다.

## 2. 서비스 구성

| Service     | Role                              |        Port |                                                         
| ----------- | --------------------------------- | ----------: | 
| Dispatcher  | 클라이언트 공통 정보 제공 및 서비스 간 Gateway | 33000/33001 | 
| Websocket   | 웹 클라이언트 로그인, HTTP/WebSocket 요청 처리 |       33002 | 
| Presence    | 사용자 상태 및 정보 관리                    |       33003 |                                                                
| Notificator | 클라이언트 실시간 이벤트 송수신                 |       33004 |   
| Certify     | 클라이언트 인증 처리                       |       33006 |                                                                             
| Fetch       | 채팅, 쪽지 등 데이터 조회                   |       33007 |                                                      
| File        | 파일 관련 요청 처리                       |       33008 |                                             

## 3. ECS Cluster 구성

애플리케이션 코드를 ECS 환경에 맞게 크게 변경하기보다는, 기존 실행 방식을 컨테이너 이미지와 Task Definition으로 감싸고, 서비스별 실행 조건을 분리하는 방식으로 전환했습니다.

| 항목                 | 구성                                                             |
| ------------------ | -------------------------------------------------------------- |
| Launch Type        | ECS EC2                                                        |
| Region             | ap-northeast-2                                                 |
| Container Registry | Amazon ECR                                                     |
| 실행 단위              | ECS Service                                                    |
| 배포 단위              | 서비스별 Task Definition                                           |
| 애플리케이션 구조          | 동일 single jar + 서비스별 Runner/CMD                                |
| 주요 설정 파일           | `/config/dbConfiguation.ini`, `/config/serverConfiguation.xml` |
| 외부 접근              | ALB / NLB                                                      |
| 내부 접근              | Cloud Map 기반 Private DNS                                       |

### 3.1 ECS EC2 선택 이유

본 POC에서는 Fargate가 아닌 ECS EC2 방식을 선택했습니다.

가장 큰 이유는 기존 레거시 서비스의 실행 구조와 네트워크 구성을 최대한 유지한 상태에서 ECS 전환을 검증하기 위해서입니다. 기존 서비스는 서비스별 고정 포트를 기준으로 통신하고 있었고, HTTP/WebSocket 서비스와 TCP 기반 서비스가 함께 존재했습니다.

또한 제한된 POC 환경에서 여러 서비스를 동시에 실행해야 했기 때문에, EC2 기반 ECS를 통해 Container Instance의 리소스, 포트 매핑, Target Group 등록 상태를 직접 확인하면서 구성하는 방식이 더 적합했습니다.

Fargate는 인프라 관리 부담이 적다는 장점이 있지만, 본 POC에서는 레거시 서비스의 포트 구조, 네트워크 모드 선택, Host Port 매핑, Task 배치 상태를 직접 검증해야 했기 때문에 EC2 기반 ECS를 선택했습니다.

### 3.2 Single Jar 기반 서비스 분리

기존 메신저 서비스는 동일한 Java single jar를 기반으로 실행되는 구조였습니다. 서비스별 역할은 별도의 jar 파일로 구분되는 것이 아니라, Runner class와 CMD 인자 조합에 따라 런타임에서 결정되었습니다.

예시는 다음과 같습니다.

``dockerfile
ENTRYPOINT ["java", "-Xms64m", "-Xmx192m", "-cp", "/app/app.jar", "각 서비스 별 Main Class"]
CMD ["ID", "서비스 명", "포트"]
``

즉, 컨테이너 이미지 내부의 jar 구조는 동일하지만, 서비스별 Runner class와 CMD 인자를 다르게 지정하여 Websocket, Dispatcher, Certify, Notificator, Presence, Fetch, File 등의 역할을 분리했습니다.

ECS 전환 시에도 이 구조를 유지했습니다. 서비스별 Docker Image와 Task Definition은 분리했지만, 내부적으로는 동일한 single jar 기반 실행 구조를 사용하고, 서비스별 ENTRYPOINT/CMD 조합을 다르게 지정하여 각 ECS Service가 서로 다른 역할로 기동되도록 구성했습니다.

## 4. Network Mode 설계

ECS Task의 Network Mode를 서비스 특성에 따라 `bridge` mode와 `awsvpc` mode로 나누어 구성했습니다.

기존 메신저 서비스는 서비스별 고정 포트를 기준으로 통신하고 있었고, HTTP/WebSocket 기반 서비스와 TCP 기반 서비스가 함께 존재했습니다. 또한 제한된 EC2 리소스 내에서 여러 서비스를 동시에 실행해야 했기 때문에, 모든 서비스를 동일한 Network Mode로 구성하기보다는 서비스별 요구사항에 맞게 Network Mode를 분리했습니다.

대부분의 서비스는 `bridge` mode를 사용하여 EC2 Container Instance 위에서 여러 Task를 실행하도록 구성했고, Dispatcher는 내부 서비스들이 고정 DNS 기반으로 접근해야 하는 특성이 있어 `awsvpc` mode로 구성했습니다.

### 4.1 bridge mode 적용 서비스

`bridge` mode는 Websocket, Certify, Notificator, Presence, Fetch, File 서비스에 적용했습니다.

| Service     |  Port | Load Balancer | 비고               |
| ----------- | ----: | ------------- | ---------------- |
| Websocket   | 33002 | ALB           | HTTP / WebSocket |
| Presence    | 33003 | NLB           | TCP              |
| Notificator | 33004 | NLB           | TCP              |
| Certify     | 33006 | NLB           | TCP              |
| Fetch       | 33007 | NLB           | TCP              |
| File        | 33008 | NLB           | TCP              |

`bridge` mode를 적용한 이유는 제한된 EC2 리소스 내에서 여러 서비스를 동시에 실행하기 위해서입니다. 각 서비스는 컨테이너 내부 포트를 사용하고, ECS Container Instance의 Host Port와 매핑되어 ALB 또는 NLB Target Group으로 연결되도록 구성했습니다.

기존 서비스는 서비스별 포트가 명확히 구분되어 있었기 때문에, ECS 전환 시에도 기존 포트 구조를 최대한 유지하는 것이 중요했습니다. `bridge` mode를 사용하면 EC2 인스턴스 위에서 여러 컨테이너를 실행하면서도, 서비스별 포트 매핑을 통해 기존 통신 구조를 유지할 수 있습니다.

다만 `bridge` mode는 Host Port를 사용하기 때문에, 동일한 포트를 사용하는 Task가 같은 EC2 인스턴스에 중복 배치될 경우 포트 충돌이 발생할 수 있습니다. 따라서 본 POC에서는 서비스별 Target Group과 포트 구성을 분리하여 각 서비스가 독립적으로 라우팅되도록 구성했습니다.

### 4.2 awsvpc mode 적용 서비스

`awsvpc` mode는 Dispatcher 서비스에 적용했습니다.

| Service    |  Port | 접근 방식              | 비고        |
| ---------- | ----: | ------------------ | --------- |
| Dispatcher | 33000 | Cloud Map A Record | 내부 서비스 접근 |
| Dispatcher | 33001 | NLB Listener       | 외부 접근     |

Dispatcher는 클라이언트 공통 정보 제공과 서비스 간 Gateway 역할을 수행하는 중심 서비스입니다. 다른 내부 서비스들이 Dispatcher에 접근해야 하므로, Task 재시작이나 재배치 이후에도 안정적으로 접근할 수 있는 내부 주소가 필요했습니다.

`awsvpc` mode를 사용하면 ECS Task마다 별도의 ENI와 Private IP가 할당됩니다. 이를 통해 Dispatcher Task를 Cloud Map A Record로 등록하고, 내부 서비스들이 `ds.ucware.local`과 같은 Private DNS 이름으로 접근할 수 있도록 구성했습니다.

Dispatcher는 내부 접근과 외부 접근을 분리했습니다. 내부 서비스 간 통신은 Cloud Map A Record 기반으로 `33000` 포트를 사용하고, 외부 접근은 NLB Listener를 통해 `33001` 포트로 연결되도록 구성했습니다.

이 방식은 기존 레거시 서비스가 일반 Hostname 또는 IP 기반 접근을 기대하는 구조와도 잘 맞았습니다.

### 4.3 bridge와 awsvpc를 혼합한 이유

서비스별 네트워크 요구사항이 달랐기 때문입니다.

대부분의 서비스는 제한된 EC2 리소스 내에서 여러 Task를 실행하는 것이 중요했습니다. 이 경우 모든 Task에 개별 ENI가 필요한 `awsvpc` mode보다, EC2 Container Instance의 네트워크를 활용하는 `bridge` mode가 더 적합했습니다.

반면 Dispatcher는 내부 서비스들이 고정 DNS 이름으로 접근해야 하는 중심 서비스였습니다. Cloud Map A Record 기반 접근을 사용하기 위해서는 Task 단위의 Private IP가 필요했기 때문에, Dispatcher는 `awsvpc` mode로 구성했습니다.

| 구분      | bridge mode                                            | awsvpc mode               |
| ------- | ------------------------------------------------------ | ------------------------- |
| 적용 대상   | Websocket, Certify, Notificator, Presence, Fetch, File | Dispatcher                |
| 주요 목적   | 제한된 EC2 리소스 내 다수 서비스 실행                                | 내부 DNS 기반 접근              |
| 네트워크 특성 | Host Port 매핑 사용                                        | Task별 ENI / Private IP 할당 |
| 장점      | 여러 서비스 배치에 유리                                          | Cloud Map A Record 구성에 유리 |
| 고려 사항   | Host Port 충돌 가능성                                       | ENI 수 제한 가능성              |

결과적으로 본 POC에서는 `bridge` mode를 통해 제한된 EC2 환경에서 여러 서비스를 실행하고, `awsvpc` mode를 통해 Dispatcher의 내부 DNS 접근 요구사항을 해결하는 구조로 설계했습니다.

## 5. Load Balancer 설계

Load Balancer는 서비스의 통신 프로토콜에 따라 분리하여 구성했습니다.

HTTP/WebSocket 기반 요청을 처리하는 Websocket 서비스는 ALB를 통해 라우팅했고, Dispatcher, Certify, Notificator, Presence, Fetch, File과 같은 TCP 기반 서비스는 NLB Listener를 통해 접근하도록 구성했습니다.

이를 통해 기존 레거시 서비스의 포트 기반 통신 구조를 유지하면서도, HTTP 계층에서 처리해야 하는 서비스와 TCP 계층에서 전달해야 하는 서비스를 분리했습니다.

### 5.1 ALB 적용 대상

ALB는 Websocket 서비스에 적용했습니다.

| Service   |  Port | Protocol         | Load Balancer | 비고                            |
| --------- | ----: | ---------------- | ------------- | ----------------------------- |
| Websocket | 33002 | HTTP / WebSocket | ALB           | 웹 클라이언트 HTTP 요청 및 WebSocket 요청 처리 |

Websocket 서비스는 웹 클라이언트 로그인 요청과 HTTP/WebSocket 기반 통신을 처리합니다. 따라서 단순 TCP 전달보다는 HTTP 계층에서 요청을 라우팅하고 Health Check를 수행할 수 있는 ALB를 적용했습니다.

### 5.2 NLB 적용 대상

NLB는 TCP 기반 서비스에 적용했습니다.

| Service     |  Port | Protocol | Load Balancer | 
| ----------- | ----: | -------- | ------------- | 
| Dispatcher  | 33001 | TCP      | NLB           | 
| Certify     | 33006 | TCP      | NLB           | 
| Notificator | 33004 | TCP      | NLB           | 
| Presence    | 33003 | TCP      | NLB           | 
| Fetch       | 33007 | TCP      | NLB           | 
| File        | 33008 | TCP      | NLB           |

기존 레거시 서비스는 HTTP 기반 API만으로 구성된 구조가 아니라, 서비스별 TCP 포트를 기준으로 통신하는 구조를 가지고 있었습니다. 따라서 TCP 계층에서 포트별 Listener를 구성할 수 있는 NLB를 적용했습니다.


## 6. Service Discovery 설계

ECS 내부 서비스 간 통신을 위해 Cloud Map 기반 Service Discovery를 구성했습니다.

ECS 환경에서는 Task가 재시작되거나 재배치될 때 Private IP가 변경될 수 있습니다. 따라서 내부 서비스 간 통신에서 특정 Task IP를 직접 설정하는 방식은 적합하지 않았습니다.

특히 Dispatcher 서비스는 여러 내부 서비스가 공통으로 접근하는 Gateway 역할을 수행하기 때문에, 내부 서비스들이 Dispatcher에 안정적으로 접근할 수 있는 고정 이름이 필요했습니다.

이를 위해 Private DNS Namespace를 기준으로 Cloud Map을 구성하고, 내부 서비스들이 DNS 이름을 통해 Dispatcher 서비스에 접근할 수 있도록 설계했습니다.

### 6.1 Cloud Map 적용 목적

Cloud Map을 적용한 목적은 ECS Task의 동적인 IP 변경에 대응하고, 내부 서비스 간 통신 주소를 고정된 DNS 이름으로 관리하기 위해서입니다.

기존 온프레미스 환경에서는 서비스 주소와 포트를 설정 파일에 직접 지정하거나, 서버 IP를 기준으로 서비스 간 연결을 구성할 수 있었습니다. 하지만 ECS 환경에서는 Task가 재시작되거나 다른 인스턴스에 배치될 수 있으므로, 고정 IP를 전제로 한 내부 통신 방식은 유지하기 어렵습니다.

본 POC에서는 Cloud Map을 통해 다음 항목을 검증했습니다.

| 항목            | 설명                                    |
| ------------- | ------------------------------------- |
| 내부 DNS 이름 제공  | 내부 서비스들이 고정 DNS 이름으로 Dispatcher 서비스에 접근   |
| Task IP 변경 대응 | Dispatcher Task 재시작 시에도 DNS 기반 접근 유지  |
| VPC 내부 통신 구성  | 외부 Load Balancer를 거치지 않는 내부 서비스 접근 구성 |
| 레거시 설정 호환     | 기존 서비스의 Hostname 기반 접근 방식 유지          |

### 6.2 SRV Record 검토

초기에는 Cloud Map의 SRV Record 방식도 검토했습니다.

SRV Record는 서비스의 IP뿐 아니라 포트 정보까지 함께 제공할 수 있기 때문에, ECS의 동적 포트 매핑이나 `bridge` mode 기반 서비스 디스커버리와 함께 사용할 수 있는 방식입니다.

하지만 기존 레거시 서비스는 SRV Record를 해석하여 `host:port` 형태로 사용하는 구조가 아니었습니다. 서비스 설정과 연결 로직은 일반적인 Hostname 또는 IP 기반 접근을 전제로 하고 있었고, 포트는 설정 파일 또는 실행 인자에 의해 별도로 관리되는 구조에 가까웠습니다.

이로 인해 SRV Record를 적용할 경우 DNS 응답의 포트 정보를 애플리케이션에서 별도로 처리해야 하는 부분이 발생하여, 레거시 메신저의 서비스 연결 로직을 수정해야 했습니다. 기존 방식을 최대한 유지하기 위해서 SRV Record가 아닌 A Record 기반 접근으로 조정하였습니다.

| 항목        | 문제                                 |
| --------- | ---------------------------------- |
| DNS 해석 방식 | 기존 코드가 SRV Record 조회를 전제로 하지 않음    |
| 포트 처리     | DNS 응답의 포트 정보를 애플리케이션에서 별도로 처리해야 함 |
| 코드 수정 범위  | 레거시 서비스의 연결 로직 수정이 필요할 수 있음        |
| 호환성       | 기존 Hostname 기반 접근 방식과 맞지 않음        |

따라서 SRV Record는 구조적으로는 유효한 선택지였지만, 기존 레거시 서비스와의 호환성을 고려했을 때 본 POC에는 적합하지 않다고 판단했습니다.

### 6.3 A Record 기반 접근으로 조정한 이유

최종적으로 Dispatcher는 Cloud Map A Record 기반으로 접근하도록 조정했습니다.

A Record는 DNS 이름에 대해 IP 주소를 반환하는 방식이므로, 기존 레거시 서비스가 기대하는 일반 Hostname 기반 접근 방식과 잘 맞았습니다. 내부 서비스들은 Dispatcher Task의 Private IP를 얻고, 기존 설정에 정의된 포트로 접근할 수 있습니다.

이를 위해 Dispatcher는 `awsvpc` mode로 구성했습니다. `awsvpc` mode에서는 ECS Task마다 별도의 ENI와 Private IP가 할당되므로, Cloud Map A Record에 Dispatcher Task의 Private IP를 등록할 수 있습니다.

Dispatcher의 내부/외부 접근 구조는 다음과 같이 분리했습니다.

| 구분    | 접근 방식              |  Port | 설명                             |
| ----- | ------------------ | ----: | ------------------------------ |
| 내부 접근 | Cloud Map A Record | 33000 | 내부 서비스들이 `ds.service.local`로 접근 |
| 외부 접근 | NLB Listener       | 33001 | 외부 클라이언트 또는 외부 연동 접근           |


## 7. Security Group 설계

본 POC에서는 서비스 구동과 통신 검증을 우선 목표로 하여, Load Balancer, ECS Service, 내부 서비스, 외부 의존 시스템 간 연결에 필요한 포트를 중심으로 Security Group을 조정했습니다.

기존 메신저 서비스는 서버별 고정 포트를 기준으로 통신하고 있었기 때문에, ECS 전환 과정에서도 서비스별 Listener, Target Group, Network Mode에 따라 필요한 인바운드/아웃바운드 규칙을 확인했습니다.

POC 단계에서 고려한 주요 통신 경로는 다음과 같습니다.

| 통신 구간                           | 설명                              |
| ------------------------------- | ------------------------------- |
| Client → ALB                    | Websocket 서비스 HTTP/WebSocket 접근 |
| Client → NLB                    | TCP 기반 서비스 외부 접근                |
| ALB/NLB → ECS Service           | Target Group을 통한 서비스별 Task 접근   |
| ECS Service → Dispatcher        | Cloud Map 기반 내부 서비스 접근          |
| ECS Service → DB/Redis/RabbitMQ | 기존 외부 의존 시스템 접근                 |

기능 검증을 위해 필요한 포트를 우선 허용했지만, 운영 환경에서는 다음과 같은 방향으로 보완이 필요합니다.

| 항목        | 운영 환경 보완 방향                                    |
| --------- | ---------------------------------------------- |
| 외부 접근     | ALB/NLB에서 필요한 포트만 공개                           |
| ECS 접근    | Load Balancer 또는 내부 서비스 Security Group 기준으로 제한 |
| 내부 통신     | 서비스 간 필요한 포트만 허용                               |
| 의존 시스템 접근 | DB/Redis/RabbitMQ 접근 주체를 ECS Service 기준으로 제한   |
| 관리 접근     | SSH 등 관리 포트는 특정 IP로 제한                         |
| 테스트 규칙    | POC 검증 후 불필요한 인바운드 규칙 제거                       |

결과적으로 Security Group을 세부 보안 정책 완성보다는 서비스 연결 검증 관점에서 구성했습니다. 이후 운영 환경 적용 시에는 최소 권한 원칙에 따라 Load Balancer, ECS Service, 외부 의존 시스템의 Security Group을 분리하고, 필요한 통신 경로만 허용하는 구조로 보완할 예정입니다.

## 8. Architecture Decision Summary

본 POC에서는 기존 레거시 메신저 서비스의 실행 구조와 통신 방식을 최대한 유지하면서, ECS 기반 운영 구조로 전환하는 것을 목표로 했습니다.

이를 위해 서비스 실행 단위, Network Mode, Load Balancer, Service Discovery, Security Group을 다음과 같은 기준으로 결정했습니다.

| Decision                | 선택                              | 이유                                                                                | 고려 사항                               |
| ----------------------- | ------------------------------- | --------------------------------------------------------------------------------- | ----------------------------------- |
| ECS Launch Type         | ECS EC2                         | 기존 서비스의 포트 구조, Host Port 매핑, Task 배치 상태를 직접 검증하기 위해 선택                            | EC2 인스턴스 리소스와 운영 관리 필요              |
| 실행 단위                   | ECS Task / ECS Service          | 기존 서버별 Java 프로세스를 ECS의 관리 단위로 분리하기 위해 선택                                          | 서비스별 Task Definition 관리 필요          |
| 애플리케이션 실행 구조            | 동일 single jar + 서비스별 Runner/CMD | 기존 실행 구조를 크게 변경하지 않고 서비스별 역할을 분리하기 위해 선택                                          | 이미지/Task Definition은 서비스별로 관리 필요    |
| Websocket 접근            | ALB                             | HTTP/WebSocket 기반 요청을 처리하고 HTTP Health Check를 적용하기 위해 선택                          | TCP 기반 서비스와 별도 Load Balancer 구성 필요  |
| TCP 서비스 접근              | NLB                             | Dispatcher, Certify, Notificator, Presence, Fetch, File의 TCP 포트 기반 통신을 유지하기 위해 선택 | Listener와 Target Group을 서비스별로 관리 필요 |
| 다수 서비스 Network Mode     | bridge mode                     | 제한된 EC2 리소스 내에서 여러 서비스를 동시에 실행하기 위해 선택                                            | Host Port 충돌 가능성 존재                 |
| Dispatcher Network Mode | awsvpc mode                     | Cloud Map A Record 기반 내부 접근을 위해 Task 단위 Private IP가 필요했기 때문에 선택                   | Task별 ENI 사용으로 인한 리소스 제한 고려 필요      |
| 내부 서비스 디스커버리            | Cloud Map Private DNS           | Task 재시작 또는 재배치 시에도 내부 서비스가 고정 DNS 이름으로 접근할 수 있도록 선택                              | DNS Record 방식 선택 필요                 |
| Dispatcher DNS Record   | A Record                        | 기존 레거시 서비스가 일반 Hostname/IP 기반 접근을 기대하기 때문에 선택                                     | bridge mode 동적 포트 매핑에는 제한적          |
| SRV Record              | 미적용                             | 기존 코드가 SRV Record를 해석해 `host:port`로 사용하는 구조가 아니기 때문에 미적용                          | SRV 적용 시 연결 로직 수정 필요                |
| Security Group          | POC 검증 중심 포트 허용                 | 서비스 구동, Target Group 연동, 내부/외부 통신 검증을 우선하기 위해 구성                                  | 운영 환경에서는 최소 권한 기준으로 재정리 필요          |

이번 아키텍처에서 가장 중요한 결정은 모든 서비스를 동일한 방식으로 ECS에 올리지 않고, 서비스 특성에 따라 실행 방식과 네트워크 구성을 분리했다는 점입니다.

Websocket 서비스는 HTTP/WebSocket 기반 요청을 처리하므로 ALB를 적용했고, TCP 기반 레거시 서비스는 기존 포트 기반 통신 구조를 유지하기 위해 NLB를 적용했습니다.

Network Mode 역시 동일하게 구성하지 않았습니다. Websocket, Certify, Notificator, Presence, Fetch, File 서비스는 제한된 EC2 리소스 내에서 여러 Task를 실행하기 위해 `bridge` mode를 사용했고, Dispatcher는 내부 서비스들이 고정 DNS 이름으로 접근해야 하므로 `awsvpc` mode와 Cloud Map A Record를 조합했습니다.

결과적으로 본 POC에서는 기존 레거시 서비스의 실행 구조와 통신 방식을 크게 변경하지 않으면서, ECS Service 기반 실행 관리, ALB/NLB 기반 외부 접근, Cloud Map 기반 내부 서비스 디스커버리 구성을 검증했습니다.

다만 현재 구성은 POC 검증을 위한 구조이므로, 운영 환경 적용 시에는 다음 항목에 대한 보완이 필요합니다.

| 보완 항목                 | 설명                                                  |
| --------------------- | --------------------------------------------------- |
| Multi-AZ 배치 전략        | AZ별 Healthy Target 확보 및 Task 분산 배치 필요               |
| Security Group 최소 권한화 | 테스트용 인바운드 규칙 제거 및 통신 주체별 제한 필요                      |
| CI/CD 자동화             | Docker build, ECR push, ECS Service update 자동화 필요   |
| 모니터링 구성               | 분산 Task 환경에서 로그와 메트릭 추적 체계 필요                       |
| 운영 제어 방식              | ECS Service 상태 조회, 기동/중지, scale, redeploy API 구성 필요 |
