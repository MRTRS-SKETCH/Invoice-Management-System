from sqlalchemy import create_engine, pool
from sqlalchemy.orm import declarative_base, sessionmaker
from pathlib import Path

# 获取项目根目录的绝对路径 (即 core_api 目录)
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)

# 拼接出数据库的绝对路径
DB_PATH = DATA_DIR / "invoice_system.db"
SQLALCHEMY_DATABASE_URL = f"sqlite:///{DB_PATH}"

# 创建数据库引擎 (增加了企业级连接池与超时防护机制)
engine = create_engine(
    SQLALCHEMY_DATABASE_URL, 
    connect_args={
        "check_same_thread": False, 
        "timeout": 15  # SQLite 原生锁等待超时(秒)，防止由于并发读写导致数据库被死锁
    },
    # 强制使用队列池，配合 FastAPI 的并发特性，防止幽灵连接
    poolclass=pool.QueuePool,
    pool_size=5,       # 维持的常规连接数
    max_overflow=10,   # 高峰期允许溢出的最多连接数
    pool_recycle=3600, # 一小时强制回收一次连接
    pool_timeout=30    # 获取连接时的最长等待时间
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal() # 【开门】前端一发来请求，立刻创建一个专属的数据库连接
    try:
        yield db        # 【干活】把这个连接“借给”你的 API 接口
    finally:
        db.close()      # 【关门】干完活后强制关闭连接，释放资源