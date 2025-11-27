# RPI pg_cron 배포 패키지 (2025-10-30)

## 목적
RPI 환경에 pg_cron extension을 영구적으로 설치하여 Virtual Tag 계산을 DB 내부에서 자동 실행

## 포함 파일
- `Dockerfile.rpi-pgcron` - pg_cron 포함 Alpine 기반 커스텀 이미지
- `docker-compose.rpi-pgcron.yml` - RPI 환경 docker-compose 설정
- `RPI_PGCRON_DEPLOYMENT.md` - 상세 배포 가이드

## 주요 특징
1. **Alpine Linux 기반**: RPI에서 사용 중인 `timescale/timescaledb:latest-pg17` 이미지 확장
2. **pg_cron 영구 설치**: 컨테이너 재시작 후에도 유지
3. **기존 설정 유지**: 포트(5432), 사용자(postgres), 볼륨(pgai_data) 동일
4. **자동 심볼릭 링크**: pg_cron 파일 경로 문제 해결

## 빠른 시작

### 1. RPI에 파일 배포
```bash
# 로컬에서 Git push
cd C:\reflex\reflex-ksys-refactor\db\20251030-rpi-pgcron
git add .
git commit -m "feat: Add pg_cron support for RPI"
git push origin main

# RPI에서 Pull
ssh tion@192.168.1.80
cd /home/tion/deployment/reflex-ksys-db
git pull origin main
```

### 2. 백업 및 배포
```bash
# 백업
docker exec pgai-db pg_dump -U postgres -d ecoanp -F c -f /backup/before_pgcron_$(date +%Y%m%d_%H%M%S).dump

# 이미지 빌드
cd /home/tion/deployment/reflex-ksys-db/20251030-rpi-pgcron
docker build -f Dockerfile.rpi-pgcron -t pgai-db-pgcron:latest ..

# 컨테이너 재생성
docker-compose -f docker-compose.rpi-pgcron.yml up -d
```

### 3. 검증
```bash
# pg_cron extension 확인
docker exec pgai-db psql -U postgres -d ecoanp -c "\dx" | grep pg_cron

# Virtual Tag 스케줄 설정
docker exec pgai-db psql -U postgres -d ecoanp -f /migrations/08_pg_cron_virtual_tags.sql

# 스케줄 확인
docker exec pgai-db psql -U postgres -d ecoanp -c "SELECT * FROM cron.job;"
```

## 기술 세부사항

### Dockerfile 핵심 내용
- FROM: `timescale/timescaledb:latest-pg17` (Alpine Linux)
- pg_cron 설치: `apk add postgresql-pg_cron`
- 심볼릭 링크 생성: `/usr/share/postgresql17` → `/usr/local/share/postgresql`
- CMD: `shared_preload_libraries=timescaledb,pg_cron`

### docker-compose 핵심 설정
- 컨테이너명: `pgai-db` (기존과 동일)
- 포트: `5432:5432` (기존과 동일)
- 볼륨: `pgai_data` (기존과 동일)
- 네트워크: `ksys-network` (기존과 동일)

## 예상 결과

### Virtual Tag 자동 계산
매 1분마다 다음 태그들이 자동 계산됨:
1. `PRESSURE_DIFF` = INLET_PRESSURE - OUTLET_PRESSURE
2. `RECOVERY_RATE` = (PRODUCT_FLOW / FEED_FLOW) * 100
3. `OPERATING_TIME` = IF(FEED_FLOW > 1.0, 1분, 0분)
4. `TOTAL_PRODUCT_VOLUME_1H` = 1시간 동안의 생산량 합계

### 기존 data-injector 영향
- data-injector가 생성하던 RECOVERY_RATE 랜덤값은 이제 불필요
- 진짜 계산값으로 대체됨

## 참고 문서
- 상세 배포 가이드: `RPI_PGCRON_DEPLOYMENT.md`
- Virtual Tag 마이그레이션: `../migrations/08_pg_cron_virtual_tags.sql`
- pg_cron 공식 문서: https://github.com/citusdata/pg_cron

## 작성자
- 날짜: 2025-10-30
- 목적: RPI 프로덕션 환경 pg_cron 도입
