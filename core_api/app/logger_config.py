"""
Loguru 集中配置模块 — 前后端大一统日志系统的后端基建。

特性：
- enqueue=True 异步写入，主线程不被磁盘 I/O 阻塞
- 按 100 MB 轮转，保留 30 天，历史日志自动 zip 压缩
- 劫持 FastAPI / Uvicorn 标准 logging 输出，统一交给 Loguru 处理
"""
import logging
from pathlib import Path
from loguru import logger

# 日志目录与文件
LOG_DIR = Path(__file__).resolve().parent.parent / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / "app.log"


class _InterceptHandler(logging.Handler):
    """将标准 logging 日志重定向到 Loguru — 统一格式与输出目标"""

    def emit(self, record: logging.LogRecord) -> None:
        # 获取对应的 Loguru 级别名称
        try:
            level = logger.level(record.levelname).name
        except ValueError:
            level = record.levelno

        # 向上追溯调用栈，找到真实的调用者（跳过标准库帧）
        frame, depth = logging.currentframe(), 2
        while frame and frame.f_code.co_filename == logging.__file__:
            frame = frame.f_back
            depth += 1

        logger.opt(depth=depth, exception=record.exc_info).log(
            level, record.getMessage()
        )


def setup_loguru() -> None:
    """初始化 Loguru — 应在 main.py 启动早期调用，替换 logging.basicConfig"""

    # 1. 移除 Loguru 默认的 stderr 输出
    logger.remove()

    # 2. 添加文件输出（异步 + 轮转 + 压缩 + 保留）
    logger.add(
        str(LOG_FILE),
        level="INFO",
        format=(
            "{time:YYYY-MM-DD HH:mm:ss.SSS} "
            "[{level}] "
            "{name} - "
            "{message}"
        ),
        rotation="100 MB",
        retention="30 days",
        compression="zip",
        enqueue=True,
        encoding="utf-8",
    )

    # 3. 劫持标准 logging → Loguru（覆盖 FastAPI / Uvicorn 内部日志）
    logging.basicConfig(handlers=[_InterceptHandler()], level=0, force=True)

    # 显式接管 uvicorn 的专用 logger
    for _name in ("uvicorn", "uvicorn.access", "uvicorn.error", "fastapi"):
        _lg = logging.getLogger(_name)
        _lg.handlers = [_InterceptHandler()]
        _lg.propagate = False

    logger.info("Loguru 日志系统初始化完成 | 输出文件: {}", LOG_FILE)
