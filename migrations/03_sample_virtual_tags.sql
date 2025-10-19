-- =====================================================
-- Sample Virtual Tags Definitions
-- 실제 사용 예시 및 샘플 Virtual Tag들
-- =====================================================

-- 1. 수식 기반 Virtual Tag - 열교환기 효율성 계산
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config, update_frequency)
VALUES (
    'HEAT_EXCHANGER_EFF_01',
    'Heat Exchanger Efficiency #1',
    'Thermal efficiency calculation based on inlet/outlet temperatures',
    '%',
    'expression',
    '{
        "expression": {
            "formula": "((TEMP_IN - TEMP_OUT) / (TEMP_IN - TEMP_AMBIENT)) * 100",
            "variables": {
                "TEMP_IN": {
                    "type": "sensor_tag",
                    "source": "influx_latest",
                    "tag_name": "TT_HX01_IN"
                },
                "TEMP_OUT": {
                    "type": "sensor_tag",
                    "source": "influx_latest", 
                    "tag_name": "TT_HX01_OUT"
                },
                "TEMP_AMBIENT": {
                    "type": "sensor_tag",
                    "source": "influx_latest",
                    "tag_name": "TT_AMBIENT"
                }
            }
        },
        "validation": {
            "min_value": 0,
            "max_value": 100
        }
    }'::jsonb,
    '30 seconds'::interval
);

-- 2. 수식 기반 Virtual Tag - 압력 차이 계산
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config)
VALUES (
    'PRESSURE_DIFF_01',
    'Pressure Differential #1',
    'Pressure difference between inlet and outlet',
    'bar',
    'expression',
    '{
        "expression": {
            "formula": "PRESSURE_IN - PRESSURE_OUT",
            "variables": {
                "PRESSURE_IN": {
                    "type": "sensor_tag",
                    "source": "influx_latest",
                    "tag_name": "PT_INLET_01"
                },
                "PRESSURE_OUT": {
                    "type": "sensor_tag",
                    "source": "influx_latest",
                    "tag_name": "PT_OUTLET_01"
                }
            }
        },
        "validation": {
            "min_value": -10,
            "max_value": 10
        }
    }'::jsonb
);

-- 3. 통계 기반 Virtual Tag - 온도 평균값
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config)
VALUES (
    'TEMP_AVG_REACTOR',
    'Reactor Temperature Average',
    'Average temperature across all reactor sensors',
    '°C',
    'statistical',
    '{
        "statistical": {
            "function": "avg",
            "window": "5 minutes",
            "input_tags": ["TT_REACTOR_01", "TT_REACTOR_02", "TT_REACTOR_03", "TT_REACTOR_04"]
        }
    }'::jsonb
);

-- 4. 통계 기반 Virtual Tag - 유량 합계
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config)
VALUES (
    'FLOW_TOTAL_SYSTEM',
    'Total System Flow Rate',
    'Sum of all flow rates in the system',
    'm³/h',
    'statistical',
    '{
        "statistical": {
            "function": "sum",
            "window": "1 minute", 
            "input_tags": ["FT_PUMP_01", "FT_PUMP_02", "FT_PUMP_03"]
        }
    }'::jsonb
);

-- 5. 조건부 로직 Virtual Tag - 온도 알람 레벨
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config)
VALUES (
    'TEMP_ALARM_LEVEL',
    'Temperature Alarm Level',
    'Temperature alarm level based on reactor temperature',
    'level',
    'conditional',
    '{
        "conditional": {
            "input_tag": "TT_REACTOR_01",
            "conditions": [
                {
                    "condition": "value > 85",
                    "result": 3,
                    "description": "Critical High"
                },
                {
                    "condition": "value > 70",
                    "result": 2,
                    "description": "Warning High"
                },
                {
                    "condition": "value > 50",
                    "result": 1,
                    "description": "Normal High"
                }
            ],
            "default_result": 0,
            "default_description": "Normal"
        }
    }'::jsonb
);

-- 6. 조건부 로직 Virtual Tag - 압력 상태
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config)
VALUES (
    'PRESSURE_STATUS',
    'System Pressure Status',
    'Overall pressure system status',
    'status',
    'conditional',
    '{
        "conditional": {
            "input_tag": "PT_SYSTEM_MAIN",
            "conditions": [
                {
                    "condition": "value > 8.5",
                    "result": 2,
                    "description": "High Pressure"
                },
                {
                    "condition": "value < 2.0",
                    "result": 2,
                    "description": "Low Pressure"
                },
                {
                    "condition": "value >= 6.0",
                    "result": 1,
                    "description": "Normal High"
                },
                {
                    "condition": "value >= 3.0",
                    "result": 0,
                    "description": "Normal"
                }
            ],
            "default_result": 1,
            "default_description": "Normal Low"
        }
    }'::jsonb
);

-- 7. 복합 수식 Virtual Tag - 에너지 효율성
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config)
VALUES (
    'ENERGY_EFFICIENCY',
    'System Energy Efficiency',
    'Overall energy efficiency calculation',
    '%',
    'expression',
    '{
        "expression": {
            "formula": "((POWER_OUT / POWER_IN) * EFFICIENCY_FACTOR) * 100",
            "variables": {
                "POWER_OUT": {
                    "type": "sensor_tag",
                    "source": "influx_latest",
                    "tag_name": "WT_OUTPUT_POWER"
                },
                "POWER_IN": {
                    "type": "sensor_tag",
                    "source": "influx_latest",
                    "tag_name": "WT_INPUT_POWER"
                }
            },
            "constants": {
                "EFFICIENCY_FACTOR": 0.95
            }
        },
        "validation": {
            "min_value": 0,
            "max_value": 100
        }
    }'::jsonb
);

-- 8. 통계 기반 Virtual Tag - 표준편차
INSERT INTO virtual_tags (virtual_tag_id, name, description, unit, calculation_type, config)
VALUES (
    'TEMP_STDDEV_SYSTEM',
    'Temperature Standard Deviation',
    'Temperature variation across system sensors',
    '°C',
    'statistical',
    '{
        "statistical": {
            "function": "stddev",
            "window": "10 minutes",
            "input_tags": ["TT_REACTOR_01", "TT_REACTOR_02", "TT_REACTOR_03", "TT_HX01_IN", "TT_HX01_OUT"]
        }
    }'::jsonb
);

-- Virtual Tag 의존성 자동 업데이트
SELECT update_virtual_tag_dependencies('HEAT_EXCHANGER_EFF_01');
SELECT update_virtual_tag_dependencies('PRESSURE_DIFF_01');
SELECT update_virtual_tag_dependencies('TEMP_AVG_REACTOR');
SELECT update_virtual_tag_dependencies('FLOW_TOTAL_SYSTEM');
SELECT update_virtual_tag_dependencies('TEMP_ALARM_LEVEL');
SELECT update_virtual_tag_dependencies('PRESSURE_STATUS');
SELECT update_virtual_tag_dependencies('ENERGY_EFFICIENCY');
SELECT update_virtual_tag_dependencies('TEMP_STDDEV_SYSTEM');

-- 샘플 데이터 입력 완료 메시지
SELECT 'Sample Virtual Tags created successfully!' as status;
SELECT COUNT(*) || ' virtual tags created' as count FROM virtual_tags;
SELECT COUNT(*) || ' dependencies created' as dependencies FROM virtual_tag_dependencies;