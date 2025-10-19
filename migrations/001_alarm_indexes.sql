-- ============================================
-- Alarm Dashboard - Database Index Optimization
-- ============================================
-- 작성일: 2025-10-02
-- 목적: 알람 쿼리 성능 최적화를 위한 인덱스 생성
-- 참고: docs/alarm/alarm-data-flow.md

-- ============================================
-- 1. Triggered At Index (시간 범위 쿼리 최적화)
-- ============================================
-- 용도: WHERE triggered_at > NOW() - INTERVAL '24 hours'
-- 효과: 최근 24시간 알람 조회 속도 향상 (O(n) → O(log n))

CREATE INDEX IF NOT EXISTS idx_alarm_triggered_at
ON alarm_history(triggered_at DESC);

-- ============================================
-- 2. Severity + Status Composite Index
-- ============================================
-- 용도: WHERE level = 5 AND acknowledged = false
-- 효과: Severity + Status 복합 필터 시 성능 향상

CREATE INDEX IF NOT EXISTS idx_alarm_level_acknowledged
ON alarm_history(level DESC, acknowledged)
WHERE resolved = false;  -- 파셜 인덱스 (resolved된 알람 제외)

-- ============================================
-- 3. Sensor Tag Index (센서별 조회 최적화)
-- ============================================
-- 용도: WHERE sensor_data->>'tag_name' = 'D102'
-- 효과: 특정 센서의 알람 이력 조회 시 성능 향상

CREATE INDEX IF NOT EXISTS idx_alarm_sensor_tag
ON alarm_history((sensor_data->>'tag_name'));

-- ============================================
-- 4. Scenario + Triggered At Composite Index
-- ============================================
-- 용도: WHERE scenario_id = 'RULE_BASE' AND triggered_at > ...
-- 효과: 특정 시나리오의 최근 알람 조회 (가장 자주 사용되는 쿼리)

CREATE INDEX IF NOT EXISTS idx_alarm_scenario_triggered
ON alarm_history(scenario_id, triggered_at DESC)
WHERE resolved = false;

-- ============================================
-- 5. Unacknowledged Alarms Index
-- ============================================
-- 용도: WHERE acknowledged = false ORDER BY triggered_at DESC
-- 효과: 미확인 알람 조회 속도 향상

CREATE INDEX IF NOT EXISTS idx_alarm_unacknowledged
ON alarm_history(acknowledged, triggered_at DESC)
WHERE acknowledged = false AND resolved = false;

-- ============================================
-- 인덱스 사용 통계 확인 쿼리
-- ============================================
-- 실행 후 아래 쿼리로 인덱스 사용 여부 확인:
--
-- SELECT
--     schemaname,
--     tablename,
--     indexname,
--     idx_scan,
--     idx_tup_read,
--     idx_tup_fetch
-- FROM pg_stat_user_indexes
-- WHERE tablename = 'alarm_history'
-- ORDER BY idx_scan DESC;

-- ============================================
-- 쿼리 플랜 확인 예제
-- ============================================
-- 인덱스가 제대로 사용되는지 확인:
--
-- EXPLAIN ANALYZE
-- SELECT * FROM alarm_history
-- WHERE scenario_id = 'RULE_BASE'
--   AND triggered_at > NOW() - INTERVAL '24 hours'
--   AND level = 5
-- ORDER BY triggered_at DESC
-- LIMIT 20;
--
-- 출력에서 "Index Scan using idx_alarm_scenario_triggered" 확인

-- ============================================
-- 롤백 (필요 시)
-- ============================================
-- DROP INDEX IF EXISTS idx_alarm_triggered_at;
-- DROP INDEX IF EXISTS idx_alarm_level_acknowledged;
-- DROP INDEX IF EXISTS idx_alarm_sensor_tag;
-- DROP INDEX IF EXISTS idx_alarm_scenario_triggered;
-- DROP INDEX IF EXISTS idx_alarm_unacknowledged;
