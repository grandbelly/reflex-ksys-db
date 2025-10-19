-- =========================================================================
-- Forecast Player Cache Table
-- =========================================================================
-- Purpose: Pre-calculated Rolling Window snapshots for ultra-fast UI queries
-- Updated by: ForecastScheduler every 10 minutes
-- Read by: Forecast Player UI (single SELECT, <50ms response)
-- =========================================================================

CREATE TABLE IF NOT EXISTS forecast_player_cache (
    cache_id SERIAL PRIMARY KEY,

    -- Model identification
    model_id INT NOT NULL,
    tag_name VARCHAR(100) NOT NULL,

    -- Snapshot timing
    forecast_time TIMESTAMPTZ NOT NULL,      -- When predictions were generated
    reference_time TIMESTAMPTZ NOT NULL,     -- T0 moment (latest actual data timestamp)
    created_at TIMESTAMPTZ DEFAULT NOW(),    -- When cache entry was created

    -- Rolling Window data (Past 30 + Present 1 + Future N points)
    -- Structure: [{"time_label": "T-30", "timestamp": "...", "actual_value": 123.45,
    --             "predicted_value": null, "ci_lower": null, "ci_upper": null,
    --             "zone": "past", "horizon_minutes": null}, ...]
    rolling_window JSONB NOT NULL,

    -- Predictions table data (for table display, typically 7 rows)
    -- Structure: [{"target_time_display": "19:50", "horizon_hours": "1.0",
    --             "predicted_value": 123.45, "actual_value": null, "has_actual": false,
    --             "prediction_error": null, "ci_lower": 120.0, "ci_upper": 126.0}, ...]
    predictions_data JSONB NOT NULL,

    -- Pre-calculated metrics
    mape NUMERIC(10,2),              -- Mean Absolute Percentage Error
    rmse NUMERIC(10,2),              -- Root Mean Squared Error
    mae NUMERIC(10,2),               -- Mean Absolute Error
    accuracy NUMERIC(10,2),          -- 100 - MAPE

    -- Countdown information
    next_forecast_at TIMESTAMPTZ,    -- When next forecast will be generated

    -- Latest sensor value
    latest_value NUMERIC(10,2),

    -- Prevent duplicate cache entries
    UNIQUE(model_id, forecast_time)
);

-- Index for fast latest cache retrieval
CREATE INDEX idx_fpc_model_latest ON forecast_player_cache(model_id, forecast_time DESC);

-- Index for cleanup queries (delete old cache entries)
CREATE INDEX idx_fpc_created_at ON forecast_player_cache(created_at);

-- Comments
COMMENT ON TABLE forecast_player_cache IS 'Pre-computed Rolling Window snapshots for Forecast Player UI - eliminates complex JOIN queries';
COMMENT ON COLUMN forecast_player_cache.rolling_window IS 'Complete Rolling Window data (Past + Present + Future) as JSONB array';
COMMENT ON COLUMN forecast_player_cache.predictions_data IS 'Formatted predictions for table display (7 rows typically)';
COMMENT ON COLUMN forecast_player_cache.next_forecast_at IS 'Timestamp of next scheduled forecast generation (for countdown timer)';

-- Cleanup function: Delete cache entries older than 7 days
CREATE OR REPLACE FUNCTION cleanup_forecast_player_cache()
RETURNS void AS $$
BEGIN
    DELETE FROM forecast_player_cache
    WHERE created_at < NOW() - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql;

-- Optional: Schedule automatic cleanup (requires pg_cron)
-- SELECT cron.schedule('cleanup-forecast-cache', '0 2 * * *', $$SELECT cleanup_forecast_player_cache()$$);
