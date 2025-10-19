-- ============================================================================
-- Virtual Tag Calculation with pg_cron (DB-based scheduler)
-- ============================================================================
-- Purpose: Calculate virtual tags entirely in database every 1 minute
-- Replaces: Python virtual-tag-scheduler container
-- Schedule: Every 1 minute at :00 seconds
-- ============================================================================

-- Step 1: Create pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Step 2: Create simplified virtual tag calculation function
CREATE OR REPLACE FUNCTION calculate_virtual_tags()
RETURNS TABLE(vtag_name TEXT, vtag_value NUMERIC, vtag_status TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_timestamp TIMESTAMPTZ := NOW();
    v_inlet_pressure NUMERIC;
    v_outlet_pressure NUMERIC;
    v_feed_flow NUMERIC;
    v_product_flow NUMERIC;
    v_calculated_count INT := 0;
BEGIN
    -- Get latest sensor values needed for all virtual tags
    SELECT
        MAX(CASE WHEN il.tag_name = 'INLET_PRESSURE' THEN il.value END),
        MAX(CASE WHEN il.tag_name = 'OUTLET_PRESSURE' THEN il.value END),
        MAX(CASE WHEN il.tag_name = 'FEED_FLOW' THEN il.value END),
        MAX(CASE WHEN il.tag_name = 'PRODUCT_FLOW' THEN il.value END)
    INTO
        v_inlet_pressure,
        v_outlet_pressure,
        v_feed_flow,
        v_product_flow
    FROM influx_latest il
    WHERE il.tag_name IN ('INLET_PRESSURE', 'OUTLET_PRESSURE', 'FEED_FLOW', 'PRODUCT_FLOW');

    -- ========================================================================
    -- 1. PRESSURE_DIFF = INLET_PRESSURE - OUTLET_PRESSURE
    -- ========================================================================
    IF v_inlet_pressure IS NOT NULL AND v_outlet_pressure IS NOT NULL THEN
        INSERT INTO influx_hist (ts, tag_name, value, quality)
        VALUES (v_timestamp, 'PRESSURE_DIFF', v_inlet_pressure - v_outlet_pressure, 0)
        ON CONFLICT (ts, tag_name) DO UPDATE SET value = EXCLUDED.value;

        v_calculated_count := v_calculated_count + 1;
        RETURN QUERY SELECT 'PRESSURE_DIFF'::TEXT, v_inlet_pressure - v_outlet_pressure, 'OK'::TEXT;
    ELSE
        RETURN QUERY SELECT 'PRESSURE_DIFF'::TEXT, NULL::NUMERIC, 'MISSING_DATA'::TEXT;
    END IF;

    -- ========================================================================
    -- 2. RECOVERY_RATE = (PRODUCT_FLOW / FEED_FLOW) * 100
    -- ========================================================================
    IF v_feed_flow IS NOT NULL AND v_product_flow IS NOT NULL THEN
        IF v_feed_flow > 0 THEN
            INSERT INTO influx_hist (ts, tag_name, value, quality)
            VALUES (v_timestamp, 'RECOVERY_RATE', (v_product_flow / v_feed_flow) * 100, 0)
            ON CONFLICT (ts, tag_name) DO UPDATE SET value = EXCLUDED.value;

            v_calculated_count := v_calculated_count + 1;
            RETURN QUERY SELECT 'RECOVERY_RATE'::TEXT, (v_product_flow / v_feed_flow) * 100, 'OK'::TEXT;
        ELSE
            -- Division by zero - store 0
            INSERT INTO influx_hist (ts, tag_name, value, quality)
            VALUES (v_timestamp, 'RECOVERY_RATE', 0, 0)
            ON CONFLICT (ts, tag_name) DO UPDATE SET value = EXCLUDED.value;

            v_calculated_count := v_calculated_count + 1;
            RETURN QUERY SELECT 'RECOVERY_RATE'::TEXT, 0::NUMERIC, 'DIV_BY_ZERO'::TEXT;
        END IF;
    ELSE
        RETURN QUERY SELECT 'RECOVERY_RATE'::TEXT, NULL::NUMERIC, 'MISSING_DATA'::TEXT;
    END IF;

    -- ========================================================================
    -- 3. OPERATING_TIME = IF(FEED_FLOW > 1.0, 1, 0) minutes
    -- ========================================================================
    IF v_feed_flow IS NOT NULL THEN
        IF v_feed_flow > 1.0 THEN
            INSERT INTO influx_hist (ts, tag_name, value, quality)
            VALUES (v_timestamp, 'OPERATING_TIME', 1.0, 0)
            ON CONFLICT (ts, tag_name) DO UPDATE SET value = EXCLUDED.value;

            v_calculated_count := v_calculated_count + 1;
            RETURN QUERY SELECT 'OPERATING_TIME'::TEXT, 1.0::NUMERIC, 'OK'::TEXT;
        ELSE
            INSERT INTO influx_hist (ts, tag_name, value, quality)
            VALUES (v_timestamp, 'OPERATING_TIME', 0, 0)
            ON CONFLICT (ts, tag_name) DO UPDATE SET value = EXCLUDED.value;

            v_calculated_count := v_calculated_count + 1;
            RETURN QUERY SELECT 'OPERATING_TIME'::TEXT, 0::NUMERIC, 'OK'::TEXT;
        END IF;
    ELSE
        RETURN QUERY SELECT 'OPERATING_TIME'::TEXT, NULL::NUMERIC, 'MISSING_DATA'::TEXT;
    END IF;

    -- ========================================================================
    -- 4. TOTAL_PRODUCT_VOLUME_1H = SUM(PRODUCT_FLOW * time_delta) over 1 hour
    -- ========================================================================
    DECLARE
        v_total_volume NUMERIC;
    BEGIN
        WITH time_deltas AS (
            SELECT
                value,
                COALESCE(
                    EXTRACT(EPOCH FROM (ts - LAG(ts) OVER (ORDER BY ts))) / 60.0,
                    1.0
                ) as delta_minutes
            FROM influx_hist
            WHERE tag_name = 'PRODUCT_FLOW'
              AND ts >= v_timestamp - INTERVAL '1 hour'
              AND ts <= v_timestamp
        )
        SELECT COALESCE(SUM(value * delta_minutes), 0)
        INTO v_total_volume
        FROM time_deltas;

        INSERT INTO influx_hist (ts, tag_name, value, quality)
        VALUES (v_timestamp, 'TOTAL_PRODUCT_VOLUME_1H', v_total_volume, 0)
        ON CONFLICT (ts, tag_name) DO UPDATE SET value = EXCLUDED.value;

        v_calculated_count := v_calculated_count + 1;
        RETURN QUERY SELECT 'TOTAL_PRODUCT_VOLUME_1H'::TEXT, v_total_volume, 'OK'::TEXT;
    END;

    -- Log summary
    RAISE NOTICE '💾 Calculated % virtual tags at %', v_calculated_count, v_timestamp;
END;
$$;

COMMENT ON FUNCTION calculate_virtual_tags() IS
'Calculate all 4 virtual tags (PRESSURE_DIFF, RECOVERY_RATE, OPERATING_TIME, TOTAL_PRODUCT_VOLUME_1H)
and store in influx_hist table. Called by pg_cron every 1 minute.';

-- Step 3: Test the function
SELECT * FROM calculate_virtual_tags();

-- Step 4: Schedule with pg_cron
-- Remove any existing schedules
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname LIKE 'calculate_virtual_tags%';

-- Schedule to run every 1 minute
SELECT cron.schedule(
    'calculate_virtual_tags_every_minute',
    '* * * * *',  -- Every minute
    'SELECT calculate_virtual_tags()'
);

-- Step 5: Verify the schedule
SELECT
    jobid,
    jobname,
    schedule,
    command,
    active,
    database
FROM cron.job
WHERE jobname = 'calculate_virtual_tags_every_minute';

-- Step 6: Check recent executions
SELECT
    jobid,
    runid,
    job_pid,
    database,
    username,
    command,
    status,
    return_message,
    start_time AT TIME ZONE 'Asia/Seoul' as start_time_kst,
    end_time AT TIME ZONE 'Asia/Seoul' as end_time_kst
FROM cron.job_run_details
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'calculate_virtual_tags_every_minute')
ORDER BY start_time DESC
LIMIT 5;

-- ============================================================================
-- Migration Complete - DB-based Virtual Tag Calculation Active
-- ============================================================================
-- Next steps:
-- 1. Monitor: SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
-- 2. Stop Python scheduler: docker-compose stop virtual-tag-scheduler
-- 3. Remove from docker-compose.yml (optional)
-- ============================================================================
