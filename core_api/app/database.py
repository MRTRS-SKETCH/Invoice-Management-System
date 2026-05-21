import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# 1. 获取项目根目录的绝对路径 (即 core_api 目录)
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 2. 定义 data 文件夹路径并确保它存在
DATA_DIR = os.path.join(BASE_DIR, "data")
os.makedirs(DATA_DIR, exist_ok=True) # 如果没有 data 文件夹，自动创建

# 3. 将数据库文件拼接到 data 目录下
DB_PATH = os.path.join(DATA_DIR, "invoice_system.db")
SQLALCHEMY_DATABASE_URL = f"sqlite:///{DB_PATH}"

# 创建数据库引擎
engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()