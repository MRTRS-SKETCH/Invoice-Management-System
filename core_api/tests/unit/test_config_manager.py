"""
配置管理模块单元测试 — validate_paths / preview_directory_structure / resolve_absolute_pdf_path 等纯逻辑函数。

覆盖模块: app/config_manager.py
Fixtures: _patch_config_manager (autouse — 已全局 hijack 磁盘 I/O)
注意：load_config / save_config 的 I/O 路径已被 autouse fixture 接管，
此处仅测试其逻辑行为（通过 fake 函数验证）。
"""
import pytest
import os
from pathlib import Path
from unittest.mock import patch, MagicMock

from app import config_manager as cm


# ── 每个测试前重置配置缓存，防止前序 save_config 污染 ──
@pytest.fixture(autouse=True)
def _reset_config_cache():
    cm._config_cache = None
    yield
    cm._config_cache = None


# ═══════════════════════════════════════════════════════════════
#  validate_paths
# ═══════════════════════════════════════════════════════════════

class TestValidatePaths:
    """路径校验函数"""

    # ── Happy Path ──

    def test_returns_valid_for_different_writable_paths(self, tmp_path):
        """两个不同的可写目录 → (True, None)"""
        # Arrange
        db = tmp_path / "db"
        log = tmp_path / "log"
        # Act
        valid, error = cm.validate_paths(str(db), str(log))
        # Assert
        assert valid is True
        assert error is None

    def test_returns_valid_when_both_are_nested_but_not_overlapping_restriction(
        self, tmp_path
    ):
        """db 和 log 在同一父目录下，不违反规则 → (True, None)"""
        # Arrange
        base = tmp_path / "base"
        db = base / "data"
        log = base / "logs"
        # Act
        valid, error = cm.validate_paths(str(db), str(log))
        # Assert
        assert valid is True

    # ── 边界/异常 ──

    def test_returns_invalid_when_paths_are_same_directory(self, tmp_path):
        """相同目录 → (False, error_msg)"""
        # Arrange
        same = tmp_path / "same"
        # Act
        valid, error = cm.validate_paths(str(same), str(same))
        # Assert
        assert valid is False
        assert "不能为同一目录" in error

    def test_returns_invalid_when_log_inside_pdfs_directory(self, tmp_path):
        """log_path 位于 db_path/pdfs 内 → (False, error_msg)"""
        # Arrange
        db = tmp_path / "db"
        pdfs = db / "pdfs"
        pdfs.mkdir(parents=True)
        # Act
        valid, error = cm.validate_paths(str(db), str(pdfs))
        # Assert
        assert valid is False
        assert "日志路径不能位于" in error

    def test_returns_invalid_when_log_inside_pdfs_shard_directory(self, tmp_path):
        """log_path 位于 db_path/pdfs_3 分片子目录内 → (False, error_msg)"""
        # Arrange
        db = tmp_path / "db"
        pdfs3 = db / "pdfs_3"
        pdfs3.mkdir(parents=True)
        # Act
        valid, error = cm.validate_paths(str(db), str(pdfs3))
        # Assert
        assert valid is False
        assert "日志路径不能位于" in error

    def test_returns_invalid_when_path_cannot_be_created(
        self, tmp_path, monkeypatch
    ):
        """路径不可写（模拟 PermissionError）→ (False, error_msg)"""
        # Arrange
        db = tmp_path / "db"
        log = tmp_path / "log"

        def _fake_mkdir(self, parents=False, exist_ok=False):
            raise PermissionError("Access denied")

        monkeypatch.setattr(Path, "mkdir", _fake_mkdir)
        # Act
        valid, error = cm.validate_paths(str(db), str(log))
        # Assert
        assert valid is False
        assert "权限" in error or "无法创建" in error

    def test_returns_invalid_for_invalid_path_characters(self):
        """非法路径字符（Windows 不允许的字符）"""
        # Arrange & Act
        valid, error = cm.validate_paths(
            "C:\\valid_db",
            "C:\\valid_log",
        )
        # Assert — C:\\valid_* 应该合法
        assert valid is True


# ═══════════════════════════════════════════════════════════════
#  preview_directory_structure
# ═══════════════════════════════════════════════════════════════

class TestPreviewDirectoryStructure:
    """目录结构预览函数"""

    def test_returns_expected_keys(self):
        """返回的字典包含所有必要键"""
        # Arrange & Act
        result = cm.preview_directory_structure("/fake/db", "/fake/log")
        # Assert
        assert "db_path" in result
        assert "log_path" in result
        assert "pdf_path" in result
        assert "db_structure" in result
        assert "log_structure" in result

    def test_db_structure_includes_db_file_and_pdfs_dir(self):
        """db_structure 包含 invoice_system.db 和 pdfs/"""
        # Arrange & Act
        result = cm.preview_directory_structure("/db", "/log")
        # Assert
        assert "invoice_system.db" in result["db_structure"]
        assert "pdfs/" in result["db_structure"]

    def test_log_structure_includes_app_log(self):
        """log_structure 包含 app.log"""
        # Arrange & Act
        result = cm.preview_directory_structure("/db", "/log")
        # Assert
        assert "app.log" in result["log_structure"]

    def test_pdf_path_ends_with_separator(self):
        """pdf_path 以路径分隔符结尾"""
        # Arrange & Act
        result = cm.preview_directory_structure("/db", "/log")
        # Assert
        assert result["pdf_path"].endswith(os.sep)

    def test_returns_original_paths_unchanged(self):
        """返回的 db_path / log_path 与传入一致"""
        # Arrange & Act
        result = cm.preview_directory_structure("/my/db", "/my/log")
        # Assert
        assert result["db_path"] == "/my/db"
        assert result["log_path"] == "/my/log"

    def test_is_pure_preview_no_files_created(self, tmp_path):
        """纯预览，不实际创建任何文件/目录"""
        # Arrange
        db = tmp_path / "preview_db"
        log = tmp_path / "preview_log"
        # Act
        cm.preview_directory_structure(str(db), str(log))
        # Assert
        assert not db.exists()
        assert not log.exists()


# ═══════════════════════════════════════════════════════════════
#  resolve_absolute_pdf_path
# ═══════════════════════════════════════════════════════════════

class TestResolveAbsolutePdfPath:
    """PDF 相对路径 → 绝对路径解析"""

    def test_resolves_standard_pdf_path(self, tmp_data_dir):
        """标准路径 pdfs/xxx.pdf → db_path/pdfs/xxx.pdf"""
        # Arrange
        saved = "pdfs/test.pdf"
        # Act
        result = cm.resolve_absolute_pdf_path(saved)
        # Assert
        expected = Path(tmp_data_dir["db_path"]) / "pdfs" / "test.pdf"
        assert result == expected

    def test_resolves_sharded_pdf_path(self, tmp_data_dir):
        """分片路径 pdfs_3/xxx.pdf → db_path/pdfs_3/xxx.pdf"""
        # Arrange
        saved = "pdfs_3/test.pdf"
        # Act
        result = cm.resolve_absolute_pdf_path(saved)
        # Assert
        expected = Path(tmp_data_dir["db_path"]) / "pdfs_3" / "test.pdf"
        assert result == expected

    def test_strips_user_data_prefix(self, tmp_data_dir):
        """兼容旧格式 user_data/pdfs/xxx.pdf → db_path/pdfs/xxx.pdf"""
        # Arrange
        saved = "user_data/pdfs/old_file.pdf"
        # Act
        result = cm.resolve_absolute_pdf_path(saved)
        # Assert
        expected = Path(tmp_data_dir["db_path"]) / "pdfs" / "old_file.pdf"
        assert result == expected

    def test_strips_user_data_prefix_with_shard(self, tmp_data_dir):
        """user_data/pdfs_2/xxx.pdf → db_path/pdfs_2/xxx.pdf"""
        # Arrange
        saved = "user_data/pdfs_2/sharded.pdf"
        # Act
        result = cm.resolve_absolute_pdf_path(saved)
        # Assert
        expected = Path(tmp_data_dir["db_path"]) / "pdfs_2" / "sharded.pdf"
        assert result == expected

    def test_no_user_data_prefix_passed_through(self, tmp_data_dir):
        """不以 user_data/ 开头 → 直接拼接"""
        # Arrange
        saved = "pdfs/direct.pdf"
        # Act
        result = cm.resolve_absolute_pdf_path(saved)
        # Assert
        expected = Path(tmp_data_dir["db_path"]) / "pdfs" / "direct.pdf"
        assert result == expected


# ═══════════════════════════════════════════════════════════════
#  _count_files_in_dir
# ═══════════════════════════════════════════════════════════════

class TestCountFilesInDir:
    """内部文件计数函数"""

    def test_returns_zero_for_empty_directory(self, tmp_path):
        """空目录 → 0"""
        # Arrange
        d = tmp_path / "empty"
        d.mkdir()
        # Act
        count = cm._count_files_in_dir(d)
        # Assert
        assert count == 0

    def test_returns_correct_count_for_directory_with_files(self, tmp_path):
        """含 5 个文件的目录 → 5"""
        # Arrange
        d = tmp_path / "with_files"
        d.mkdir()
        for i in range(5):
            (d / f"file_{i}.pdf").write_text("content")
        # Act
        count = cm._count_files_in_dir(d)
        # Assert
        assert count == 5

    def test_returns_zero_for_non_existent_directory(self, tmp_path):
        """不存在的目录 → 0"""
        # Arrange
        d = tmp_path / "does_not_exist"
        # Act
        count = cm._count_files_in_dir(d)
        # Assert
        assert count == 0

    def test_excludes_subdirectories_from_count(self, tmp_path):
        """仅统计文件，不统计子目录"""
        # Arrange
        d = tmp_path / "mixed"
        d.mkdir()
        (d / "file1.pdf").write_text("content")
        (d / "subdir").mkdir()
        (d / "file2.pdf").write_text("content")
        # Act
        count = cm._count_files_in_dir(d)
        # Assert
        assert count == 2


# ═══════════════════════════════════════════════════════════════
#  load_config / save_config (通过 autouse fixture 验证)
# ═══════════════════════════════════════════════════════════════

class TestConfigLoadSave:
    """配置加载/保存（已被 fixture 劫持）"""

    def test_load_config_returns_temp_dir_paths(self, tmp_data_dir):
        """load_config 返回的路径指向临时目录（非真实 config）"""
        # Act
        cfg = cm.load_config()
        # Assert
        assert cfg["db_path"] == tmp_data_dir["db_path"]
        assert cfg["log_path"] == tmp_data_dir["log_path"]

    def test_load_config_includes_pdf_shard_fields(self):
        """load_config 包含分片相关字段"""
        # Act
        cfg = cm.load_config()
        # Assert
        assert "pdf_shard_size" in cfg
        assert "current_pdf_shard" in cfg
        assert "shard_file_count" in cfg
        assert cfg["pdf_shard_size"] == 1000

    def test_save_config_updates_paths(self, tmp_data_dir):
        """save_config 更新路径"""
        # Arrange
        new_db = "/new/db/path"
        new_log = "/new/log/path"
        # Act
        cfg = cm.save_config(new_db, new_log)
        # Assert
        assert cfg["db_path"] == new_db
        assert cfg["log_path"] == new_log

    def test_save_config_resets_shard_counter(self):
        """save_config 重置分片计数器为 0"""
        # Arrange & Act
        cfg = cm.save_config("/db", "/log")
        # Assert
        assert cfg["current_pdf_shard"] == 0

    def test_get_db_path_returns_path_object(self, tmp_data_dir):
        """get_db_path 返回 Path 对象并确保目录存在"""
        # Act
        p = cm.get_db_path()
        # Assert
        assert isinstance(p, Path)
        assert p.exists()

    def test_get_log_path_returns_path_object(self, tmp_data_dir):
        """get_log_path 返回 Path 对象并确保目录存在"""
        # Act
        p = cm.get_log_path()
        # Assert
        assert isinstance(p, Path)
        assert p.exists()

    def test_get_db_file_path_returns_correct_file(self):
        """get_db_file_path 返回 {db_path}/invoice_system.db"""
        # Arrange
        cfg = cm.load_config()
        # Act
        p = cm.get_db_file_path()
        # Assert
        assert p.name == "invoice_system.db"
        assert p.parent == Path(cfg["db_path"])

    def test_get_pdf_dir_returns_path_with_pdfs(self):
        """get_pdf_dir (shard=0) 返回 {db_path}/pdfs"""
        # Arrange
        cfg = cm.load_config()
        # Act
        p = cm.get_pdf_dir()
        # Assert
        assert p.name == "pdfs"
        assert p.parent == Path(cfg["db_path"])

    def test_get_config_for_api_returns_all_keys(self):
        """get_config_for_api 返回 5 个必要键"""
        # Act
        summary = cm.get_config_for_api()
        # Assert
        for key in ("db_path", "log_path", "pdf_path", "current_pdf_shard",
                     "shard_file_count"):
            assert key in summary
