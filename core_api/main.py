from fastapi import FastAPI
from database import init_db, generate_uid
import uvicorn

# 1. 启动时执行数据库初始化
# 这样可以确保每次启动 FastAPI 时，表结构都已经准备就绪
init_db()

# 2. 实例化 FastAPI 应用
app = FastAPI(
    title="财务与发票管理系统 API",
    description="为 Flutter 桌面端提供本地数据和文件流转支持的 Python 侧车服务",
    version="1.0.0"
)

# 3. 编写最简单的启动测试接口
@app.get("/")
def read_root():
    return {
        "status": "success",
        "message": "后端引擎已启动！FastAPI 正在为您服务。"
    }

# 4. 编写一个获取新 UID 的测试接口，验证我们的策略
@app.get("/api/test/generate-uid")
def test_uid():
    new_uid = generate_uid()
    return {
        "status": "success",
        "generated_uid": new_uid
    }

if __name__ == "__main__":
    # 保持进程常驻，监听本地 8000 端口
    uvicorn.run(app, host="127.0.0.1", port=8000)