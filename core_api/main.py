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
app = FastAPI(title="发票管理系统 API", version="1.2.1")
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
    logger.info("API 服务启动中 — 监听 127.0.0.1:18090")
    from uvicorn import run
    run(app, host="127.0.0.1", port=18090)
