from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from loguru import logger

from app import models
from app import config_manager
from app.database import init_database, get_engine
from app.logger_config import setup_loguru
from app.routers import expenses, invoices, dashboard, client_logs, settings

# ── 1. 加载配置（config.json / 默认值）──
config = config_manager.load_config()

# ── 2. 初始化数据库引擎 ──
init_database(config["db_path"])

# ── 3. 初始化 Loguru 日志系统 ──
setup_loguru(config["log_path"])

# ── 4. 启动时建表 ──
models.Base.metadata.create_all(bind=get_engine())
logger.info("数据库表结构已确认/创建")

# ── 5. 初始化 FastAPI 应用 ──
app = FastAPI(title="发票管理系统 API", version="1.3.1")
logger.info("FastAPI 应用实例已创建")

# 本地桌面端无需跨域 —— CORS 中间件已移除

# 将访问者引流到可视化接口面板
@app.get("/", include_in_schema=False)
def redirect_to_docs():
    return RedirectResponse(url="/docs")

# 挂载业务路由
app.include_router(expenses.router)
app.include_router(invoices.router)
app.include_router(dashboard.router)
app.include_router(client_logs.router)
app.include_router(settings.router)
logger.info("业务路由已挂载：/api/expenses  /api/invoices  /api/dashboard  /api/client-logs  /api/settings")

if __name__ == "__main__":
    import socket
    import atexit
    import os
    from pathlib import Path as _Path

    # ── 端口自动扫描 ──
    def _find_available_port(start=18090, max_attempts=20) -> int:
        for offset in range(max_attempts):
            port = start + offset
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                try:
                    s.bind(('127.0.0.1', port))
                    return port
                except OSError:
                    continue
        raise RuntimeError(f"无法在 {start}–{start + max_attempts - 1} 范围内找到可用端口")

    port = _find_available_port()

    # ── 写入 PID 和端口号（供前端清场/连接使用）──
    config_dir = config_manager._CONFIG_DIR  # config/ 目录
    config_dir.mkdir(parents=True, exist_ok=True)
    pid_file = config_dir / "backend.pid"
    port_file = config_dir / "port.txt"

    pid_file.write_text(str(os.getpid()))
    port_file.write_text(str(port))

    # 正常退出时自动清理 PID 文件（port.txt 保留供清场参考）
    @atexit.register
    def _cleanup():
        pid_file.unlink(missing_ok=True)

    logger.info("API 服务启动中 — 监听 127.0.0.1:{}", port)
    from uvicorn import run
    run(app, host="127.0.0.1", port=port)
