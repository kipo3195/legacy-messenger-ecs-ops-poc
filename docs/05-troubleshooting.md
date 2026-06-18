## EC2 리소스 및 포트 충돌 이슈

bridge mode 기반 서비스는 EC2 Container Instance의 Host Port를 사용하므로, 동일 포트를 사용하는 Task가 같은 인스턴스에 중복 배치될 경우 포트 충돌이 발생할 수 있었다.

또한 제한된 EC2 리소스 내에서 여러 서비스를 실행하면서 CPU 부족으로 Task 배치가 실패하는 상황도 확인했다.