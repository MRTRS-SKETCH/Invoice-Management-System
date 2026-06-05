"""
全局测试 Fixture 配置 — 为所有测试提供隔离、可控的运行环境。

设计原则：
- 绝不触碰真实 config/config.json、真实数据库文件、真实日志目录
- Session-scoped 资源（engine、临时目录、config patch）共享复用
- Function-scoped 资源（DB session、TestClient）每测试独立 + 自动回滚
"""
from __future__ import annotations

import pytest
from pathlib import Path
from unittest.mock import MagicMock
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from loguru import logger


# ═══════════════════════════════════════════════════════════════
#  Session-scoped — 跨测试共享，只初始化一次
# ═══════════════════════════════════════════════════════════════

@pytest.fixture(scope="session")
def tmp_data_dir(tmp_path_factory: pytest.TempPathFactory) -> dict:
    """会话级隔离临时目录 — 模拟 db/log/pdf 存储路径。

    结构：
        {base}/
        ├── user_data/        ← db_path
        │   └── pdfs/         ← PDF 存储
        └── logs/             ← log_path
    """
    base = tmp_path_factory.mktemp("test_data")
    db_dir = base / "user_data"
    log_dir = base / "logs"
    db_dir.mkdir()
    (db_dir / "pdfs").mkdir()
    log_dir.mkdir()
    return {
        "base": str(base),
        "db_path": str(db_dir),
        "log_path": str(log_dir),
    }


@pytest.fixture(scope="session", autouse=True)
def _patch_config_manager(tmp_data_dir: dict) -> None:
    """全局 monkeypatch：劫持 config_manager，所有配置读写指向临时目录。

    autouse=True 确保在任何测试导入/执行前生效，
    防止模块级代码意外读写真实 config/config.json。
    """
    import app.config_manager as cm

    # ── 保存原始引用（teardown 时恢复）──
    _orig_load_config = cm.load_config
    _orig_save_config = cm.save_config
    _orig__save_raw = cm._save_raw

    db_path = tmp_data_dir["db_path"]
    log_path = tmp_data_dir["log_path"]

    def _fake_load_config() -> dict:
        """返回指向临时目录的伪配置"""
        cache = getattr(cm, "_config_cache", None)
        if cache is not None:
            return cache
        cfg = {
            "db_path": db_path,
            "log_path": log_path,
            "pdf_shard_size": 1000,
            "current_pdf_shard": 0,
            "shard_file_count": 0,
        }
        cm._config_cache = cfg
        return cfg

    def _fake_save_config(db_path_new: str | None = None,
                          log_path_new: str | None = None) -> dict:
        """不写磁盘，仅更新内存缓存"""
        cfg = {
            "db_path": db_path_new or db_path,
            "log_path": log_path_new or log_path,
            "pdf_shard_size": 1000,
            "current_pdf_shard": 0,
            "shard_file_count": 0,
        }
        cm._config_cache = cfg
        return cfg

    # 清除真实缓存，注入伪造函数
    cm._config_cache = None
    cm.load_config = _fake_load_config
    cm.save_config = _fake_save_config
    cm._save_raw = lambda _cfg: None  # 静默吞掉所有磁盘写入

    yield  # ← 所有测试在此执行

    # ── 恢复原始函数 ──
    cm._config_cache = None
    cm.load_config = _orig_load_config
    cm.save_config = _orig_save_config
    cm._save_raw = _orig__save_raw


@pytest.fixture(scope="session", autouse=True)
def _silence_loguru() -> None:
    """全局静默 Loguru — 移除所有 handler，防止测试期间写磁盘日志文件。"""
    logger.remove()
    # 添加一个黑洞 handler 避免 "no handler" 警告
    handler_id = logger.add(lambda _: None, level="ERROR")

    yield

    try:
        logger.remove(handler_id)
    except ValueError:
        pass  # 已被 setup_loguru 移除（test_logger_config.py 等）


@pytest.fixture(scope="session")
def _test_engine() -> "Engine":
    """会话级 SQLite :memory: 引擎 — 所有测试共享，建表只执行一次。"""
    from app.models import Base

    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        echo=False,
    )
    Base.metadata.create_all(bind=engine)
    return engine


# ═══════════════════════════════════════════════════════════════
#  Function-scoped — 每个测试独立，自动回滚保证隔离
# ═══════════════════════════════════════════════════════════════

@pytest.fixture
def test_db_session(_test_engine):
    """每个测试函数独立的数据库会话。

    核心机制：
    1. 创建一个连接级事务（SAVEPOINT 等效）
    2. 测试代码内的所有 db.commit() 都提交到此事务
    3. teardown 时回滚整个事务 → 数据完全隔离，无脏数据残留
    """
    connection = _test_engine.connect()
    transaction = connection.begin()          # ← 开启外层事务
    TestSession = sessionmaker(bind=connection)
    session = TestSession()

    yield session

    # ── 清理：回滚 + 关闭 ──
    session.close()
    transaction.rollback()
    connection.close()


@pytest.fixture
def fastapi_client(test_db_session):
    """每个测试独立的 FastAPI TestClient，get_db 已覆写为 test_db_session。

    用法：
        def test_create_expense(fastapi_client):
            resp = fastapi_client.post("/api/expenses/", json={...})
            assert resp.status_code == 201
    """
    from app.database import get_db
    from app.routers import expenses, invoices, dashboard, client_logs, settings

    app = FastAPI(title="Test API", version="0.0.0")
    app.include_router(expenses.router)
    app.include_router(invoices.router)
    app.include_router(dashboard.router)
    app.include_router(client_logs.router)
    app.include_router(settings.router)

    # 覆写 get_db → 注入 test_db_session
    def _override_get_db():
        yield test_db_session

    app.dependency_overrides[get_db] = _override_get_db

    with TestClient(app) as client:
        yield client

    app.dependency_overrides.clear()


# ═══════════════════════════════════════════════════════════════
#  Mock Fixture — 按需使用
# ═══════════════════════════════════════════════════════════════

@pytest.fixture
def mock_pdfplumber(monkeypatch) -> MagicMock:
    """替换 PdfReader 为可控 Mock，不依赖真实 PDF 文件。

    用法：
        def test_parse_invoice(mock_pdfplumber):
            from app.utils.invoice_parser import parse_invoice_pdf
            result = parse_invoice_pdf("fake.pdf")
            assert result["amount"] == 2996.00
    """
    mock_page = MagicMock()

    # 默认返回一张完整的增值税专用发票文本（覆盖 5 个解析字段）
    mock_page.extract_text.return_value = (
        "增值税专用发票\n"
        "开票日期：2024年05月20日\n"
        "项目名称 规格型号 数量 单价 金额 税率 税额\n"
        "*酒*汾酒精品 53度 500ml*6瓶 箱 2 1325.66 2651.33 13% 344.67\n"
        "价税合计（大写）贰仟玖佰玖拾陆圆整 （小写）¥2996.00\n"
        "订单号:2007064325443298\n"
    )

    mock_reader = MagicMock()
    mock_reader.pages = [mock_page]

    mock_constructor = MagicMock(return_value=mock_reader)
    monkeypatch.setattr("app.utils.invoice_parser.PdfReader", mock_constructor)

    return mock_constructor
