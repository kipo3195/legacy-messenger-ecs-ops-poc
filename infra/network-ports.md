# Network and Port Mapping

## 1. 서비스 포트 구성

| Service | Internal Port | External Port | Access Type | 비고 |
| --- | ---: | ---: | --- | --- |
| WS | 33002 | ALB | HTTP/WebSocket | 클라이언트 로그인 |
| DS | 33000 | - | Internal DNS | 내부 서비스 접근 |
| DS | 33001 | NLB 33001 | TCP | 외부 Dispatcher 접근 |
| PS | 33003 | NLB 33003 | TCP | Presence |
| NS | 33004 | ALB/NLB 또는 내부 접근 | HTTP/TCP | 실시간 이벤트 송/수신 |
| CS | 33006 | NLB 33006 | TCP | 인증 |
| FETCH | 33007 | NLB 33007 | TCP | 채팅, 쪽지 데이터 조회 |
| FS | 33008 | NLB 33008 | TCP | 파일 |

## 2. Bridge Mode 포트 고려사항

bridge mode에서는 동일 EC2 인스턴스에서 동일 host port를 중복 사용할 수 없습니다.  
따라서 서비스별 host port 충돌 여부와 Task 배치 가능 여부를 함께 확인해야 했습니다.

## 3. awsvpc Mode 포트 고려사항

awsvpc mode에서는 Task별 ENI가 할당되므로 포트 충돌 문제는 줄어들지만, EC2 인스턴스의 ENI 한계로 인해 Scale-out에 제약이 발생할 수 있습니다.