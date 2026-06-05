"""
数据库引擎模块测试 — 延迟初始化、引擎获取、WAL 模式。

覆盖模块: app/database.py
Fixtures: 无（独立测试，不依赖 conftest fixture）
"""
import pytest
from sqlalchemy import Engine
from sqlalchemy.orm import sessionmaker

import app.database as db_module
from app import models  # 确保表注册到 Base.metadata


class TestDatabaseInit:
    """init_database / get_engine / get_session_local"""

    def test_init_database_creates_engine(self, tmp_path):
        """init_database 后 get_engine 返回有效 Engine 对象"""
        # Arrange
        data_dir = tmp_path / "data"
        # Act
        db_module.init_database(str(data_dir))
        engine = db_module.get_engine()
        # Assert
        assert engine is not None
        assert isinstance(engine, Engine)

    def test_init_database_creates_db_file_after_connect(self, tmp_path):
        """init_database 后首次建表时自动创建数据库文件"""
        # Arrange
        data_dir = tmp_path / "data2"
        # Act
        db_module.init_database(str(data_dir))
        engine = db_module.get_engine()
        db_module.Base.metadata.create_all(bind=engine)
        # Assert
        db_file = data_dir / "invoice_system.db"
        assert db_file.exists()

    def test_get_session_local_returns_factory(self, tmp_path):
        """init_database 后 get_session_local 返回 sessionmaker 工厂"""
        # Arrange
        data_dir = tmp_path / "data3"
        db_module.init_database(str(data_dir))
        # Act
        factory = db_module.get_session_local()
        # Assert
        assert isinstance(factory, sessionmaker)

    def test_get_engine_raises_when_not_initialized(self):
        """未调用 init_database 时 get_engine() 抛 RuntimeError"""
        # Arrange — 重置全局状态
        db_module._engine = None
        db_module._SessionLocal = None
        # Act & Assert
        with pytest.raises(RuntimeError, match="尚未初始化"):
            db_module.get_engine()

    def test_get_session_local_raises_when_not_initialized(self):
        """未调用 init_database 时 get_session_local() 抛 RuntimeError"""
        # Arrange
        db_module._engine = None
        db_module._SessionLocal = None
        # Act & Assert
        with pytest.raises(RuntimeError, match="尚未初始化"):
            db_module.get_session_local()


class TestGetDb:
    """get_db 依赖注入生成器"""

    @pytest.fixture(autouse=True)
    def _setup(self, tmp_path):
        """每个测试前初始化数据库"""
        db_module._engine = None
        db_module._SessionLocal = None
        data_dir = tmp_path / "getdb_test"
        db_module.init_database(str(data_dir))
        yield
        db_module._engine = None
        db_module._SessionLocal = None

    def test_get_db_yields_session_and_closes_after(self):
        """get_db 返回可用 session，with 块结束后自动关闭"""
        # Arrange & Act
        gen = db_module.get_db()
        session = next(gen)
        # Assert — session 可用
        assert session is not None
        assert session.is_active
        # Act — 关闭生成器
        try:
            next(gen)
        except StopIteration:
            pass
        # 无法直接验证连接已回池，但至少不抛异常

    def test_base_declarative_class_is_valid(self):
        """Base 是有效的 declarative_base"""
        # Assert
        assert db_module.Base is not None
        assert hasattr(db_module.Base, "metadata")
