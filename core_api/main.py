import logging
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse

# 使用绝对路径从 app 包中导入所需模块
from app.database import engine
from app import models
from app.routers import expenses, invoices, dashboard

# ── 日志配置（按年月命名，仅输出到文件，不输出到控制台）──
LOG_DIR = Path(__file__).resolve().parent / "user_data"
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOG_DIR / f"{__import__('datetime').datetime.now().strftime('%Y-%m')}.log"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
    ],
)
logger = logging.getLogger("core_api")

# 启动时建表
models.Base.metadata.create_all(bind=engine)
logger.info("数据库表结构已确认/创建")

# 初始化总应用
app = FastAPI(title="对公报销与发票管理系统 API", version="1.0.0")
logger.info("FastAPI 应用实例已创建")

# ── CORS 中间件 ──
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 将访问者引流到可视化接口面板
@app.get("/", include_in_schema=False)
def redirect_to_docs():
    return RedirectResponse(url="/docs")

# 挂载业务路由
app.include_router(expenses.router)
app.include_router(invoices.router)
app.include_router(dashboard.router)
logger.info("业务路由已挂载：/api/expenses  /api/invoices  /api/dashboard")

if __name__ == "__main__":
    # 作为唯一的启动入口
    logger.info("API 服务启动中 — 监听 127.0.0.1:8000")
    from uvicorn import run
    run(app, host="127.0.0.1", port=8000)
