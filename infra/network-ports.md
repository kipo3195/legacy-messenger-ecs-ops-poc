# Network and Port Mapping

## 1. 서비스 포트 구성

| Service | Container Port | External Access | Protocol       | 비고                                |
| ------- | -------------: | --------------- | -------------- | --------------------------------- |
| WS      |          33002 | ALB 80/443      | HTTP/WebSocket | 웹 클라이언트 HTTP 요청 및 WebSocket 요청 처리 |
| DS      |          33000 | Internal DNS    | TCP            | 내부 서비스 간 Gateway                  |
| DS      |          33001 | NLB 33001       | TCP            | 클라이언트 공통 정보 제공                    |
| PS      |          33003 | NLB 33003       | TCP            | 사용자 상태 및 정보 관리                    |
| NS      |          33004 | NLB 33004       | TCP            | 실시간 이벤트 송/수신                      |
| CS      |          33006 | NLB 33006       | TCP            | 클라이언트 인증 처리                       |
| FETCH   |          33007 | NLB 33007       | TCP            | 채팅, 쪽지 데이터 조회                     |
| FS      |          33008 | NLB 33008       | TCP            | 파일 관련 요청 처리                       |


## 2. Bridge Mode 포트 고려사항

bridge mode에서는 동일 EC2 인스턴스에서 동일 host port를 중복 사용할 수 없습니다.  
따라서 서비스별 host port 충돌 여부와 Task 배치 가능 여부를 함께 확인해야 했습니다.

## 3. awsvpc Mode 포트 고려사항

awsvpc mode에서는 Task별 ENI가 할당되므로 포트 충돌 문제는 줄어들지만, EC2 인스턴스의 ENI 한계로 인해 Scale-out에 제약이 발생할 수 있습니다.