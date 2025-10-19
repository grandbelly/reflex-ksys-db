-- =====================================================
-- Virtual Tag 추가 템플릿
-- 새로운 Virtual Tag를 추가할 때 사용하는 템플릿
-- =====================================================

-- 사용법:
-- 1. 아래 템플릿을 복사하여 수정
-- 2. psql 또는 pgAdmin에서 실행
-- 3. 의존성 자동 업데이트

-- ===========================================
-- 1. 수식 기반 Virtual Tag 추가 템플릿
-- ===========================================
/*
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config, update_frequency)
VALUES (
    'NEW_EXPRESSION_TAG',  -- 고유 ID (변경 필수)
    'New Expression Tag',  -- 표시명
    'Description of the tag calculation',  -- 설명
    'unit',  -- 단위 (°C, %, bar, m³/h 등)
    'expression',
    '{
        "expression": {
            "formula": "VAR1 + VAR2 * CONSTANT1",  -- 수식 (변경 필수)
            "variables": {
                "VAR1": {
                    "type": "sensor_tag",
                    "source": "influx_latest",
                    "tag_name": "ACTUAL_SENSOR_TAG_1"  -- 실제 센서 태그명 (변경 필수)
                },
                "VAR2": {
                    "type": "sensor_tag", 
                    "source": "influx_latest",
                    "tag_name": "ACTUAL_SENSOR_TAG_2"  -- 실제 센서 태그명 (변경 필수)
                }
            },
            "constants": {
                "CONSTANT1": 1.5  -- 상수값 (선택사항)
            }
        },
        "validation": {
            "min_value": 0,    -- 최소값 검증 (선택사항)
            "max_value": 100   -- 최대값 검증 (선택사항)
        }
    }'::jsonb,
    '30 seconds'::interval  -- 업데이트 주기 (선택사항, 기본: 10초)
);

-- 의존성 자동 업데이트
SELECT update_virtual_tag_dependencies('NEW_EXPRESSION_TAG');
*/

-- ===========================================
-- 2. 통계 기반 Virtual Tag 추가 템플릿
-- ===========================================
/*
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config)
VALUES (
    'NEW_STATISTICAL_TAG',  -- 고유 ID (변경 필수)
    'New Statistical Tag',  -- 표시명
    'Statistical calculation description',  -- 설명
    'unit',  -- 단위
    'statistical',
    '{
        "statistical": {
            "function": "avg",  -- avg, sum, min, max, count, stddev 중 선택 (변경 필수)
            "window": "5 minutes",  -- 시간 윈도우 (변경 가능)
            "input_tags": [  -- 입력 태그 목록 (변경 필수)
                "SENSOR_TAG_1",
                "SENSOR_TAG_2", 
                "SENSOR_TAG_3"
            ]
        }
    }'::jsonb
);

-- 의존성 자동 업데이트
SELECT update_virtual_tag_dependencies('NEW_STATISTICAL_TAG');
*/

-- ===========================================
-- 3. 조건부 Virtual Tag 추가 템플릿
-- ===========================================
/*
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config)
VALUES (
    'NEW_CONDITIONAL_TAG',  -- 고유 ID (변경 필수)
    'New Conditional Tag',  -- 표시명
    'Conditional logic description',  -- 설명
    'level',  -- 단위 (보통 level, status 등)
    'conditional',
    '{
        "conditional": {
            "input_tag": "INPUT_SENSOR_TAG",  -- 입력 센서 태그 (변경 필수)
            "conditions": [
                {
                    "condition": "value > 80",  -- 조건 (변경 필수)
                    "result": 3,               -- 결과값
                    "description": "High"      -- 설명
                },
                {
                    "condition": "value > 60", 
                    "result": 2,
                    "description": "Medium"
                },
                {
                    "condition": "value > 30",
                    "result": 1, 
                    "description": "Low"
                }
            ],
            "default_result": 0,
            "default_description": "Normal"
        }
    }'::jsonb
);

-- 의존성 자동 업데이트
SELECT update_virtual_tag_dependencies('NEW_CONDITIONAL_TAG');
*/

-- ===========================================
-- 실제 추가 예시 (템플릿을 사용한 새 태그)
-- ===========================================

-- 예시 1: 냉각 효율성 계산
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config)
VALUES (
    'COOLING_EFFICIENCY',
    'Cooling System Efficiency',
    'Cooling efficiency based on inlet/outlet temperature difference',
    '%',
    'expression',
    '{
        "expression": {
            "formula": "((TEMP_IN - TEMP_OUT) / TEMP_IN) * 100",
            "variables": {
                "TEMP_IN": {
                    "type": "sensor_tag",
                    "source": "influx_latest", 
                    "tag_name": "TT_COOLING_IN"
                },
                "TEMP_OUT": {
                    "type": "sensor_tag",
                    "source": "influx_latest",
                    "tag_name": "TT_COOLING_OUT"
                }
            }
        },
        "validation": {
            "min_value": 0,
            "max_value": 100
        }
    }'::jsonb
);

-- 예시 2: 시스템 부하율
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config)
VALUES (
    'SYSTEM_LOAD_PCT',
    'System Load Percentage',
    'Current system load as percentage of maximum',
    '%',
    'expression', 
    '{
        "expression": {
            "formula": "(CURRENT_LOAD / MAX_LOAD) * 100",
            "variables": {
                "CURRENT_LOAD": {
                    "type": "sensor_tag",
                    "source": "influx_latest",
                    "tag_name": "AT_CURRENT_LOAD"
                }
            },
            "constants": {
                "MAX_LOAD": 1000
            }
        },
        "validation": {
            "min_value": 0,
            "max_value": 120
        }
    }'::jsonb
);

-- 의존성 업데이트
SELECT update_virtual_tag_dependencies('COOLING_EFFICIENCY');
SELECT update_virtual_tag_dependencies('SYSTEM_LOAD_PCT');

-- 추가 완료 확인
SELECT 'New virtual tags added successfully!' as status;
SELECT virtual_tag_id, name, enabled FROM virtual_tags WHERE virtual_tag_id IN ('COOLING_EFFICIENCY', 'SYSTEM_LOAD_PCT');

-- 계산 테스트 (선택사항)
-- SELECT * FROM calculate_virtual_tag('COOLING_EFFICIENCY');
-- SELECT * FROM calculate_virtual_tag('SYSTEM_LOAD_PCT');