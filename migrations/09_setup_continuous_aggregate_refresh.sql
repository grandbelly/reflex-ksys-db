-- ============================================
-- 05_setup_continuous_aggregate_refresh.sql
-- Continuous Aggregate 자동 갱신 정책 설정
-- Docker 재시작 시에도 유지됨
-- ============================================

-- 1분 Aggregate: 매 1분마다 갱신
SELECT add_continuous_aggregate_policy('influx_agg_1m',
  start_offset => INTERVAL '2 hours',
  end_offset => INTERVAL '1 minute',
  schedule_interval => INTERVAL '1 minute',
  if_not_exists => true
);

-- 10분 Aggregate: 매 10분마다 갱신
SELECT add_continuous_aggregate_policy('influx_agg_10m',
  start_offset => INTERVAL '2 hours',
  end_offset => INTERVAL '10 minutes',
  schedule_interval => INTERVAL '10 minutes',
  if_not_exists => true
);

-- 1시간 Aggregate: 매 1시간마다 갱신
SELECT add_continuous_aggregate_policy('influx_agg_1h',
  start_offset => INTERVAL '7 days',
  end_offset => INTERVAL '1 hour',
  schedule_interval => INTERVAL '1 hour',
  if_not_exists => true
);

-- 1일 Aggregate: 매일 갱신
SELECT add_continuous_aggregate_policy('influx_agg_1d',
  start_offset => INTERVAL '30 days',
  end_offset => INTERVAL '1 day',
  schedule_interval => INTERVAL '1 day',
  if_not_exists => true
);

-- predictions_hourly Aggregate: 매 1시간마다 갱신
SELECT add_continuous_aggregate_policy('predictions_hourly',
  start_offset => INTERVAL '7 days',
  end_offset => INTERVAL '1 hour',
  schedule_interval => INTERVAL '1 hour',
  if_not_exists => true
);

-- 설정 확인
DO $$
BEGIN
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'Continuous Aggregate Policies configured:';
    RAISE NOTICE '- influx_agg_1m: every 1 minute';
    RAISE NOTICE '- influx_agg_10m: every 10 minutes';
    RAISE NOTICE '- influx_agg_1h: every 1 hour';
    RAISE NOTICE '- influx_agg_1d: every 1 day';
    RAISE NOTICE '- predictions_hourly: every 1 hour';
    RAISE NOTICE '===========================================';
END $$;
