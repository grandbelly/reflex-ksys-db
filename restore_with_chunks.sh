#!/bin/bash
# TimescaleDB 완전 복원 스크립트 (Chunks 포함)
# 생성일: 2025-10-31

set -e

echo "=== Step 1: Terminate existing connections ==="
docker exec rpi-finished-pgai-db psql -U postgres -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'ecoanp' AND pid <> pg_backend_pid();
"

echo "=== Step 2: Drop and recreate database ==="
docker exec rpi-finished-pgai-db psql -U postgres <<EOF
DROP DATABASE IF EXISTS ecoanp;
CREATE DATABASE ecoanp;
EOF

echo "=== Step 3: Install extensions (MUST BE FIRST!) ==="
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

-- Verify extensions
\dx
EOF

echo "=== Step 4: Run timescaledb_pre_restore() ==="
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp -c "
SELECT timescaledb_pre_restore();
"

echo "=== Step 5: Restore database with pg_restore ==="
docker exec rpi-finished-pgai-db pg_restore \
  -U postgres \
  -d ecoanp \
  --verbose \
  --no-owner \
  --no-acl \
  /backup/ecoanp_from_local_20251031.dump 2>&1 | tee /tmp/restore.log

echo "=== Step 6: Run timescaledb_post_restore() ==="
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp -c "
SELECT timescaledb_post_restore();
"

echo "=== Step 7: Analyze database ==="
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp -c "ANALYZE;"

echo "=== Step 8: Verify restoration ==="
docker exec rpi-finished-pgai-db psql -U postgres -d ecoanp <<EOF
-- Check table counts
SELECT
  schemaname,
  relname,
  n_live_tup as row_count
FROM pg_stat_user_tables
WHERE n_live_tup > 0
ORDER BY n_live_tup DESC
LIMIT 10;

-- Check influx_hist
SELECT COUNT(*) as total_count,
       MIN(ts)::date as earliest,
       MAX(ts)::date as latest
FROM influx_hist;

-- Check chunks
SELECT
  schemaname || '.' || relname as chunk_name,
  n_live_tup as rows
FROM pg_stat_user_tables
WHERE schemaname = '_timescaledb_internal'
  AND relname LIKE '%hyper%'
  AND n_live_tup > 0
ORDER BY n_live_tup DESC
LIMIT 10;
EOF

echo "=== Restoration complete! ==="
