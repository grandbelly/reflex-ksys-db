-- =====================================================
-- Virtual Tags Integration with Existing InfluxDB Views
-- 기존 influx_hist, influx_latest와 Virtual Tag 통합
-- =====================================================

-- 1. Virtual Tag 데이터를 influx_hist 형태로 변환하는 뷰
CREATE VIEW virtual_tags_as_influx AS
SELECT 
    time as ts,
    virtual_tag_id as tag_name,
    value,
    CASE 
        WHEN quality_code = 0 THEN 0  -- Good
        WHEN quality_code = 1 THEN 1  -- Uncertain 
        WHEN quality_code = 2 THEN 2  -- Bad
        ELSE 3                        -- Error
    END as qc,
    jsonb_build_object(
        'source', 'virtual_tag',
        'calculation_type', (SELECT calculation_type FROM virtual_tags vt WHERE vt.virtual_tag_id = vtv.virtual_tag_id),
        'calculation_time_ms', calculation_time_ms,
        'error_message', error_message
    ) as meta
FROM virtual_tag_values vtv
WHERE value IS NOT NULL;

-- 2. 기존 influx_latest를 Virtual Tag 포함으로 확장하는 통합 뷰
CREATE OR REPLACE VIEW influx_latest_with_virtual AS
-- 실제 센서 데이터
SELECT 
    tag_name,
    value,
    ts,
    'sensor' as source_type,
    qc as quality_code
FROM influx_latest

UNION ALL

-- Virtual Tag 데이터 (최신값만)
SELECT 
    virtual_tag_id as tag_name,
    value,
    time as ts,
    'virtual' as source_type,
    quality_code
FROM virtual_tag_latest
WHERE value IS NOT NULL;

-- 3. 통합된 태그 정보 뷰 (센서 + Virtual)
CREATE OR REPLACE VIEW all_tags_info AS
-- 실제 센서 태그
SELECT 
    tag_name,
    'sensor' as tag_type,
    NULL as description,
    NULL as unit,
    NULL as calculation_type,
    TRUE as enabled
FROM influx_tag

UNION ALL

-- Virtual 태그
SELECT 
    virtual_tag_id as tag_name,
    'virtual' as tag_type,
    description,
    unit,
    calculation_type,
    enabled
FROM virtual_tags;

-- 4. 히스토리 데이터 통합 뷰 (influx_hist + Virtual Tags)
CREATE OR REPLACE VIEW influx_hist_with_virtual AS
-- 실제 센서 히스토리
SELECT 
    ts,
    tag_name,
    value,
    qc,
    meta,
    'sensor' as source_type
FROM influx_hist

UNION ALL

-- Virtual Tag 히스토리
SELECT 
    time as ts,
    virtual_tag_id as tag_name,
    value,
    quality_code as qc,
    jsonb_build_object(
        'source', 'virtual_tag',
        'calculation_time_ms', calculation_time_ms,
        'error_message', error_message
    ) as meta,
    'virtual' as source_type
FROM virtual_tag_values
WHERE value IS NOT NULL;

-- 5. Virtual Tag 데이터를 influx_hist에 삽입하는 함수
CREATE OR REPLACE FUNCTION insert_virtual_tags_to_influx_hist()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_virtual_tag RECORD;
BEGIN
    -- 최근 계산된 Virtual Tag 값들을 influx_hist 형태로 삽입
    FOR v_virtual_tag IN
        SELECT 
            time,
            virtual_tag_id,
            value,
            quality_code,
            calculation_time_ms,
            error_message
        FROM virtual_tag_values vtv
        WHERE value IS NOT NULL
        AND NOT EXISTS (
            -- 이미 influx_hist에 동일한 시간/태그 데이터가 없는 경우만
            SELECT 1 FROM influx_hist ih 
            WHERE ih.ts = vtv.time 
            AND ih.tag_name = vtv.virtual_tag_id
        )
        ORDER BY time DESC
        LIMIT 1000  -- 한번에 최대 1000개만 처리
    LOOP
        -- Virtual Tag를 실제 센서처럼 influx_hist에 삽입
        INSERT INTO influx_hist (ts, tag_name, value, qc, meta)
        VALUES (
            v_virtual_tag.time,
            v_virtual_tag.virtual_tag_id,
            v_virtual_tag.value,
            v_virtual_tag.quality_code,
            jsonb_build_object(
                'source', 'virtual_tag',
                'calculation_time_ms', v_virtual_tag.calculation_time_ms,
                'error_message', v_virtual_tag.error_message
            )
        );
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Error inserting virtual tags to influx_hist: %', SQLERRM;
        RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- 6. Virtual Tag 자동 동기화 트리거
CREATE OR REPLACE FUNCTION sync_virtual_tags_to_influx()
RETURNS TRIGGER AS $$
BEGIN
    -- Virtual Tag 값이 새로 계산되면 influx_hist에도 추가
    IF NEW.value IS NOT NULL AND NEW.quality_code IN (0, 1) THEN
        INSERT INTO influx_hist (ts, tag_name, value, qc, meta)
        VALUES (
            NEW.time,
            NEW.virtual_tag_id,
            NEW.value,
            NEW.quality_code,
            jsonb_build_object(
                'source', 'virtual_tag',
                'calculation_time_ms', NEW.calculation_time_ms,
                'error_message', NEW.error_message
            )
        )
        ON CONFLICT (ts, tag_name) DO NOTHING;  -- 중복 방지
    END IF;
    
    -- Materialized View 업데이트 (비동기)
    PERFORM pg_notify('refresh_views', 'virtual_tag_latest');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Virtual Tag 값 삽입 시 트리거 연결
CREATE TRIGGER trigger_sync_virtual_to_influx
    AFTER INSERT ON virtual_tag_values
    FOR EACH ROW EXECUTE FUNCTION sync_virtual_tags_to_influx();

-- 7. Virtual Tag를 influx_tag 테이블에 등록하는 함수
CREATE OR REPLACE FUNCTION register_virtual_tags_as_sensors()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_virtual_tag RECORD;
BEGIN
    FOR v_virtual_tag IN
        SELECT virtual_tag_id, name, unit, description
        FROM virtual_tags 
        WHERE enabled = true
        AND NOT EXISTS (
            SELECT 1 FROM influx_tag it 
            WHERE it.tag_name = virtual_tags.virtual_tag_id
        )
    LOOP
        -- Virtual Tag를 influx_tag에 등록
        INSERT INTO influx_tag (tag_name, description, unit)
        VALUES (
            v_virtual_tag.virtual_tag_id,
            COALESCE(v_virtual_tag.description, v_virtual_tag.name),
            v_virtual_tag.unit
        )
        ON CONFLICT (tag_name) DO UPDATE SET
            description = EXCLUDED.description,
            unit = EXCLUDED.unit;
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- 8. 기존 집계 뷰에 Virtual Tag 포함시키는 함수
CREATE OR REPLACE FUNCTION create_virtual_tag_aggregates()
RETURNS VOID AS $$
BEGIN
    -- 1분 집계에 Virtual Tag 포함
    DROP VIEW IF EXISTS influx_agg_1m_with_virtual CASCADE;
    CREATE VIEW influx_agg_1m_with_virtual AS
    -- 기존 센서 1분 집계
    SELECT * FROM influx_agg_1m
    
    UNION ALL
    
    -- Virtual Tag 1분 집계
    SELECT 
        time_bucket('1 minute', time) as bucket,
        virtual_tag_id as tag_name,
        COUNT(*) as n,
        AVG(value) as avg,
        SUM(value) as sum,
        MIN(value) as min,
        MAX(value) as max,
        LAST(value, time) as last,
        FIRST(value, time) as first,
        (LAST(value, time) - FIRST(value, time)) as diff
    FROM virtual_tag_values
    WHERE value IS NOT NULL
    AND quality_code IN (0, 1)  -- Good, Uncertain만
    GROUP BY bucket, virtual_tag_id;

    -- 1일 집계에 Virtual Tag 포함  
    DROP VIEW IF EXISTS influx_agg_1d_with_virtual CASCADE;
    CREATE VIEW influx_agg_1d_with_virtual AS
    -- 기존 센서 1일 집계
    SELECT * FROM influx_agg_1d
    
    UNION ALL
    
    -- Virtual Tag 1일 집계
    SELECT 
        time_bucket('1 day', time) as bucket,
        virtual_tag_id as tag_name,
        COUNT(*) as n,
        AVG(value) as avg,
        SUM(value) as sum,
        MIN(value) as min,
        MAX(value) as max,
        LAST(value, time) as last,
        FIRST(value, time) as first,
        (LAST(value, time) - FIRST(value, time)) as diff
    FROM virtual_tag_values
    WHERE value IS NOT NULL
    AND quality_code IN (0, 1)
    GROUP BY bucket, virtual_tag_id;
END;
$$ LANGUAGE plpgsql;

-- 9. Virtual Tag 완전 통합 함수 (한번에 모든 작업 수행)
CREATE OR REPLACE FUNCTION integrate_virtual_tags_complete()
RETURNS TABLE(
    action TEXT,
    count INTEGER,
    status TEXT
) AS $$
DECLARE
    v_hist_count INTEGER;
    v_tag_count INTEGER;
BEGIN
    -- 1. Virtual Tag를 influx_tag에 등록
    v_tag_count := register_virtual_tags_as_sensors();
    RETURN QUERY SELECT 'register_tags'::TEXT, v_tag_count, 'completed'::TEXT;
    
    -- 2. Virtual Tag 히스토리를 influx_hist에 동기화
    v_hist_count := insert_virtual_tags_to_influx_hist();
    RETURN QUERY SELECT 'sync_history'::TEXT, v_hist_count, 'completed'::TEXT;
    
    -- 3. 집계 뷰 생성
    PERFORM create_virtual_tag_aggregates();
    RETURN QUERY SELECT 'create_aggregates'::TEXT, 0, 'completed'::TEXT;
    
    -- 4. Materialized View 업데이트
    REFRESH MATERIALIZED VIEW CONCURRENTLY virtual_tag_latest;
    RETURN QUERY SELECT 'refresh_views'::TEXT, 0, 'completed'::TEXT;
    
    RETURN QUERY SELECT 'integration'::TEXT, 0, 'all_completed'::TEXT;
END;
$$ LANGUAGE plpgsql;

-- 10. 통합 상태 확인 함수
CREATE OR REPLACE FUNCTION check_integration_status()
RETURNS TABLE(
    metric TEXT,
    sensor_count BIGINT,
    virtual_count BIGINT,
    total_count BIGINT
) AS $$
BEGIN
    -- 태그 등록 현황
    RETURN QUERY
    SELECT 
        'tags_registered'::TEXT,
        (SELECT COUNT(*) FROM influx_tag WHERE tag_name NOT IN (SELECT virtual_tag_id FROM virtual_tags)),
        (SELECT COUNT(*) FROM influx_tag WHERE tag_name IN (SELECT virtual_tag_id FROM virtual_tags)),
        (SELECT COUNT(*) FROM influx_tag);
    
    -- 히스토리 데이터 현황
    RETURN QUERY
    SELECT 
        'history_records'::TEXT,
        (SELECT COUNT(*) FROM influx_hist WHERE tag_name NOT IN (SELECT virtual_tag_id FROM virtual_tags)),
        (SELECT COUNT(*) FROM influx_hist WHERE tag_name IN (SELECT virtual_tag_id FROM virtual_tags)),
        (SELECT COUNT(*) FROM influx_hist);
    
    -- 최신 값 현황
    RETURN QUERY
    SELECT 
        'latest_values'::TEXT,
        (SELECT COUNT(*) FROM influx_latest WHERE tag_name NOT IN (SELECT virtual_tag_id FROM virtual_tags)),
        (SELECT COUNT(*) FROM influx_latest WHERE tag_name IN (SELECT virtual_tag_id FROM virtual_tags)),
        (SELECT COUNT(*) FROM influx_latest);
END;
$$ LANGUAGE plpgsql;

-- 통합 완료 메시지
SELECT 'Virtual Tags integration with InfluxDB views completed!' as status;
SELECT 'New views: influx_latest_with_virtual, all_tags_info, influx_hist_with_virtual' as info;
SELECT 'New functions: integrate_virtual_tags_complete(), check_integration_status()' as functions;