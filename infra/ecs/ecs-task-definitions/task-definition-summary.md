# Task Definition Summary

| Service     | Task Definition     | Network Mode | Container Port |   Host Port | Volume Mount         | 비고                             |
| ----------- | ------------------- | ------------ | -------------: | ----------: | -------------------- | ------------------------------ |
| Dispatcher  | `ds-task`    | awsvpc       |    33000/33001 | 33000/33001 | config, security_key | Cloud Map A Record, NLB TCP 연결 |
| Websocket   | `ws-task`    | bridge       |          33002 | dynamic `0` | config, security_key | ALB 연결                         |
| Presence    | `ps-task`    | bridge       |          33003 |       33003 | config               | NLB TCP 연결                     |
| Notificator | `ns-task`    | bridge       |          33004 |       33004 | config, security_key | NLB TCP 연결                     |
| Certify     | `cs-task`    | bridge       |          33006 |       33006 | config, security_key | NLB TCP 연결                     |
| Fetch       | `fetch-task` | bridge       |          33007 |       33007 | config, security_key | NLB TCP 연결                     |
| File        | `fs-task`    | bridge       |          33008 |       33008 | config, security_key | NLB TCP 연결                     |

## 정리 기준

Task Definition은 ECS에서 컨테이너를 실행하기 위한 기본 실행 정의입니다.

* Websocket 서비스는 ALB와 연동하기 위해 `bridge` 모드에서 `hostPort: 0` 기반의 동적 포트 매핑을 사용했습니다.
* Dispatcher 서비스는 내부 서비스 디스커버리를 위해 `awsvpc` 모드로 구성하고, Cloud Map A Record 기반 접근을 적용했습니다.
* Certify, Presence, File, Fetch, Notificator 계열 서비스는 고정 포트 기반으로 NLB TCP Target Group과 연동했습니다.
* 각 서비스는 기존 Java 서비스 실행에 필요한 설정 파일을 `/config` 경로에 마운트했습니다.
* 일부 서비스는 암호화 키 참조를 위해 `/security_key` 경로를 추가로 마운트했습니다.
