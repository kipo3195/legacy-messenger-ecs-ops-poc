# ECS Operation Scripts

이 디렉터리는 ECS 기반 서비스 운영 중 반복적으로 수행하는 작업을 AWS CLI 기반 스크립트로 표준화한 예시입니다.

본 POC에서는 ECS 콘솔에서 수동으로 확인하던 서비스 상태 조회, desired count 변경, 강제 재배포, Target Group health 확인, 포트 연결 검증 작업을 스크립트 형태로 정리했습니다.

실제 운영 환경에 바로 적용하기 위한 완성형 자동화 도구라기보다는, ECS 운영 시 자주 사용하는 명령을 일관된 방식으로 실행할 수 있도록 구성한 운영 보조 스크립트입니다.

---

## Script List

| Script                      | Purpose                                                     |
| --------------------------- | ----------------------------------------------------------- |
| `describe-service.sh`       | ECS Service의 desired/running/pending 상태와 Task Definition 확인 |
| `scale-service.sh`          | ECS Service의 desired count 변경                               |
| `force-new-deployment.sh`   | ECS Service에 force new deployment 실행                        |
| `check-target-health.sh`    | ALB/NLB Target Group의 target health 상태 확인                   |
| `test-port-connectivity.sh` | 특정 host/port에 대한 TCP 연결 확인                                  |

---

## Environment Variables

스크립트 실행 시 공통으로 사용하는 값은 환경변수로 분리했습니다.

민감한 값이나 실제 리소스 식별자는 저장소에 직접 포함하지 않고, `env.example` 파일을 참고하여 로컬 환경에서 별도 설정하는 방식을 사용합니다.

```bash
# env.example

AWS_REGION=ap-northeast-2
CLUSTER_NAME=cluster

# ECS Service names
WS_SERVICE=ws-service
DS_SERVICE=ds-service
PS_SERVICE=ps-service
NS_SERVICE=ns-service
CS_SERVICE=cs-service
FETCH_SERVICE=fetch-service
FS_SERVICE=fs-service

# Target Group ARNs
WS_TG_ARN=arn:aws:elasticloadbalancing:ap-northeast-2:xxxxxxxxxxxx:targetgroup/xxxxxxxx/xxxxxxxx
DS_TG_ARN=arn:aws:elasticloadbalancing:ap-northeast-2:xxxxxxxxxxxx:targetgroup/xxxxxxxx/xxxxxxxx
PS_TG_ARN=arn:aws:elasticloadbalancing:ap-northeast-2:xxxxxxxxxxxx:targetgroup/xxxxxxxx/xxxxxxxx
NS_TG_ARN=arn:aws:elasticloadbalancing:ap-northeast-2:xxxxxxxxxxxx:targetgroup/xxxxxxxx/xxxxxxxx
CS_TG_ARN=arn:aws:elasticloadbalancing:ap-northeast-2:xxxxxxxxxxxx:targetgroup/xxxxxxxx/xxxxxxxx
FETCH_TG_ARN=arn:aws:elasticloadbalancing:ap-northeast-2:xxxxxxxxxxxx:targetgroup/xxxxxxxx/xxxxxxxx
FS_TG_ARN=arn:aws:elasticloadbalancing:ap-northeast-2:xxxxxxxxxxxx:targetgroup/xxxxxxxx/xxxxxxxx
```

실제 사용 시에는 다음과 같이 `.env` 파일을 생성하여 사용할 수 있습니다.

```bash
cp env.example .env
```

`.env` 파일은 실제 환경 정보를 포함할 수 있으므로 Git에 포함하지 않습니다.

```gitignore
scripts/.env
```

---

## Usage Examples

### 1. ECS Service 상태 확인

```bash
./describe-service.sh ws-service
```

또는 환경변수를 사용하는 경우:

```bash
./describe-service.sh "$WS_SERVICE"
```

이 스크립트는 ECS Service의 현재 상태, desired count, running count, pending count, 연결된 Task Definition 정보를 확인하는 용도로 사용합니다.

---

### 2. ECS Service desired count 변경

```bash
./scale-service.sh ws-service 1
```

서비스 중지 또는 기동 검증 시 다음과 같이 사용할 수 있습니다.

```bash
./scale-service.sh ws-service 0
./scale-service.sh ws-service 1
```

이 스크립트는 기존 온프레미스 환경에서 프로세스를 직접 중지/시작하던 작업을 ECS Service의 desired count 변경 방식으로 대체하기 위한 검증용입니다.

---

### 3. ECS Service 강제 재배포

```bash
./force-new-deployment.sh ws-service
```

이 스크립트는 동일한 Task Definition 또는 신규 이미지 반영 이후 ECS Service에 새로운 Task 배포를 강제로 유도할 때 사용합니다.

---

### 4. Target Group Health 확인

```bash
./check-target-health.sh "$WS_TG_ARN"
```

ALB 또는 NLB에 연결된 Target Group의 target 상태를 확인합니다.

Target unhealthy 이슈 분석 시 다음 항목을 확인하는 데 사용합니다.

| 확인 항목       | 설명                               |
| ----------- | -------------------------------- |
| Target ID   | 등록된 EC2 instance 또는 IP           |
| Port        | Target Group에 등록된 포트             |
| State       | healthy / unhealthy / initial 상태 |
| Reason      | unhealthy 원인 코드                  |
| Description | 상세 설명                            |

---

### 5. 포트 연결 확인

```bash
./test-port-connectivity.sh ds.service.local 33000
```

NLB 또는 Cloud Map 기반 내부 DNS 연결 검증 시 사용할 수 있습니다.

예시:

```bash
./test-port-connectivity.sh ds.service.local 33000
./test-port-connectivity.sh example-nlb.elb.ap-northeast-2.amazonaws.com 33001
```

이 스크립트는 `nc -vz` 명령을 사용하여 특정 host/port에 TCP 연결이 가능한지 확인합니다.

---

## Evidence Output Example

스크립트 실행 결과는 `evidence/test-results/` 디렉터리에 저장하여 검증 자료로 사용할 수 있습니다.

```bash
mkdir -p ../evidence/test-results

./describe-service.sh ws-service \
  > ../evidence/test-results/ws-describe-service.txt

./check-target-health.sh "$WS_TG_ARN" \
  > ../evidence/test-results/ws-target-health.txt

./test-port-connectivity.sh ds.service.local 33000 \
  > ../evidence/test-results/ds-cloudmap-connectivity.txt
```

이를 통해 README와 문서에서 설명한 검증 항목을 실제 명령 실행 결과와 연결할 수 있습니다.

---

## Notes

이 스크립트들은 POC 과정에서 반복적으로 수행한 ECS 운영 확인 명령을 정리한 것입니다.

실제 운영 환경에 적용할 경우에는 다음 사항을 추가로 고려해야 합니다.

| 항목     | 고려 사항                                                          |
| ------ | -------------------------------------------------------------- |
| 권한 관리  | 실행 계정에 필요한 IAM 권한 최소화                                          |
| 환경 분리  | dev / staging / production 별 cluster, service, target group 분리 |
| 로그 관리  | 실행 결과를 파일 또는 로그 시스템에 저장                                        |
| 에러 처리  | AWS CLI 실패, 네트워크 오류, 권한 오류에 대한 처리 강화                           |
| 배포 자동화 | CI/CD 파이프라인과 연계하여 자동 배포 흐름 구성                                  |

본 저장소에서는 실제 운영 계정 정보, Target Group ARN, 내부 도메인 등 민감한 값은 마스킹하거나 예시 값으로 대체했습니다.
