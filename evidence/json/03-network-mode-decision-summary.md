# Network Mode Redesign Decision

초기 ECS 전환 과정에서는 여러 레거시 Java 서비스를 동일한 Network Mode(awsvpc)로 구성하는 방식을 검토했습니다.

하지만 ECS EC2 환경에서는 단일 인스턴스의 CPU, Memory, Port, ENI와 같은 리소스 제약이 Task 배치에 직접적인 영향을 줄 수 있습니다. 실제 검증 과정에서도 일부 서비스가 Pending 상태에 머물거나 Task 배치가 실패하는 상황이 발생했습니다.

이에 따라 모든 서비스를 동일한 방식으로 구성하지 않고, 서비스 특성에 따라 Network Mode를 분리했습니다.

- DS: 내부 DNS 접근과 고정적인 서비스 엔드포인트가 중요하므로 awsvpc 유지
- WS: ALB 기반 WebSocket 연결과 스케일링 검증을 위해 bridge 적용
- NS/PS/CS/FETCH/FS: TCP 포트 기반 서비스로 bridge 적용

이 구조를 통해 DS는 `ds.service.local` 기반 내부 접근을 유지하고, WS 및 기타 서비스는 ECS EC2 환경에서 보다 효율적으로 배치할 수 있도록 조정했습니다.

