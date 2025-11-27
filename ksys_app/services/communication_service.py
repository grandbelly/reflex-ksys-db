"""
Communication Service
- Handles communication statistics queries
- Returns data for heatmap and analytics
- FIXED: influx_agg_1m 기반으로 변경 (2025-11-26)
  - 예측 가능한 주기: 1분당 1레코드 = 시간당 60레코드
  - quality=0 집계만 포함 (avg_value)
"""
from typing import List, Dict
from datetime import datetime, timedelta
from sqlalchemy import text
from ksys_app.services.base_service import BaseService


class CommunicationService(BaseService):
    """Service for communication success rate monitoring"""

    async def get_available_tags(self) -> List[str]:
        """
        Get list of available sensor tags

        Returns:
            List of tag names
        """
        query = text("""
            SELECT DISTINCT tag_name
            FROM influx_latest
            ORDER BY tag_name
        """)

        rows = await self.execute_query(query, timeout="5s")
        return [row['tag_name'] for row in rows]

    async def get_hourly_stats(self, tag: str, days: int) -> List[Dict]:
        """
        Get hourly communication statistics using influx_agg_1m (KST timezone)

        Uses 1-minute aggregates for predictable counting:
        - Expected: 60 records per hour (1 per minute)
        - Actual: COUNT of 1-minute buckets with data

        Args:
            tag: Sensor tag name
            days: Number of days to look back

        Returns:
            List of hourly statistics with:
            - timestamp: Hour timestamp (KST)
            - record_count: Actual 1-minute records received
            - expected_count: Expected 60 records per hour
            - success_rate: Percentage (capped at 100%)
            - date: Date string (KST)
            - hour: Hour of day (KST)
        """
        query = text("""
            WITH hourly_data AS (
                SELECT
                    (date_trunc('hour', bucket AT TIME ZONE 'Asia/Seoul'))::timestamp as timestamp_kst,
                    COUNT(*) as record_count,
                    60 as expected_count  -- 1 record per minute = 60 per hour
                FROM influx_agg_1m
                WHERE (bucket AT TIME ZONE 'Asia/Seoul') >= (NOW() AT TIME ZONE 'Asia/Seoul') - :days * INTERVAL '1 day'
                  AND (bucket AT TIME ZONE 'Asia/Seoul') < (NOW() AT TIME ZONE 'Asia/Seoul')
                  AND tag_name = :tag
                GROUP BY date_trunc('hour', bucket AT TIME ZONE 'Asia/Seoul')
            )
            SELECT
                timestamp_kst as timestamp,
                record_count,
                expected_count,
                LEAST(
                    ROUND((record_count::NUMERIC / expected_count) * 100, 2),
                    100.0
                ) as success_rate,
                TO_CHAR(timestamp_kst, 'YYYY-MM-DD') as date,
                EXTRACT(hour FROM timestamp_kst) as hour
            FROM hourly_data
            ORDER BY timestamp_kst DESC
        """)

        return await self.execute_query(
            query,
            {"days": days, "tag": tag},
            timeout="15s"
        )

    async def get_daily_stats(self, days: int) -> List[Dict]:
        """
        Get daily statistics for all tags using influx_agg_1m (KST timezone)

        Uses 1-minute aggregates:
        - Expected: 1440 records per day (60 * 24)
        - Actual: COUNT of 1-minute buckets with data

        Args:
            days: Number of days to look back

        Returns:
            List of daily statistics with:
            - date: Date (KST)
            - tag_name: Sensor tag
            - daily_count: Records for the day
            - expected_daily_count: Expected 1440 records
            - success_rate: Percentage (capped at 100%)
        """
        query = text("""
            WITH daily_data AS (
                SELECT
                    (date_trunc('day', bucket AT TIME ZONE 'Asia/Seoul'))::date as date_kst,
                    tag_name,
                    COUNT(*) as daily_count,
                    1440 as expected_daily_count  -- 60 * 24 = 1440 per day
                FROM influx_agg_1m
                WHERE (bucket AT TIME ZONE 'Asia/Seoul') >= (NOW() AT TIME ZONE 'Asia/Seoul') - :days * INTERVAL '1 day'
                  AND (bucket AT TIME ZONE 'Asia/Seoul') < (NOW() AT TIME ZONE 'Asia/Seoul')
                GROUP BY date_trunc('day', bucket AT TIME ZONE 'Asia/Seoul'), tag_name
            )
            SELECT
                date_kst::text as date,
                tag_name,
                daily_count,
                expected_daily_count,
                LEAST(
                    ROUND((daily_count::NUMERIC / expected_daily_count) * 100, 2),
                    100.0
                )::float as success_rate
            FROM daily_data
            WHERE daily_count > 0
            ORDER BY date_kst DESC, tag_name
        """)

        rows = await self.execute_query(
            query,
            {"days": days},
            timeout="15s"
        )

        return [
            {
                "date": row["date"],
                "tag_name": row["tag_name"],
                "daily_count": int(row["daily_count"]),
                "expected_daily_count": int(row["expected_daily_count"]),
                "success_rate": float(row["success_rate"])
            }
            for row in rows
        ]

    async def get_tag_summary(self, tag: str, days: int) -> Dict:
        """
        Get summary statistics for a specific tag using influx_agg_1m (KST timezone)

        Args:
            tag: Sensor tag name
            days: Number of days to look back

        Returns:
            Dict with summary stats:
            - total_records: Total 1-minute records received
            - expected_records: Expected records (days * 1440)
            - success_rate: Overall success rate (capped at 100%)
            - active_hours: Number of hours with at least 1 record
        """
        days_int = int(days) if not isinstance(days, int) else days

        query = text("""
            WITH stats AS (
                SELECT
                    COUNT(*) as total_records,
                    COUNT(DISTINCT date_trunc('hour', bucket AT TIME ZONE 'Asia/Seoul')) as active_hours,
                    :days * 1440 as expected_records  -- days * 60 * 24
                FROM influx_agg_1m
                WHERE (bucket AT TIME ZONE 'Asia/Seoul') >= (NOW() AT TIME ZONE 'Asia/Seoul') - :days * INTERVAL '1 day'
                  AND (bucket AT TIME ZONE 'Asia/Seoul') < (NOW() AT TIME ZONE 'Asia/Seoul')
                  AND tag_name = :tag
            )
            SELECT
                total_records,
                GREATEST(expected_records, 1) as expected_records,
                active_hours,
                LEAST(
                    ROUND((total_records::NUMERIC / NULLIF(expected_records, 0)) * 100, 2),
                    100.0
                ) as success_rate
            FROM stats
        """)

        rows = await self.execute_query(
            query,
            {
                "tag": tag,
                "days": days_int
            },
            timeout="10s"
        )

        if rows:
            return rows[0]
        else:
            return {
                "total_records": 0,
                "expected_records": 0,
                "active_hours": 0,
                "success_rate": 0.0
            }
