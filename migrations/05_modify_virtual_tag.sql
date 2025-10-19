-- =====================================================
-- Virtual Tag 수정 템플릿
-- 기존 Virtual Tag를 수정할 때 사용하는 템플릿
-- =====================================================

-- 사용법:
-- 1. 수정하고 싶은 템플릿을 복사하여 실제 값으로 변경
-- 2. psql 또는 pgAdmin에서 실행
-- 3. 필요시 의존성 재계산

-- ===========================================
-- 1. Virtual Tag 활성화/비활성화
-- ===========================================

-- 특정 Virtual Tag 비활성화
-- UPDATE virtual_tags SET enabled = false WHERE virtual_tag_id = 'VIRTUAL_TAG_ID';

-- 특정 Virtual Tag 활성화
-- UPDATE virtual_tags SET enabled = true WHERE virtual_tag_id = 'VIRTUAL_TAG_ID';

-- 여러 Virtual Tag 일괄 비활성화
-- UPDATE virtual_tags SET enabled = false WHERE virtual_tag_id IN ('TAG1', 'TAG2', 'TAG3');

-- ===========================================
-- 2. Virtual Tag 기본 정보 수정
-- ===========================================

-- 이름, 설명, 단위 수정
/*
UPDATE virtual_tags 
SET 
    name = 'New Name',
    description = 'New Description', 
    unit = 'new_unit',
    updated_at = NOW()
WHERE virtual_tag_id = 'VIRTUAL_TAG_ID';
*/

-- 업데이트 주기 변경
/*
UPDATE virtual_tags 
SET 
    update_frequency = '1 minute'::interval,
    updated_at = NOW()
WHERE virtual_tag_id = 'VIRTUAL_TAG_ID';
*/

-- ===========================================
-- 3. 수식 기반 Virtual Tag 수정
-- ===========================================

-- 수식 변경
/*
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{expression,formula}',
        '"NEW_VAR1 * 2 + NEW_VAR2"'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'EXPRESSION_TAG_ID';
*/

-- 변수 추가/수정
/*
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{expression,variables,NEW_VAR}',
        '{
            "type": "sensor_tag",
            "source": "influx_latest",
            "tag_name": "NEW_SENSOR_TAG"
        }'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'EXPRESSION_TAG_ID';
*/

-- 상수값 추가/수정
/*
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{expression,constants,NEW_CONSTANT}',
        '1.25'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'EXPRESSION_TAG_ID';
*/

-- 전체 설정 교체 (수식 기반)
/*
UPDATE virtual_tags 
SET 
    config = '{
        "expression": {
            "formula": "UPDATED_VAR1 + UPDATED_VAR2 * FACTOR",
            "variables": {
                "UPDATED_VAR1": {
                    "type": "sensor_tag",
                    "source": "influx_latest",
                    "tag_name": "UPDATED_SENSOR_1"
                },
                "UPDATED_VAR2": {
                    "type": "sensor_tag",
                    "source": "influx_latest", 
                    "tag_name": "UPDATED_SENSOR_2"
                }
            },
            "constants": {
                "FACTOR": 2.5
            }
        },
        "validation": {
            "min_value": 0,
            "max_value": 200
        }
    }'::jsonb,
    updated_at = NOW()
WHERE virtual_tag_id = 'EXPRESSION_TAG_ID';
*/

-- ===========================================
-- 4. 통계 기반 Virtual Tag 수정
-- ===========================================

-- 통계 함수 변경 (avg -> sum)
/*
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{statistical,function}',
        '"sum"'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'STATISTICAL_TAG_ID';
*/

-- 시간 윈도우 변경
/*
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{statistical,window}',
        '"10 minutes"'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'STATISTICAL_TAG_ID';
*/

-- 입력 태그 목록 변경
/*
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{statistical,input_tags}',
        '["NEW_TAG_1", "NEW_TAG_2", "NEW_TAG_3", "NEW_TAG_4"]'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'STATISTICAL_TAG_ID';
*/

-- ===========================================
-- 5. 조건부 Virtual Tag 수정
-- ===========================================

-- 입력 태그 변경
/*
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{conditional,input_tag}',
        '"NEW_INPUT_TAG"'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'CONDITIONAL_TAG_ID';
*/

-- 전체 조건 교체
/*
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{conditional,conditions}',
        '[
            {
                "condition": "value > 90",
                "result": 4,
                "description": "Very High"
            },
            {
                "condition": "value > 75",
                "result": 3,
                "description": "High"
            },
            {
                "condition": "value > 50",
                "result": 2,
                "description": "Medium"
            },
            {
                "condition": "value > 25",
                "result": 1,
                "description": "Low"
            }
        ]'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'CONDITIONAL_TAG_ID';
*/

-- ===========================================
-- 6. 검증 규칙 추가/수정
-- ===========================================

-- 검증 규칙 추가
/*
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{validation}',
        '{
            "min_value": -50,
            "max_value": 150,
            "data_quality_check": true
        }'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'ANY_TAG_ID';
*/

-- ===========================================
-- 실제 수정 예시
-- ===========================================

-- 예시 1: HEAT_EXCHANGER_EFF_01 태그의 수식 수정
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{expression,formula}',
        '"((TEMP_IN - TEMP_OUT) / (TEMP_IN - TEMP_AMBIENT)) * EFFICIENCY_FACTOR"'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'HEAT_EXCHANGER_EFF_01';

-- 효율성 팩터 상수 추가
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{expression,constants,EFFICIENCY_FACTOR}',
        '0.98'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'HEAT_EXCHANGER_EFF_01';

-- 예시 2: TEMP_AVG_REACTOR 태그의 입력 센서 추가
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{statistical,input_tags}',
        '["TT_REACTOR_01", "TT_REACTOR_02", "TT_REACTOR_03", "TT_REACTOR_04", "TT_REACTOR_05"]'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'TEMP_AVG_REACTOR';

-- 예시 3: TEMP_ALARM_LEVEL 태그의 임계값 조정
UPDATE virtual_tags 
SET 
    config = jsonb_set(
        config,
        '{conditional,conditions}',
        '[
            {
                "condition": "value > 90",
                "result": 3,
                "description": "Critical High"
            },
            {
                "condition": "value > 75",
                "result": 2,
                "description": "Warning High"
            },
            {
                "condition": "value > 55",
                "result": 1,
                "description": "Normal High"
            }
        ]'
    ),
    updated_at = NOW()
WHERE virtual_tag_id = 'TEMP_ALARM_LEVEL';

-- ===========================================
-- 수정 후 의존성 업데이트 및 검증
-- ===========================================

-- 의존성 재계산 (수정된 태그들)
SELECT update_virtual_tag_dependencies('HEAT_EXCHANGER_EFF_01');
SELECT update_virtual_tag_dependencies('TEMP_AVG_REACTOR');
SELECT update_virtual_tag_dependencies('TEMP_ALARM_LEVEL');

-- 수정 결과 확인
SELECT virtual_tag_id, name, updated_at, enabled 
FROM virtual_tags 
WHERE virtual_tag_id IN ('HEAT_EXCHANGER_EFF_01', 'TEMP_AVG_REACTOR', 'TEMP_ALARM_LEVEL');

-- 계산 테스트 (선택사항)
-- SELECT * FROM calculate_virtual_tag('HEAT_EXCHANGER_EFF_01');

-- 수정 완료 메시지
SELECT 'Virtual tags modified successfully!' as status;