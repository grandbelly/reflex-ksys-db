-- ============================================================================
-- Phase 0: Database Schema Setup for Online Forecasting
-- Created: 2025-10-14 16:40 KST
-- Purpose: Separate offline training evaluation from online predictions
-- Reference: docs/forecast_result/ONLINE_FORECAST_REDESIGN_20251014.md
-- ============================================================================

-- Step 1: Create training_evaluation table for offline backtest results
-- ============================================================================
CREATE TABLE IF NOT EXISTS training_evaluation (
    evaluation_id BIGSERIAL PRIMARY KEY,
    model_id INTEGER NOT NULL REFERENCES model_registry(model_id) ON DELETE CASCADE,

    -- Timestamps
    evaluation_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- When model was trained
    target_time TIMESTAMPTZ NOT NULL,                    -- Test set timestamp (PAST)

    -- Prediction values
    predicted_value NUMERIC(15, 4) NOT NULL,
    actual_value NUMERIC(15, 4) NOT NULL,               -- Known from test set

    -- Error metrics
    prediction_error NUMERIC(15, 4),                     -- (predicted - actual)
    absolute_percentage_error NUMERIC(10, 4),            -- |error| / |actual| * 100

    -- Metadata
    horizon_minutes INTEGER,                             -- Forecast horizon (e.g., 60, 120, 360)
    model_type VARCHAR(50),                              -- PROPHET, ARIMA, XGBOOST
    sensor_tag VARCHAR(100),                             -- Sensor tag name

    -- Indexes for common queries
    CONSTRAINT unique_evaluation UNIQUE (model_id, target_time, horizon_minutes)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_training_eval_model ON training_evaluation(model_id);
CREATE INDEX IF NOT EXISTS idx_training_eval_time ON training_evaluation(target_time DESC);
CREATE INDEX IF NOT EXISTS idx_training_eval_sensor ON training_evaluation(sensor_tag);
CREATE INDEX IF NOT EXISTS idx_training_eval_combo ON training_evaluation(model_id, target_time);

-- Add table comment
COMMENT ON TABLE training_evaluation IS
'Stores OFFLINE backtest results from Training Wizard.
Contains historical test set predictions with known actual values.
Used for: Algorithm comparison, model validation, historical performance analysis.
NOT for online real-time predictions (use predictions table instead).';

-- Column comments
COMMENT ON COLUMN training_evaluation.evaluation_time IS 'When the model was trained and evaluated';
COMMENT ON COLUMN training_evaluation.target_time IS 'Timestamp from test set (always in the PAST)';
COMMENT ON COLUMN training_evaluation.predicted_value IS 'Model prediction on test set';
COMMENT ON COLUMN training_evaluation.actual_value IS 'Known actual value from test set';
COMMENT ON COLUMN training_evaluation.prediction_error IS 'Signed error: predicted - actual';
COMMENT ON COLUMN training_evaluation.absolute_percentage_error IS 'MAPE component: |error| / |actual| * 100';

-- ============================================================================
-- Step 2: Migrate existing predictions table data to training_evaluation
-- ============================================================================

-- Check if predictions table has data that looks like training data
-- (actual_value is NOT NULL and target_time is in the PAST)
DO $$
DECLARE
    record_count INTEGER;
BEGIN
    -- Count records that look like training data
    SELECT COUNT(*) INTO record_count
    FROM predictions
    WHERE actual_value IS NOT NULL
      AND target_time < NOW();

    IF record_count > 0 THEN
        RAISE NOTICE 'Found % records to migrate from predictions to training_evaluation', record_count;

        -- Migrate data
        INSERT INTO training_evaluation (
            model_id,
            evaluation_time,
            target_time,
            predicted_value,
            actual_value,
            prediction_error,
            absolute_percentage_error,
            horizon_minutes,
            model_type,
            sensor_tag
        )
        SELECT
            p.model_id,
            p.forecast_time AS evaluation_time,
            p.target_time,
            p.predicted_value,
            p.actual_value,
            p.prediction_error,
            p.absolute_percentage_error,
            p.horizon_minutes,
            mr.model_type,
            mr.sensor_tag
        FROM predictions p
        JOIN model_registry mr ON p.model_id = mr.model_id
        WHERE p.actual_value IS NOT NULL
          AND p.target_time < NOW()
        ON CONFLICT (model_id, target_time, horizon_minutes) DO NOTHING;

        RAISE NOTICE 'Migration completed. Migrated % records.', record_count;

        -- OPTIONAL: Clean up migrated records from predictions
        -- Uncomment the following lines to delete migrated records
        -- DELETE FROM predictions
        -- WHERE actual_value IS NOT NULL
        --   AND target_time < NOW();
        -- RAISE NOTICE 'Cleaned up predictions table.';
    ELSE
        RAISE NOTICE 'No training data found in predictions table to migrate.';
    END IF;
END $$;

-- ============================================================================
-- Step 3: Create helper views for common queries
-- ============================================================================

-- View: Latest evaluation metrics per model
CREATE OR REPLACE VIEW v_latest_evaluation_metrics AS
SELECT
    model_id,
    sensor_tag,
    model_type,
    COUNT(*) AS evaluation_count,
    AVG(absolute_percentage_error) AS avg_mape,
    AVG(ABS(prediction_error)) AS avg_mae,
    SQRT(AVG(prediction_error ^ 2)) AS rmse,
    MAX(evaluation_time) AS last_evaluated,
    MIN(target_time) AS eval_period_start,
    MAX(target_time) AS eval_period_end
FROM training_evaluation
GROUP BY model_id, sensor_tag, model_type;

COMMENT ON VIEW v_latest_evaluation_metrics IS
'Aggregated evaluation metrics per model from training/backtest results.
Used for: Model Performance page algorithm comparison.';

-- View: Evaluation time series for charting
CREATE OR REPLACE VIEW v_evaluation_timeseries AS
SELECT
    te.evaluation_id,
    te.model_id,
    te.target_time,
    te.predicted_value,
    te.actual_value,
    te.prediction_error,
    te.absolute_percentage_error,
    mr.sensor_tag,
    mr.model_type,
    mr.version
FROM training_evaluation te
JOIN model_registry mr ON te.model_id = mr.model_id
ORDER BY te.model_id, te.target_time;

COMMENT ON VIEW v_evaluation_timeseries IS
'Time series of evaluation results for charting predicted vs actual.
Used for: Training Wizard results page validation charts.';

-- ============================================================================
-- Step 4: Clean up predictions table (KEEP ONLY online predictions)
-- ============================================================================

-- Add constraint to ensure predictions table only has future predictions
-- (This will be enforced after schedulers are implemented)
/*
ALTER TABLE predictions DROP CONSTRAINT IF EXISTS chk_predictions_future_only;
ALTER TABLE predictions ADD CONSTRAINT chk_predictions_future_only
    CHECK (target_time > forecast_time);

COMMENT ON CONSTRAINT chk_predictions_future_only ON predictions IS
'Ensures predictions table only contains online predictions where target_time is in the FUTURE.
Offline training data should go to training_evaluation table.';
*/

-- For now, just add a comment to the table
COMMENT ON TABLE predictions IS
'Stores ONLINE real-time predictions generated by ForecastScheduler.
CRITICAL: This table should ONLY contain predictions where target_time > forecast_time (future predictions).
Offline training/backtest data belongs in training_evaluation table.
Generated by: ForecastScheduler (every 5 minutes).
Updated by: ActualValueUpdater (every 10 minutes, fills actual_value when target_time arrives).';

-- ============================================================================
-- Step 5: Update prediction_performance table comment
-- ============================================================================

COMMENT ON TABLE prediction_performance IS
'Aggregated accuracy metrics for online predictions (from predictions table).
Generated by: PerformanceAggregator (every 1 hour).
Compares online predictions against actual values after target_time has passed.
NOT for training evaluation (use v_latest_evaluation_metrics view instead).';

-- ============================================================================
-- Verification Queries
-- ============================================================================

-- Query 1: Check training_evaluation table
-- SELECT COUNT(*), MIN(target_time), MAX(target_time) FROM training_evaluation;

-- Query 2: Check predictions table (should be empty or have only future predictions)
-- SELECT COUNT(*), MIN(target_time), MAX(target_time) FROM predictions;

-- Query 3: View evaluation metrics
-- SELECT * FROM v_latest_evaluation_metrics ORDER BY sensor_tag;

-- Query 4: Count records in each table
-- SELECT
--     'predictions' AS table_name, COUNT(*) AS record_count FROM predictions
-- UNION ALL
-- SELECT
--     'training_evaluation', COUNT(*) FROM training_evaluation
-- UNION ALL
-- SELECT
--     'prediction_performance', COUNT(*) FROM prediction_performance;

-- ============================================================================
-- Rollback Script (if needed)
-- ============================================================================

-- DROP VIEW IF EXISTS v_evaluation_timeseries;
-- DROP VIEW IF EXISTS v_latest_evaluation_metrics;
-- DROP TABLE IF EXISTS training_evaluation CASCADE;

-- ============================================================================
-- End of Migration
-- ============================================================================

-- Print completion message
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Migration completed successfully!';
    RAISE NOTICE 'Created: training_evaluation table';
    RAISE NOTICE 'Created: v_latest_evaluation_metrics view';
    RAISE NOTICE 'Created: v_evaluation_timeseries view';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '1. Update Training Wizard to save to training_evaluation';
    RAISE NOTICE '2. Implement ForecastScheduler for online predictions';
    RAISE NOTICE '3. Implement ActualValueUpdater for accuracy tracking';
    RAISE NOTICE '========================================';
END $$;
