# Infrastructure Configuration

이 디렉터리는 레거시 Java 메신저 서비스를 AWS ECS EC2 기반 환경에서 실행하기 위해 구성한 인프라 설정을 정리합니다.

주요 구성 범위는 다음과 같습니다.

- ECS Task Definition
- ECS Service
- ALB / NLB / Target Group
- Cloud Map 기반 Service Discovery
- Security Group / Port 정책
- Auto Scaling 설정
- 운영 스크립트와 연계되는 ECS API 구성