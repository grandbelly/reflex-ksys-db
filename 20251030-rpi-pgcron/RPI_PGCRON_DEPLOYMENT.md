# RPI pg_cron 배포 가이드

## 개요
RPI 환경에 pg_cron을 포함한 TimescaleDB 이미지를 배포하는 가이드입니다.

## 파일 구성
- `Dockerfile.rpi-pgcron` - pg_cron 포함 Alpine 기반 이미지
- `docker-compose.rpi-pgcron.yml` - RPI 환경 docker-compose 설정
- `migrations/08_pg_cron_virtual_tags.sql` - Virtual Tag 스케줄링 스크립트

## 배포 절차

### 1. 현재 데이터 백업 (필수)
```bash
ssh tion@192.168.1.80
cd /home/tion/deployment/reflex-ksys-db
docker exec pgai-db pg_dump -U postgres -d ecoanp -F c -f /backup/ecoanp_before_pgcron_$(date +%Y%m%d_%H%M%S).dump
```

### 2. Git Pull
```bash
cd /home/tion/deployment/reflex-ksys-db
git pull origin main
```

### 3. 이미지 빌드
```bash
docker-compose -f docker-compose.rpi-pgcron.yml build
```

### 4. 컨테이너 재생성
```bash
# 기존 컨테이너 중지 및 제거
docker-compose down

# 새 이미지로 시작
docker-compose -f docker-compose.rpi-pgcron.yml up -d
```

### 5. pg_cron Extension 확인
```bash
docker exec pgai-db psql -U postgres -d ecoanp -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_cron';"
```

예상 결과:
```
 extname | extversion
---------+------------
 pg_cron | 1.6
```

### 6. Virtual Tag 스케줄 설정
```bash
docker exec pgai-db psql -U postgres -d ecoanp -f /migrations/08_pg_cron_virtual_tags.sql
```

### 7. 스케줄 확인
```bash
docker exec pgai-db psql -U postgres -d ecoanp -c "
SELECT jobid, jobname, schedule, active
FROM cron.job;
"
```

예상 결과:
```
 jobid |              jobname               | schedule  | active
-------+------------------------------------+-----------+--------
     1 | calculate_virtual_tags_every_minute| * * * * * | t
```

### 8. 실행 기록 확인
```bash
docker exec pgai-db psql -U postgres -d ecoanp -c "
SELECT start_time, status, return_message
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 5;
"
```

## 롤백 절차

문제 발생 시:

```bash
# 기존 이미지로 복구
docker-compose -f docker-compose.yml up -d

# 백업 복원
docker exec pgai-db pg_restore -U postgres -d ecoanp --clean /backup/ecoanp_before_pgcron_YYYYMMDD_HHMMSS.dump
```

## 주의사항

1. **데이터 손실 방지**: 배포 전 반드시 백업
2. **다운타임**: 컨테이너 재생성 시 약 30초 다운타임 발생
3. **볼륨 유지**: 기존 `pgai_data` 볼륨이 유지되어 데이터는 보존됨
4. **네트워크**: `ksys-network`가 미리 생성되어 있어야 함

## 검증

```bash
# 1. Extension 설치 확인
docker exec pgai-db psql -U postgres -d ecoanp -c "\dx"

# 2. pg_cron 작동 확인
docker exec pgai-db psql -U postgres -d ecoanp -c "SELECT cron.schedule('test-job', '* * * * *', \$\$SELECT 1\$\$);"

# 3. Virtual Tag 데이터 확인 (1분 대기 후)
docker exec pgai-db psql -U postgres -d ecoanp -c "
SELECT tag_name, value, ts
FROM influx_hist
WHERE tag_name IN ('PRESSURE_DIFF', 'RECOVERY_RATE', 'OPERATING_TIME', 'TOTAL_PRODUCT_VOLUME_1H')
AND ts > now() - interval '5 minutes'
ORDER BY ts DESC
LIMIT 10;
"
```

## 문제 해결

### pg_cron extension을 찾을 수 없음
```bash
# 심볼릭 링크 확인
docker exec pgai-db ls -la /usr/local/share/postgresql/extension/ | grep pg_cron
docker exec pgai-db ls -la /usr/local/lib/postgresql/ | grep pg_cron
```

### 스케줄이 실행되지 않음
```bash
# shared_preload_libraries 확인
docker exec pgai-db psql -U postgres -c "SHOW shared_preload_libraries;"
# 결과: timescaledb,pg_cron

# cron.database_name 확인
docker exec pgai-db psql -U postgres -c "SHOW cron.database_name;"
# 결과: ecoanp
```

### 컨테이너 로그 확인
```bash
docker logs pgai-db --tail 50
```
