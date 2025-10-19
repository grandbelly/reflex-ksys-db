-- ============================================================================
-- Virtual Tag Calculation Migration to pg_cron
-- ============================================================================
-- Purpose: Migrate virtual tag calculations from Python scheduler to database
-- Schedule: Every 1 minute at :00 seconds
-- Author: Migration from virtual-tag-scheduler container
-- Date: 2025-10-11
-- ============================================================================

-- Step 1: Install pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Step 2: Create calculation function
CREATE OR REPLACE FUNCTION calculate_virtual_tags()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_tag RECORD;
    v_value NUMERIC;
    v_sensor_data JSONB := '{}'::jsonb;
    v_source_tag TEXT;
    v_expression TEXT;
    v_result NUMERIC;
    v_timestamp TIMESTAMPTZ := NOW();
    v_calculated_count INT := 0;
BEGIN
    -- Loop through all active virtual tags
    FOR v_tag IN
        SELECT
            tag_name,
            formula_type,
            formula,
            source_tags,
            aggregation_function,
            aggregation_window,
            condition,
            true_value,
            false_value,
            unit
        FROM virtual_tag_definitions
        WHERE is_active = true
        ORDER BY formula_type, tag_name
    LOOP
        BEGIN
            v_value := NULL;

            -- Get source sensor data
            v_sensor_data := '{}'::jsonb;
            FOREACH v_source_tag IN ARRAY v_tag.source_tags
            LOOP
                SELECT jsonb_object_agg(tag_name, value)
                INTO v_sensor_data
                FROM (
                    SELECT v_sensor_data || jsonb_build_object(tag_name, value::text) as agg
                    FROM influx_latest
                    WHERE tag_name = v_source_tag
                ) sub, LATERAL (SELECT agg FROM (SELECT sub.agg) x) final(tag_name, value);

                -- Simpler approach - get individual values
                SELECT value INTO v_value
                FROM influx_latest
                WHERE tag_name = v_source_tag;

                IF v_value IS NOT NULL THEN
                    v_sensor_data := v_sensor_data || jsonb_build_object(v_source_tag, v_value);
                END IF;
            END LOOP;

            -- Calculate based on formula type
            CASE v_tag.formula_type
                WHEN 'arithmetic' THEN
                    -- Arithmetic formula: INLET_PRESSURE - OUTLET_PRESSURE
                    -- Replace tag names with values
                    v_expression := v_tag.formula;
                    FOREACH v_source_tag IN ARRAY v_tag.source_tags
                    LOOP
                        IF v_sensor_data ? v_source_tag THEN
                            v_expression := REPLACE(
                                v_expression,
                                v_source_tag,
                                (v_sensor_data->>v_source_tag)::TEXT
                            );
                        END IF;
                    END LOOP;

                    -- Handle division by zero for RECOVERY_RATE
                    IF v_tag.tag_name = 'RECOVERY_RATE' THEN
                        DECLARE
                            v_feed_flow NUMERIC;
                            v_product_flow NUMERIC;
                        BEGIN
                            v_feed_flow := (v_sensor_data->>'FEED_FLOW')::NUMERIC;
                            v_product_flow := (v_sensor_data->>'PRODUCT_FLOW')::NUMERIC;

                            IF v_feed_flow > 0 THEN
                                v_value := (v_product_flow / v_feed_flow) * 100;
                            ELSE
                                v_value := 0;
                            END IF;
                        END;
                    ELSIF v_tag.tag_name = 'PRESSURE_DIFF' THEN
                        -- PRESSURE_DIFF = INLET_PRESSURE - OUTLET_PRESSURE
                        DECLARE
                            v_inlet NUMERIC;
                            v_outlet NUMERIC;
                        BEGIN
                            v_inlet := (v_sensor_data->>'INLET_PRESSURE')::NUMERIC;
                            v_outlet := (v_sensor_data->>'OUTLET_PRESSURE')::NUMERIC;
                            v_value := v_inlet - v_outlet;
                        END;
                    ELSE
                        -- Try to evaluate expression (simplified - only basic operations)
                        -- For complex expressions, implement specific logic
                        v_value := NULL;
                    END IF;

                WHEN 'conditional' THEN
                    -- Conditional: IF(FEED_FLOW > 1.0, time_delta, 0)
                    IF v_tag.tag_name = 'OPERATING_TIME' THEN
                        DECLARE
                            v_feed_flow NUMERIC;
                        BEGIN
                            v_feed_flow := (v_sensor_data->>'FEED_FLOW')::NUMERIC;
                            IF v_feed_flow > 1.0 THEN
                                v_value := 1.0; -- 1 minute time delta
                            ELSE
                                v_value := 0;
                            END IF;
                        END;
                    END IF;

                WHEN 'aggregation' THEN
                    -- Aggregation: SUM(PRODUCT_FLOW * time_delta) OVER (1 hour)
                    IF v_tag.tag_name = 'TOTAL_PRODUCT_VOLUME_1H' THEN
                        SELECT COALESCE(
                            SUM(
                                value *
                                COALESCE(
                                    EXTRACT(EPOCH FROM (ts - LAG(ts) OVER (ORDER BY ts))) / 60.0,
                                    1.0
                                )
                            ),
                            0
                        )
                        INTO v_value
                        FROM influx_hist
                        WHERE tag_name = 'PRODUCT_FLOW'
                          AND ts >= v_timestamp - v_tag.aggregation_window
                          AND ts <= v_timestamp;
                    END IF;
            END CASE;

            -- Store calculated value in influx_hist
            IF v_value IS NOT NULL THEN
                INSERT INTO influx_hist (ts, tag_name, value, quality)
                VALUES (v_timestamp, v_tag.tag_name, v_value, 0)
                ON CONFLICT (ts, tag_name) DO UPDATE
                SET value = EXCLUDED.value;

                v_calculated_count := v_calculated_count + 1;

                RAISE NOTICE '✅ % = % %', v_tag.tag_name, ROUND(v_value::NUMERIC, 2), COALESCE(v_tag.unit, '');
            END IF;

        EXCEPTION
            WHEN division_by_zero THEN
                RAISE NOTICE '⚠️  %: Division by zero', v_tag.tag_name;
                -- Store 0 for division by zero
                INSERT INTO influx_hist (ts, tag_name, value, quality)
                VALUES (v_timestamp, v_tag.tag_name, 0, 0)
                ON CONFLICT (ts, tag_name) DO UPDATE
                SET value = EXCLUDED.value;
            WHEN OTHERS THEN
                RAISE NOTICE '❌ %: %', v_tag.tag_name, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE '💾 Stored % Virtual Tag values at %', v_calculated_count, v_timestamp;
END;
$$;

-- Add helpful comment
COMMENT ON FUNCTION calculate_virtual_tags() IS
'Calculate all active virtual tags and store in influx_hist.
Runs every 1 minute via pg_cron scheduler.
Replaces Python-based virtual-tag-scheduler container.';

-- Step 3: Schedule the function to run every minute at :00 seconds
-- First, clear any existing schedule for virtual tags
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'calculate_virtual_tags_every_minute';

-- Schedule: Every 1 minute
SELECT cron.schedule(
    'calculate_virtual_tags_every_minute',  -- job name
    '* * * * *',                            -- every minute at :00 seconds
    'SELECT calculate_virtual_tags()'       -- command
);

-- Step 4: Verify schedule
SELECT
    jobid,
    jobname,
    schedule,
    command,
    active
FROM cron.job
WHERE jobname = 'calculate_virtual_tags_every_minute';

-- Step 5: Test immediate execution
SELECT calculate_virtual_tags();

-- Step 6: View recent virtual tag data
SELECT
    ts AT TIME ZONE 'Asia/Seoul' as ts_kst,
    tag_name,
    ROUND(value::NUMERIC, 2) as value
FROM influx_hist
WHERE tag_name IN ('RECOVERY_RATE', 'PRESSURE_DIFF', 'OPERATING_TIME', 'TOTAL_PRODUCT_VOLUME_1H')
  AND ts >= NOW() - INTERVAL '5 minutes'
ORDER BY tag_name, ts DESC
LIMIT 20;

-- ============================================================================
-- Migration Complete
-- ============================================================================
-- Next steps:
-- 1. Verify pg_cron is running: SELECT * FROM cron.job;
-- 2. Monitor logs: docker logs pgai-db -f | grep -i virtual
-- 3. Stop Python scheduler: docker-compose stop virtual-tag-scheduler
-- 4. Remove from docker-compose.yml (optional)
-- ============================================================================
