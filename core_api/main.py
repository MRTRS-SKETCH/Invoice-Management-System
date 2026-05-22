from fastapi import FastAPI
from fastapi.responses import RedirectResponse

# 使用绝对路径从 app 包中导入所需模块
from app.database import engine
from app import models
from app.routers import expenses, invoices

# 启动时建表
models.Base.metadata.create_all(bind=engine)

# 初始化总应用
app = FastAPI(title="对公报销与发票管理系统 API", version="1.0.0")

# 将访问者引流到可视化接口面板
@app.get("/", include_in_schema=False)
def redirect_to_docs():
    return RedirectResponse(url="/docs")

# 挂载业务路由
app.include_router(expenses.router)
app.include_router(invoices.router)

if __name__ == "__main__":
    # 作为唯一的启动入口
    from uvicorn import run
    run(app, host="127.0.0.1", port=8000)
