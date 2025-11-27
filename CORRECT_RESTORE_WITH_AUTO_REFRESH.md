# TimescaleDB 복원 후 자동 리프레시 활성화 가이드

## 문제
DB 복원 후 Continuous Aggregates 자동 리프레시가 작동하지 않음
- `next_start`가 NULL로 설정됨
- Background worker가 job을 실행하지 않음

## 원인
1. `timescaledb.restoring` 모드가 켜진 상태로 유지됨
2. PostgreSQL 재시작 없이 background worker가 활성화되지 않음

## 해결 방법

### Step 1: 복원 모드 비활성화
```sql
-- 데이터베이스 레벨 설정
ALTER DATABASE ecoanp SET timescaledb.restoring = 'off';

-- 현재 세션에도 적용
SET timescaledb.restoring = 'off';

-- 확인
SHOW timescaledb.restoring;  -- 결과: off
```

### Step 2: PostgreSQL 재시작
```bash
docker-compose restart rpi-finished-pgai-db
```

**중요**: 이 단계를 건너뛰면 background worker가 활성화되지 않습니다!

### Step 3: Background Worker 확인
```sql
-- Worker 프로세스 확인
SELECT pid, application_name, state
FROM pg_stat_activity
WHERE application_name LIKE '%TimescaleDB%'
   OR application_name LIKE '%Policy%';
```

**예상 결과**:
```
 pid |            application_name             | state
-----+-----------------------------------------+-------
  32 | TimescaleDB Background Worker Launcher  |
  34 | TimescaleDB Background Worker Scheduler | idle
  35 | TimescaleDB Background Worker Scheduler | idle
```

### Step 4: Job 스케줄 확인
```sql
SELECT
  job_id,
  application_name,
  schedule_interval,
  next_start
FROM timescaledb_information.jobs
WHERE proc_name = 'policy_refresh_continuous_aggregate'
ORDER BY job_id;
```

**예상 결과**: `next_start`에 미래 시간이 설정되어야 함

### Step 5 (선택): 즉시 리프레시
자동 스케줄을 기다리지 않고 즉시 실행하려면:
```bash
# 각 뷰를 개별적으로 리프레시
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp -c "CALL refresh_continuous_aggregate('influx_agg_1m', NULL, NULL);"
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp -c "CALL refresh_continuous_aggregate('influx_agg_10m', NULL, NULL);"
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp -c "CALL refresh_continuous_aggregate('influx_agg_1h', NULL, NULL);"
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp -c "CALL refresh_continuous_aggregate('influx_agg_1d', NULL, NULL);"
```

## 자동 리프레시 스케줄

| View | Interval | Offset | Next Run |
|------|----------|--------|----------|
| influx_agg_1m | 1분 | 10분 지연 | 1분마다 |
| influx_agg_10m | 10분 | 1시간 지연 | 10분마다 |
| influx_agg_1h | 1시간 | 1일 지연 | 1시간마다 |
| influx_agg_1d | 1일 | 7일 지연 | 매일 |

## 문제 해결

### Background Worker가 시작되지 않는 경우
```bash
# PostgreSQL 설정 확인
docker exec rpi-finished-pgai-db psql -U postgres -c "SHOW timescaledb.max_background_workers;"
docker exec rpi-finished-pgai-db psql -U postgres -c "SHOW max_worker_processes;"

# 최소 요구사항:
# - timescaledb.max_background_workers >= 8
# - max_worker_processes >= 8
```

### Job이 실행되지 않는 경우
```sql
-- Job 실행 히스토리 확인
SELECT job_id, last_run_status, last_successful_finish
FROM timescaledb_information.job_stats
WHERE job_id IN (1035, 1036, 1037, 1038, 1045);

-- 수동으로 Job 한 번 실행 (kick-start)
CALL run_job(1035);
```

### 복원 모드가 다시 켜지는 경우
```sql
-- postgresql.conf에 영구 설정
ALTER SYSTEM SET timescaledb.restoring = 'off';
SELECT pg_reload_conf();
```

## 완전한 복원 스크립트

```bash
#!/bin/bash
# complete_restore_with_auto_refresh.sh

set -e

echo "=== Step 1: Stop applications ==="
docker-compose stop rpi-finished-reflex-app rpi-finished-forecast-scheduler

echo "=== Step 2: Terminate connections ==="
docker exec rpi-finished-pgai-db psql -U postgres -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'ecoanp' AND pid <> pg_backend_pid();"

echo "=== Step 3: Drop and recreate database ==="
docker exec rpi-finished-pgai-db psql -U postgres <<EOF
DROP DATABASE IF EXISTS ecoanp;
CREATE DATABASE ecoanp;
EOF

echo "=== Step 4: Install extensions ==="
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp <<EOF
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
CREATE EXTENSION IF NOT EXISTS pg_cron CASCADE;
CREATE EXTENSION IF NOT EXISTS plpython3u CASCADE;
CREATE EXTENSION IF NOT EXISTS vector CASCADE;
CREATE EXTENSION IF NOT EXISTS pg_trgm CASCADE;
CREATE EXTENSION IF NOT EXISTS btree_gin CASCADE;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements CASCADE;
CREATE EXTENSION IF NOT EXISTS pgcrypto CASCADE;
CREATE EXTENSION IF NOT EXISTS plpgsql CASCADE;
EOF

echo "=== Step 5: Prepare for restore ==="
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp -c "
SELECT timescaledb_pre_restore();"

echo "=== Step 6: Restore database ==="
docker exec rpi-finished-pgai-db pg_restore \
  -U postgres \
  -d ecoanp \
  --no-owner \
  --no-acl \
  /backup/your_backup_file.dump

echo "=== Step 7: Disable restore mode ==="
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp <<EOF
ALTER DATABASE ecoanp SET timescaledb.restoring = 'off';
SET timescaledb.restoring = 'off';
EOF

echo "=== Step 8: Restart PostgreSQL (CRITICAL!) ==="
docker-compose restart rpi-finished-pgai-db

echo "=== Waiting for PostgreSQL to start ==="
sleep 10

echo "=== Step 9: Verify background workers ==="
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp -c "
SELECT pid, application_name, state
FROM pg_stat_activity
WHERE application_name LIKE '%TimescaleDB%';"

echo "=== Step 10: Verify job scheduling ==="
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp -c "
SELECT job_id, application_name, schedule_interval, next_start
FROM timescaledb_information.jobs
WHERE proc_name = 'policy_refresh_continuous_aggregate'
ORDER BY job_id;"

echo "=== Step 11: Analyze database ==="
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp -c "ANALYZE;"

echo "=== Step 12: Start applications ==="
docker-compose start rpi-finished-reflex-app rpi-finished-forecast-scheduler

echo "=== Restoration complete with auto-refresh enabled! ==="
```

## 검증 체크리스트

✅ `timescaledb.restoring = 'off'`
✅ TimescaleDB Background Worker 프로세스 실행 중
✅ 모든 Job에 `next_start` 시간 설정됨
✅ Continuous Aggregates에 데이터 존재
✅ 애플리케이션 정상 실행
