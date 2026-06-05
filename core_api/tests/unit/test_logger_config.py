"""
日志配置模块单元测试 — setup_loguru + _InterceptHandler

覆盖模块: app/logger_config.py
Fixtures: 无（独立测试）
注意：conftest 的 _silence_loguru 是 session autouse，
会先于本测试文件运行，因此 setup_loguru 调用时 loguru 已被静默。
本测试验证核心行为而非副作用。
"""
import logging
import pytest
from pathlib import Path
from loguru import logger as loguru_logger

from app.logger_config import setup_loguru, _InterceptHandler


class TestSetupLoguru:
    """setup_loguru 初始化"""

    def test_creates_log_directory(self, tmp_path):
        """调用 setup_loguru 时自动创建日志目录"""
        # Arrange
        log_dir = tmp_path / "test_logs"
        # Act
        setup_loguru(str(log_dir))
        # Assert
        assert log_dir.exists()
        assert log_dir.is_dir()

    def test_does_not_throw_on_repeated_calls(self, tmp_path):
        """重复调用不应崩溃"""
        # Arrange
        log_dir = tmp_path / "repeat_logs"
        # Act & Assert — 不应抛异常
        setup_loguru(str(log_dir))
        setup_loguru(str(log_dir))

    def test_accepts_path_with_spaces(self, tmp_path):
        """路径包含空格时应正常工作"""
        # Arrange
        log_dir = tmp_path / "my logs with spaces"
        # Act
        setup_loguru(str(log_dir))
        # Assert
        assert log_dir.exists()


class TestInterceptHandler:
    """_InterceptHandler — 标准 logging → Loguru 重定向"""

    def test_handler_is_valid_logging_handler(self):
        """_InterceptHandler 是 logging.Handler 的子类"""
        # Assert
        assert issubclass(_InterceptHandler, logging.Handler)

    def test_emit_with_info_record_does_not_raise(self):
        """emit 一个 INFO 级别记录不应抛异常"""
        # Arrange
        handler = _InterceptHandler()
        record = logging.LogRecord(
            name="test_logger",
            level=logging.INFO,
            pathname=__file__,
            lineno=1,
            msg="test message",
            args=(),
            exc_info=None,
        )
        # Act & Assert — 不应抛异常
        handler.emit(record)

    def test_emit_with_error_record_with_exception(self):
        """emit 一个 ERROR 级别记录（带异常）不应抛异常"""
        # Arrange
        handler = _InterceptHandler()
        try:
            raise ValueError("test error")
        except ValueError:
            import sys
            exc_info = sys.exc_info()
            record = logging.LogRecord(
                name="error_logger",
                level=logging.ERROR,
                pathname=__file__,
                lineno=42,
                msg="an error occurred",
                args=(),
                exc_info=exc_info,
            )
        # Act & Assert — 不应抛异常
        handler.emit(record)

    def test_emit_with_custom_log_level_does_not_raise(self):
        """emit 一个自定义 level（如 CRITICAL 50）不应抛异常"""
        # Arrange
        handler = _InterceptHandler()
        record = logging.LogRecord(
            name="critical_logger",
            level=logging.CRITICAL,
            pathname=__file__,
            lineno=1,
            msg="critical issue",
            args=(),
            exc_info=None,
        )
        # Act & Assert
        handler.emit(record)
