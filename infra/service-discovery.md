# Service Discovery Configuration

## 1. 적용 목적

ECS 내부 서비스 간 통신에서 Load Balancer를 거치지 않고 Private DNS 기반으로 Dispatcher Service에 접근하기 위해 Cloud Map을 검토했습니다.

## 2. 구성 요약

| 항목 | 값 |
| --- | --- |
| Namespace | poc.local |
| Service Name | ds |
| Record Type | A Record |
| Internal DNS | ds.service.local |
| Target Service | Dispatcher Service |
| Internal Port | 33000 |

## 3. SRV Record 검토 결과

초기에는 SRV Record를 검토했으나, 기존 Java 클라이언트 코드가 `host:port` 형식보다 단일 hostname 또는 IP 기반 접근을 기대하고 있어 SRV Record 조회 결과와 맞지 않았습니다.

## 4. 최종 선택

Dispatcher Service는 awsvpc mode로 구성하고, Cloud Map A Record를 통해 내부 서비스가 `ds.service.local:33000` 형식으로 접근하도록 구성했습니다.