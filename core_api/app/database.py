"""
数据库引擎模块 — 支持运行时通过 config.json 指定数据库路径。

- engine / SessionLocal / get_db 延迟初始化
- 调用 init_database() 后再访问数据库
- WAL 模式在每个新连接上自动启用
"""
from sqlalchemy import create_engine, pool, event
from sqlalchemy.orm import declarative_base, sessionmaker
from loguru import logger

Base = declarative_base()

_engine = None
_SessionLocal = None


def init_database(db_dir: str) -> None:
    """初始化数据库引擎与连接池。
    
    Args:
        db_dir: 数据库文件所在目录的绝对路径（如 .../api_server/user_data）
    """
    from pathlib import Path
    global _engine, _SessionLocal

    data_dir = Path(db_dir)
    data_dir.mkdir(parents=True, exist_ok=True)

    db_path = data_dir / "invoice_system.db"
    database_url = f"sqlite:///{db_path}"

    _engine = create_engine(
        database_url,
        connect_args={
            "check_same_thread": False,
            "timeout": 15,
        },
        poolclass=pool.QueuePool,
        pool_size=5,
        max_overflow=10,
        pool_recycle=3600,
        pool_timeout=30,
        pool_pre_ping=True,  # 每次检出连接前发送 SELECT 1，自动检测并替换断连
    )

    _SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=_engine)

    # ── WAL 模式：每次新连接时自动启用 ──
    @event.listens_for(_engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.close()

    # ── 连接池预热：消除首个请求的冷启动延迟 ──
    try:
        conn = _engine.connect()
        conn.close()
        logger.debug("数据库连接池已预热")
    except Exception as e:
        logger.warning("连接池预热失败（不影响正常使用）| error={}", e)

    logger.info("数据库引擎初始化完成 | path={}", db_path)


def get_engine():
    """获取当前数据库引擎（模块未初始化时抛异常）"""
    if _engine is None:
        raise RuntimeError("数据库引擎尚未初始化，请先调用 init_database()")
    return _engine


def get_session_local():
    """获取 SessionLocal 工厂"""
    if _SessionLocal is None:
        raise RuntimeError("数据库引擎尚未初始化，请先调用 init_database()")
    return _SessionLocal


def get_db():
    """FastAPI 依赖注入：每个请求创建一个 DB 会话，完成后自动关闭"""
    SessionLocal = get_session_local()
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
