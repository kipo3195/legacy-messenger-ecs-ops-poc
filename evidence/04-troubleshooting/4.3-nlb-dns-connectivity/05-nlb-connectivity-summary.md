# NLB DNS Multi-IP and TCP Connectivity Verification

DS 서비스는 외부 TCP 접근을 위해 NLB 33001 Listener를 사용했습니다.

초기 검증 과정에서 NLB DNS가 여러 IP로 응답하는 상황을 확인했으며, 특정 응답 IP 또는 AZ 경로에서 TCP 연결이 timeout되는 케이스를 관찰했습니다.

이에 따라 NLB 기반 TCP 서비스 점검 시 단순히 DNS Name만 확인하는 것이 아니라, 다음 항목을 함께 확인해야 한다고 판단했습니다.

- NLB Listener 33001 구성
- Target Group의 Healthy 상태
- Target의 Availability Zone 배치 상태
- NLB DNS가 반환하는 각 IP별 TCP 연결 여부

현재 검증 결과, NLB DNS Name은 여러 IP로 응답하며 각 응답 IP에 대해 DS 외부 포트 33001 TCP 연결이 모두 성공하는 것을 확인했습니다.

이를 통해 NLB 기반 TCP 서비스 운영 시 DNS 응답 IP, Target Group Health, AZ 배치 상태를 함께 점검해야 함을 정리했습니다.