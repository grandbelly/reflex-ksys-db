-- =====================================================
-- Virtual Tags System Initialization
-- 최초 설치 시 실행하는 DDL 스크립트
-- =====================================================

-- 기존 테이블이 있으면 삭제 (개발 환경용)
DROP TABLE IF EXISTS virtual_tag_values CASCADE;
DROP TABLE IF EXISTS virtual_tag_dependencies CASCADE;
DROP TABLE IF EXISTS virtual_tags CASCADE;

-- 1. Virtual Tag 설정 테이블
CREATE TABLE virtual_tags (
    id SERIAL PRIMARY KEY,
    virtual_tag_id VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    unit VARCHAR(20),
    calculation_type VARCHAR(50) NOT NULL CHECK (calculation_type IN ('expression', 'statistical', 'conditional')),
    config JSONB NOT NULL,
    update_frequency INTERVAL DEFAULT '10 seconds',
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 인덱스 생성
CREATE INDEX idx_virtual_tags_enabled ON virtual_tags(enabled);
CREATE INDEX idx_virtual_tags_type ON virtual_tags(calculation_type);
CREATE INDEX idx_virtual_tags_config ON virtual_tags USING gin(config);
CREATE INDEX idx_virtual_tags_update_freq ON virtual_tags(update_frequency) WHERE enabled = true;

-- 2. Virtual Tag 값 저장 테이블 (Hypertable)
CREATE TABLE virtual_tag_values (
    time TIMESTAMPTZ NOT NULL,
    virtual_tag_id VARCHAR(100) NOT NULL,
    value DOUBLE PRECISION,
    quality_code INTEGER DEFAULT 0, -- 0:Good, 1:Uncertain, 2:Bad, 3:Error
    calculation_time_ms INTEGER,
    error_message TEXT
);

-- TimescaleDB Hypertable 생성
SELECT create_hypertable('virtual_tag_values', 'time');

-- 인덱스 생성
CREATE INDEX idx_virtual_tag_values_tag_time ON virtual_tag_values(virtual_tag_id, time DESC);
CREATE INDEX idx_virtual_tag_values_quality ON virtual_tag_values(quality_code, time DESC);

-- 3. Virtual Tag 의존성 관리 테이블
CREATE TABLE virtual_tag_dependencies (
    id SERIAL PRIMARY KEY,
    virtual_tag_id VARCHAR(100) NOT NULL,
    source_tag_name VARCHAR(100) NOT NULL,
    dependency_type VARCHAR(50) DEFAULT 'direct',
    CONSTRAINT fk_virtual_tag FOREIGN KEY (virtual_tag_id) REFERENCES virtual_tags(virtual_tag_id) ON DELETE CASCADE
);

-- 인덱스 생성
CREATE INDEX idx_dependencies_virtual_tag ON virtual_tag_dependencies(virtual_tag_id);
CREATE INDEX idx_dependencies_source ON virtual_tag_dependencies(source_tag_name);
CREATE UNIQUE INDEX idx_dependencies_unique ON virtual_tag_dependencies(virtual_tag_id, source_tag_name);

-- 4. Virtual Tag 최신 값 Materialized View
CREATE MATERIALIZED VIEW virtual_tag_latest AS
SELECT DISTINCT ON (virtual_tag_id) 
    virtual_tag_id, 
    time, 
    value, 
    quality_code,
    error_message
FROM virtual_tag_values 
ORDER BY virtual_tag_id, time DESC;

-- Materialized View 인덱스
CREATE UNIQUE INDEX idx_virtual_tag_latest_id ON virtual_tag_latest(virtual_tag_id);
CREATE INDEX idx_virtual_tag_latest_time ON virtual_tag_latest(time DESC);

-- 5. Virtual Tag 설정 업데이트 트리거
CREATE OR REPLACE FUNCTION update_virtual_tag_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_virtual_tag_update
    BEFORE UPDATE ON virtual_tags
    FOR EACH ROW EXECUTE FUNCTION update_virtual_tag_timestamp();

-- 6. 권한 설정 (읽기 전용 사용자용)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ecoanp_user') THEN
        GRANT SELECT ON virtual_tags TO ecoanp_user;
        GRANT SELECT ON virtual_tag_values TO ecoanp_user;
        GRANT SELECT ON virtual_tag_dependencies TO ecoanp_user;
        GRANT SELECT ON virtual_tag_latest TO ecoanp_user;
    END IF;
END $$;

-- 초기화 완료 메시지
SELECT 'Virtual Tags System initialized successfully!' as status;
SELECT 'Tables created: virtual_tags, virtual_tag_values, virtual_tag_dependencies, virtual_tag_latest' as info;