-- =====================================================
-- Virtual Tags System Functions
-- 계산 엔진 및 관리 함수들
-- =====================================================

-- 1. 수식 파서 함수 (단순한 사칙연산 지원)
CREATE OR REPLACE FUNCTION parse_expression(
    p_formula TEXT,
    p_variables JSONB,
    p_constants JSONB DEFAULT '{}'::jsonb
) RETURNS DOUBLE PRECISION AS $$
DECLARE
    v_result DOUBLE PRECISION;
    v_sql TEXT;
    v_var_name TEXT;
    v_var_config JSONB;
    v_var_value DOUBLE PRECISION;
    v_safe_formula TEXT;
BEGIN
    v_safe_formula := p_formula;
    
    -- Replace variables with actual values
    FOR v_var_name IN SELECT jsonb_object_keys(p_variables)
    LOOP
        v_var_config := p_variables->v_var_name;
        
        -- Get sensor value from influx_latest
        IF v_var_config->>'type' = 'sensor_tag' THEN
            SELECT value INTO v_var_value 
            FROM influx_latest 
            WHERE tag_name = v_var_config->>'tag_name'
            LIMIT 1;
            
            -- Replace variable with its value
            v_safe_formula := replace(v_safe_formula, v_var_name, COALESCE(v_var_value, 0)::TEXT);
        END IF;
    END LOOP;
    
    -- Replace constants
    FOR v_var_name IN SELECT jsonb_object_keys(p_constants)
    LOOP
        v_safe_formula := replace(v_safe_formula, v_var_name, (p_constants->>v_var_name));
    END LOOP;
    
    -- 안전성 체크: 허용된 연산자와 함수만 사용
    IF v_safe_formula ~ '[^0-9+\-*/.() ]' THEN
        RAISE EXCEPTION 'Formula contains unsafe characters: %', v_safe_formula;
    END IF;
    
    -- Execute the formula
    v_sql := 'SELECT ' || v_safe_formula;
    EXECUTE v_sql INTO v_result;
    
    RETURN v_result;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Expression parsing failed for formula "%" with variables "%": %', p_formula, p_variables, SQLERRM;
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- 2. 통계 계산 함수
CREATE OR REPLACE FUNCTION calculate_statistical_tag(
    p_config JSONB
) RETURNS DOUBLE PRECISION AS $$
DECLARE
    v_function TEXT;
    v_window INTERVAL;
    v_input_tags TEXT[];
    v_result DOUBLE PRECISION;
    v_sql TEXT;
    v_time_condition TEXT;
BEGIN
    v_function := p_config->'statistical'->>'function';
    v_window := (p_config->'statistical'->>'window')::INTERVAL;
    
    -- Extract input tags from JSON array
    SELECT ARRAY(SELECT jsonb_array_elements_text(p_config->'statistical'->'input_tags'))
    INTO v_input_tags;
    
    -- Time condition for window
    v_time_condition := 'ts > (NOW() - INTERVAL ''' || v_window || ''')';
    
    -- Build dynamic SQL for statistical calculation
    CASE v_function
        WHEN 'avg' THEN
            v_sql := 'SELECT AVG(value) FROM influx_latest WHERE tag_name = ANY($1)';
        WHEN 'sum' THEN
            v_sql := 'SELECT SUM(value) FROM influx_latest WHERE tag_name = ANY($1)';
        WHEN 'min' THEN
            v_sql := 'SELECT MIN(value) FROM influx_latest WHERE tag_name = ANY($1)';
        WHEN 'max' THEN
            v_sql := 'SELECT MAX(value) FROM influx_latest WHERE tag_name = ANY($1)';
        WHEN 'count' THEN
            v_sql := 'SELECT COUNT(*) FROM influx_latest WHERE tag_name = ANY($1)';
        WHEN 'stddev' THEN
            v_sql := 'SELECT STDDEV(value) FROM influx_latest WHERE tag_name = ANY($1)';
        ELSE
            RAISE EXCEPTION 'Unsupported statistical function: %', v_function;
    END CASE;
    
    EXECUTE v_sql USING v_input_tags INTO v_result;
    
    RETURN COALESCE(v_result, 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Statistical calculation failed for config "%": %', p_config, SQLERRM;
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- 3. 조건부 계산 함수
CREATE OR REPLACE FUNCTION calculate_conditional_tag(
    p_config JSONB
) RETURNS JSONB AS $$
DECLARE
    v_input_tag TEXT;
    v_input_value DOUBLE PRECISION;
    v_conditions JSONB;
    v_condition JSONB;
    v_result INTEGER;
    v_description TEXT;
    v_condition_str TEXT;
    v_threshold DOUBLE PRECISION;
    v_operator TEXT;
BEGIN
    v_input_tag := p_config->'conditional'->>'input_tag';
    v_conditions := p_config->'conditional'->'conditions';
    
    -- Get input value
    SELECT value INTO v_input_value 
    FROM influx_latest 
    WHERE tag_name = v_input_tag
    LIMIT 1;
    
    IF v_input_value IS NULL THEN
        RETURN jsonb_build_object('value', NULL, 'description', 'Input tag not found');
    END IF;
    
    -- Evaluate conditions
    FOR v_condition IN SELECT jsonb_array_elements(v_conditions)
    LOOP
        v_condition_str := v_condition->>'condition';
        
        -- Parse simple conditions (value > 85, value <= 50, etc.)
        IF v_condition_str LIKE '%>%' THEN
            v_threshold := regexp_replace(v_condition_str, '.*> *', '')::DOUBLE PRECISION;
            IF v_input_value > v_threshold THEN
                v_result := (v_condition->>'result')::INTEGER;
                v_description := v_condition->>'description';
                EXIT;
            END IF;
        ELSIF v_condition_str LIKE '%<%' THEN
            v_threshold := regexp_replace(v_condition_str, '.*< *', '')::DOUBLE PRECISION;
            IF v_input_value < v_threshold THEN
                v_result := (v_condition->>'result')::INTEGER;
                v_description := v_condition->>'description';
                EXIT;
            END IF;
        ELSIF v_condition_str LIKE '%>=%' THEN
            v_threshold := regexp_replace(v_condition_str, '.*>= *', '')::DOUBLE PRECISION;
            IF v_input_value >= v_threshold THEN
                v_result := (v_condition->>'result')::INTEGER;
                v_description := v_condition->>'description';
                EXIT;
            END IF;
        ELSIF v_condition_str LIKE '%<=%' THEN
            v_threshold := regexp_replace(v_condition_str, '.*<= *', '')::DOUBLE PRECISION;
            IF v_input_value <= v_threshold THEN
                v_result := (v_condition->>'result')::INTEGER;
                v_description := v_condition->>'description';
                EXIT;
            END IF;
        END IF;
    END LOOP;
    
    -- Default result if no conditions met
    IF v_result IS NULL THEN
        v_result := (p_config->'conditional'->>'default_result')::INTEGER;
        v_description := p_config->'conditional'->>'default_description';
    END IF;
    
    RETURN jsonb_build_object(
        'value', v_result, 
        'description', v_description,
        'input_value', v_input_value
    );
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Conditional calculation failed for config "%": %', p_config, SQLERRM;
        RETURN jsonb_build_object('value', NULL, 'description', 'Calculation error');
END;
$$ LANGUAGE plpgsql;

-- 4. 메인 Virtual Tag 계산 함수
CREATE OR REPLACE FUNCTION calculate_virtual_tag(
    p_virtual_tag_id VARCHAR(100)
) RETURNS TABLE(value DOUBLE PRECISION, quality_code INTEGER, error_message TEXT, calculation_time_ms INTEGER) AS $$
DECLARE
    v_config JSONB;
    v_calc_type VARCHAR(50);
    v_result DOUBLE PRECISION;
    v_quality INTEGER := 0;
    v_error TEXT := NULL;
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_calc_time_ms INTEGER;
    v_conditional_result JSONB;
BEGIN
    v_start_time := clock_timestamp();
    
    -- Get virtual tag configuration
    SELECT config, calculation_type
    INTO v_config, v_calc_type
    FROM virtual_tags 
    WHERE virtual_tag_id = p_virtual_tag_id AND enabled = true;
    
    IF NOT FOUND THEN
        RETURN QUERY SELECT NULL::DOUBLE PRECISION, 3, 'Virtual tag not found or disabled', 0;
        RETURN;
    END IF;
    
    BEGIN
        CASE v_calc_type
            WHEN 'expression' THEN
                v_result := parse_expression(
                    v_config->'expression'->>'formula',
                    v_config->'expression'->'variables',
                    v_config->'expression'->'constants'
                );
                
            WHEN 'statistical' THEN
                v_result := calculate_statistical_tag(v_config);
                
            WHEN 'conditional' THEN
                v_conditional_result := calculate_conditional_tag(v_config);
                v_result := (v_conditional_result->>'value')::DOUBLE PRECISION;
                
            ELSE
                v_quality := 3;
                v_error := 'Unknown calculation type: ' || v_calc_type;
        END CASE;
        
        -- Validation checks
        IF v_result IS NULL THEN
            v_quality := 2;
            v_error := 'Calculation returned null';
        ELSIF v_config ? 'validation' THEN
            -- Check min/max bounds
            IF v_config->'validation' ? 'min_value' AND v_result < (v_config->'validation'->>'min_value')::DOUBLE PRECISION THEN
                v_quality := 1;
                v_error := 'Value below minimum threshold';
            ELSIF v_config->'validation' ? 'max_value' AND v_result > (v_config->'validation'->>'max_value')::DOUBLE PRECISION THEN
                v_quality := 1;
                v_error := 'Value above maximum threshold';
            END IF;
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
            v_quality := 2;
            v_error := SQLERRM;
            v_result := NULL;
    END;
    
    v_end_time := clock_timestamp();
    v_calc_time_ms := EXTRACT(MILLISECONDS FROM (v_end_time - v_start_time))::INTEGER;
    
    RETURN QUERY SELECT v_result, v_quality, v_error, v_calc_time_ms;
END;
$$ LANGUAGE plpgsql;

-- 5. Virtual Tag 의존성 업데이트 함수
CREATE OR REPLACE FUNCTION update_virtual_tag_dependencies(
    p_virtual_tag_id VARCHAR(100)
) RETURNS INTEGER AS $$
DECLARE
    v_config JSONB;
    v_calc_type VARCHAR(50);
    v_var_name TEXT;
    v_input_tags TEXT[];
    v_count INTEGER := 0;
BEGIN
    -- Get virtual tag configuration
    SELECT config, calculation_type
    INTO v_config, v_calc_type
    FROM virtual_tags 
    WHERE virtual_tag_id = p_virtual_tag_id;
    
    IF NOT FOUND THEN
        RETURN 0;
    END IF;
    
    -- Clear existing dependencies
    DELETE FROM virtual_tag_dependencies WHERE virtual_tag_id = p_virtual_tag_id;
    
    -- Extract dependencies based on calculation type
    CASE v_calc_type
        WHEN 'expression' THEN
            -- Extract from variables
            FOR v_var_name IN SELECT jsonb_object_keys(v_config->'expression'->'variables')
            LOOP
                IF (v_config->'expression'->'variables'->v_var_name->>'type') = 'sensor_tag' THEN
                    INSERT INTO virtual_tag_dependencies (virtual_tag_id, source_tag_name, dependency_type)
                    VALUES (p_virtual_tag_id, v_config->'expression'->'variables'->v_var_name->>'tag_name', 'expression');
                    v_count := v_count + 1;
                END IF;
            END LOOP;
            
        WHEN 'statistical' THEN
            -- Extract from input_tags
            SELECT ARRAY(SELECT jsonb_array_elements_text(v_config->'statistical'->'input_tags'))
            INTO v_input_tags;
            
            FOREACH v_var_name IN ARRAY v_input_tags
            LOOP
                INSERT INTO virtual_tag_dependencies (virtual_tag_id, source_tag_name, dependency_type)
                VALUES (p_virtual_tag_id, v_var_name, 'statistical');
                v_count := v_count + 1;
            END LOOP;
            
        WHEN 'conditional' THEN
            -- Extract from input_tag
            INSERT INTO virtual_tag_dependencies (virtual_tag_id, source_tag_name, dependency_type)
            VALUES (p_virtual_tag_id, v_config->'conditional'->>'input_tag', 'conditional');
            v_count := v_count + 1;
    END CASE;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- 6. 배치 업데이트 함수
CREATE OR REPLACE FUNCTION batch_update_virtual_tags()
RETURNS INTEGER AS $$
DECLARE
    v_virtual_tag RECORD;
    v_calc_result RECORD;
    v_count INTEGER := 0;
BEGIN
    FOR v_virtual_tag IN 
        SELECT virtual_tag_id, update_frequency
        FROM virtual_tags 
        WHERE enabled = true
        ORDER BY virtual_tag_id
    LOOP
        -- Check if update is needed based on frequency
        IF NOT EXISTS (
            SELECT 1 FROM virtual_tag_values 
            WHERE virtual_tag_id = v_virtual_tag.virtual_tag_id
            AND time > (NOW() - v_virtual_tag.update_frequency)
        ) THEN
            -- Calculate virtual tag
            SELECT * INTO v_calc_result 
            FROM calculate_virtual_tag(v_virtual_tag.virtual_tag_id);
            
            -- Insert calculated value
            INSERT INTO virtual_tag_values (time, virtual_tag_id, value, quality_code, error_message, calculation_time_ms)
            VALUES (NOW(), v_virtual_tag.virtual_tag_id, v_calc_result.value, v_calc_result.quality_code, v_calc_result.error_message, v_calc_result.calculation_time_ms);
            
            v_count := v_count + 1;
        END IF;
    END LOOP;
    
    -- Update materialized view
    REFRESH MATERIALIZED VIEW CONCURRENTLY virtual_tag_latest;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- 7. Virtual Tag 상태 조회 함수
CREATE OR REPLACE FUNCTION get_virtual_tag_status(
    p_virtual_tag_id VARCHAR(100) DEFAULT NULL
) RETURNS TABLE(
    virtual_tag_id VARCHAR(100),
    name VARCHAR(200),
    enabled BOOLEAN,
    last_update TIMESTAMPTZ,
    last_value DOUBLE PRECISION,
    quality_code INTEGER,
    error_message TEXT,
    dependencies_count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        vt.virtual_tag_id,
        vt.name,
        vt.enabled,
        vtl.time as last_update,
        vtl.value as last_value,
        vtl.quality_code,
        vtl.error_message,
        COALESCE(deps.dep_count, 0) as dependencies_count
    FROM virtual_tags vt
    LEFT JOIN virtual_tag_latest vtl ON vt.virtual_tag_id = vtl.virtual_tag_id
    LEFT JOIN (
        SELECT virtual_tag_id, COUNT(*) as dep_count
        FROM virtual_tag_dependencies
        GROUP BY virtual_tag_id
    ) deps ON vt.virtual_tag_id = deps.virtual_tag_id
    WHERE (p_virtual_tag_id IS NULL OR vt.virtual_tag_id = p_virtual_tag_id)
    ORDER BY vt.virtual_tag_id;
END;
$$ LANGUAGE plpgsql;

-- 함수 생성 완료 메시지
SELECT 'Virtual Tags calculation functions created successfully!' as status;
SELECT 'Functions: parse_expression, calculate_statistical_tag, calculate_conditional_tag, calculate_virtual_tag, batch_update_virtual_tags, get_virtual_tag_status' as functions;