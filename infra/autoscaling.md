# Auto Scaling Configuration

## 1. 적용 대상

| Service | Scaling 적용 여부 | 기준 |
| --- | --- | --- |
| WS | 적용 | CPU Target Tracking |
| DS | 미적용 | Dispatcher 단일 엔드포인트 유지 |
| 기타 TCP 서비스 | 미적용 | EC2 자원 한계 및 POC 범위 |

## 2. WS Auto Scaling 설정

| 항목 | 값 |
| --- | --- |
| Min Capacity | 1 |
| Max Capacity | 2 |
| Scaling Policy | Target Tracking |
| Metric | ECSServiceAverageCPUUtilization |
| Target Value | 50% |

## 3. 검증 결과

- 부하 발생 시 Desired Count 증가 확인
- 신규 Task 기동 확인
- ALB Target Group 등록 확인
- 부하 감소 후 Scale-in 동작 확인