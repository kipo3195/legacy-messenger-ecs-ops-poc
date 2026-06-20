# ECS Task Definitions

이 디렉터리는 ECS에서 Java 메신저 서비스를 실행하기 위해 사용한 Task Definition 예시를 정리합니다.

## 주요 구성 포인트

| 항목 | 설명 |
| --- | --- |
| Network Mode | WS는 bridge, DS는 awsvpc로 구성 |
| Port Mapping | 서비스별 고정 포트 사용 |
| Volume Mount | dbconfig.ini, serverConfig.xml, uc.key 등 외부 설정 파일 마운트 |
| Logging | CloudWatch Logs 또는 표준 로그 수집 기준 |
| Resource | EC2 인스턴스 자원 한계를 고려하여 CPU/Memory 조정 |