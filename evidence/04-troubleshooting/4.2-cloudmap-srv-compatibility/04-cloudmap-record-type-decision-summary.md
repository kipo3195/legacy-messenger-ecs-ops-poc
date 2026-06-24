# Cloud Map Record Type Decision Summary

초기에는 ECS 내부 서비스 디스커버리를 위해 Cloud Map SRV Record 기반 접근을 검토했습니다.

하지만 레거시 Java 서비스는 SRV Record의 host/port 응답을 직접 해석하는 구조가 아니라, 기존 방식처럼 단일 hostname과 고정 port를 기준으로 DS에 접근하는 구조였습니다.

이에 따라 DS 서비스는 Cloud Map A Record 기반으로 조정했습니다.

- Internal DNS: `ds.sevice.local`
- Internal Port: `33000`
- External Port: `33001`
- Network Mode: `awsvpc`
- Cloud Map Record Type: `A`

변경 후 VPC 내부에서 `ds.service.local`이 private IP로 정상 해석되고, `ds.service.local:33000` TCP 연결이 성공하는 것을 확인했습니다.