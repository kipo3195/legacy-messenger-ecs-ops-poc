# Legacy Messenger ECS Ops POC
레거시 메신저 서비스 AWS ECS 운영 전환 POC
## Project Status

이 저장소는 기존 온프레미스 기반 Java 메신저 서비스를 AWS ECS 기반 컨테이너 운영 환경으로 전환하며 검증한 POC 프로젝트입니다.

현재는 ECS 기반 서비스 구동, ALB/NLB 연동, Cloud Map 기반 내부 서비스 연결, 기존 클라이언트 로그인 및 기본 기능 동작 검증까지 완료했습니다.

Go Controller Service, GitHub Actions 기반 CI/CD, PLG 모니터링 구성은 ECS 운영 환경을 확장하기 위한 후속 작업으로 계획되어 있습니다.
