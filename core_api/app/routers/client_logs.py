"""
前端日志批量上报接口 — 接收 Flutter 缓冲队列的日志，统一写入 Loguru app.log
"""
from typing import List
from fastapi import APIRouter, status
from loguru import logger

from app import schemas

router = APIRouter(
    prefix="/api/client-logs",
    tags=["前端日志上报 (Client Logs)"],
)


@router.post("/batch", status_code=status.HTTP_200_OK)
async def receive_client_logs(entries: List[schemas.ClientLogEntry]):
    """接收前端批量日志，附 [Flutter] 前缀写入统一日志文件"""
    for entry in entries:
        msg = f"[Flutter] {entry.message}"
        level = entry.level.upper()

        if level == "ERROR":
            logger.error(msg)
        elif level == "WARNING":
            logger.warning(msg)
        else:
            logger.info(msg)

    return {"status": "ok", "count": len(entries)}
