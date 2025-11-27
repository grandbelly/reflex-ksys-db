from __future__ import annotations

import os
import sys
import asyncio
import logging
import asyncpg
from typing import Any
from ksys_app.utils.logger import get_logger, log_function

# Initialize logger for this module
logger = get_logger(__name__)

# Windows에서 ProactorEventLoop 문제 해결 (로컬 개발 환경에서만)
# Docker 환경에서는 Linux이므로 이 설정이 필요 없음
if sys.platform == 'win32' and not os.environ.get('DOCKER_CONTAINER'):
    logger.info("Setting WindowsSelectorEventLoopPolicy for Windows environment")
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
else:
    logger.info(f"Running on platform: {sys.platform}, Docker: {os.environ.get('DOCKER_CONTAINER', 'False')}")


@log_function
def _dsn() -> str:
    dsn = os.environ.get("TS_DSN", "")
    if not dsn:
        logger.error("TS_DSN is not set in environment")
        raise RuntimeError("TS_DSN is not set in environment")
    logger.debug(f"DSN retrieved: {dsn[:30]}...")  # Log only first 30 chars for security
    return dsn


# 글로벌 풀 변수
_GLOBAL_POOL: asyncpg.Pool | None = None
_POOL_LOCK = asyncio.Lock()


@log_function
async def get_pool() -> asyncpg.Pool:
    """글로벌 싱글톤 풀 관리"""
    global _GLOBAL_POOL

    if _GLOBAL_POOL is None:
        async with _POOL_LOCK:
            # 다시 확인 (double-check)
            if _GLOBAL_POOL is None:
                pid = os.getpid()
                logger.info(f"Creating global pool for first access in process {pid}")
                try:
                    _GLOBAL_POOL = await asyncpg.create_pool(
                        _dsn(),
                        min_size=1,  # 최소 연결 수
                        max_size=10,  # 최대 연결 수
                        timeout=30.0,  # 연결 대기 시간
                        command_timeout=30.0,  # 명령 타임아웃
                    )
                    logger.info(f"Global pool created successfully (PID: {pid})")
                except Exception as e:
                    logger.error(f"Failed to create global pool: {str(e)}")
                    _GLOBAL_POOL = None
                    raise

    return _GLOBAL_POOL


@log_function
async def q(sql: str, params: tuple | dict = (), timeout: float = 30.0):
    """쿼리 실행 - 글로벌 풀 사용"""
    start_time = asyncio.get_event_loop().time()

    try:
        pool = await get_pool()

        # asyncpg는 named parameters ($1, $2)만 지원하므로 변환
        if isinstance(params, dict):
            # Convert named parameters to positional
            # For now, use positional parameters only
            params = tuple(params.values()) if params else ()
        
        # 풀에서 연결 가져오기 및 쿼리 실행
        async with pool.acquire() as conn:
            # asyncpg는 fetch() 메서드로 결과를 dict 형태로 반환
            results = await conn.fetch(sql, *params, timeout=timeout)

            # Convert asyncpg.Record to dict
            results = [dict(row) for row in results]

            # Log only if query took > 1 second
            elapsed = asyncio.get_event_loop().time() - start_time
            if elapsed > 1.0:
                logger.warning(f"Slow query ({elapsed:.2f}s): {sql[:100]}...")
            elif logger.isEnabledFor(logging.DEBUG):
                logger.debug(f"Query completed in {elapsed:.3f}s, returned {len(results)} rows")

            return results

    except asyncio.TimeoutError as e:
        # 타임아웃 시 직접 연결 사용
        logger.warning(f"Pool timeout, using direct connection: {str(e)}")

        try:
            conn = await asyncpg.connect(_dsn())
            try:
                results = await conn.fetch(sql, *params, timeout=timeout)
                results = [dict(row) for row in results]

                elapsed = asyncio.get_event_loop().time() - start_time
                logger.info(f"Direct connection query completed in {elapsed:.3f}s")
                return results
            finally:
                await conn.close()

        except Exception as e2:
            logger.error(f"Direct connection also failed: {str(e2)}")
            raise

    except Exception as e:
        logger.error(f"Query execution failed: {str(e)}")
        logger.error(f"SQL: {sql}")
        logger.error(f"Params: {params}")
        raise


@log_function
async def execute_query(sql: str, params: tuple | dict = (), timeout: float = 30.0):
    """Execute SQL without expecting results (for INSERT, UPDATE, DELETE)"""
    start_time = asyncio.get_event_loop().time()

    try:
        pool = await get_pool()

        # asyncpg는 named parameters ($1, $2)만 지원하므로 변환
        if isinstance(params, dict):
            params = tuple(params.values()) if params else ()

        # 풀에서 연결 가져오기 및 쿼리 실행
        async with pool.acquire() as conn:
            await conn.execute(sql, *params, timeout=timeout)

            # Log only if query took > 1 second
            elapsed = asyncio.get_event_loop().time() - start_time
            if elapsed > 1.0:
                logger.warning(f"Slow execute ({elapsed:.2f}s): {sql[:100]}...")
            elif logger.isEnabledFor(logging.DEBUG):
                logger.debug(f"Execute completed in {elapsed:.3f}s")

    except asyncio.TimeoutError as e:
        # 타임아웃 시 직접 연결 사용
        logger.warning(f"Pool timeout, using direct connection for execute: {str(e)}")

        try:
            conn = await asyncpg.connect(_dsn())
            try:
                await conn.execute(sql, *params, timeout=timeout)

                elapsed = asyncio.get_event_loop().time() - start_time
                logger.info(f"Direct connection execute completed in {elapsed:.3f}s")
            finally:
                await conn.close()

        except Exception as e2:
            logger.error(f"Direct connection execute also failed: {str(e2)}")
            raise

    except Exception as e:
        logger.error(f"Execute query failed: {str(e)}")
        logger.error(f"SQL: {sql}")
        logger.error(f"Params: {params}")
        raise


async def close_pool():
    """풀 정리"""
    global _GLOBAL_POOL

    if _GLOBAL_POOL is not None:
        try:
            await _GLOBAL_POOL.close()
            _GLOBAL_POOL = None
            logger.info("Global pool closed successfully")
        except Exception as e:
            logger.error(f"Error closing pool: {e}")