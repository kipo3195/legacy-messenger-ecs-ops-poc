# ECS Service Summary

| Service | Network Mode | LB | Port | Desired Count | 주요 검증 |
| --- | --- | --- | ---: | ---: | --- |
| WS | bridge | ALB | 33002 | 1~2 | 로그인, WebSocket, Auto Scaling |
| DS | awsvpc | NLB + Cloud Map | 33000/33001 | 1 | 내부 DNS, 외부 TCP 접근 |
| NS | bridge | NLB | 33004 | 1 | 로그인, 실시간 이벤트 송/수신 | 
| CS | bridge | NLB | 33006 | 1 | 인증 요청 TCP 연결 |
| FETCH | bridge | NLB | 33007 | 1 | 채팅, 쪽지 데이터 조회 TCP 연결 |
| PS | bridge | NLB | 33003 | 1 | 사용자 정보 확인 TCP 연결 |