# Forecasting Scheduler를 위한 Dockerfile
FROM python:3.11-slim

WORKDIR /app

ENV DOCKER_CONTAINER=true

# 시스템 패키지 설치
RUN apt-get update && apt-get install -y     curl     git     build-essential     && rm -rf /var/lib/apt/lists/*

# Python 의존성 복사 및 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 프로젝트 파일 복사
COPY ksys_app /app/ksys_app
COPY rxconfig.py .

# Schedulers 실행 (run_schedulers.py 사용)
CMD ["python", "ksys_app/schedulers/run_schedulers.py"]
