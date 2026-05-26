from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from loguru import logger

from app.database import engine
from app import models
from app.logger_config import setup_loguru
from app.routers import expenses, invoices, dashboard, client_logs

# ── 初始化 Loguru 日志系统（替代原生 logging）──
setup_loguru()

# 启动时建表
models.Base.metadata.create_all(bind=engine)
logger.info("数据库表结构已确认/创建")

# 初始化总应用
app = FastAPI(title="对公报销与发票管理系统 API", version="1.0.0")
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
logger.info("业务路由已挂载：/api/expenses  /api/invoices  /api/dashboard  /api/client-logs")

if __name__ == "__main__":
    logger.info("API 服务启动中 — 监听 127.0.0.1:18090")
    from uvicorn import run
    run(app, host="127.0.0.1", port=18090)
