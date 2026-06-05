"""
Settings Router 集成测试 — 覆盖 /api/settings 下所有端点。

覆盖模块: app/routers/settings.py
Fixtures: fastapi_client（已由 autouse fixture 接管 config I/O）
"""
import pytest


class TestGetPaths:
    """GET /api/settings/paths"""

    def test_returns_200_with_all_fields(self, fastapi_client):
        """返回当前配置路径"""
        # Arrange & Act
        resp = fastapi_client.get("/api/settings/paths")
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        for key in ("db_path", "log_path", "pdf_path", "current_pdf_shard",
                     "shard_file_count"):
            assert key in data, f"缺少字段: {key}"

    def test_paths_point_to_temp_dir_not_real_config(self, fastapi_client):
        """返回的路径应指向临时目录，非真实项目路径"""
        # Arrange & Act
        resp = fastapi_client.get("/api/settings/paths")
        # Assert
        data = resp.json()
        assert "api_server" not in data["db_path"]
        assert "Invoice-Management" not in data["db_path"]


class TestPutPaths:
    """PUT /api/settings/paths"""

    def test_updates_paths_successfully(self, fastapi_client, tmp_path):
        """合法路径 → 200"""
        # Arrange
        db = tmp_path / "new_db"
        log = tmp_path / "new_log"
        # Act
        resp = fastapi_client.put("/api/settings/paths", json={
            "db_path": str(db),
            "log_path": str(log),
        })
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert data["db_path"] == str(db)
        assert data["log_path"] == str(log)

    def test_returns_400_when_paths_are_same(self, fastapi_client, tmp_path):
        """相同路径 → 400"""
        # Arrange
        same = tmp_path / "same_dir"
        same.mkdir()
        # Act
        resp = fastapi_client.put("/api/settings/paths", json={
            "db_path": str(same),
            "log_path": str(same),
        })
        # Assert
        assert resp.status_code == 400

    def test_returns_400_when_log_inside_pdfs(self, fastapi_client, tmp_path):
        """log 在 pdfs 子目录内 → 400"""
        # Arrange
        db = tmp_path / "db"
        pdfs = db / "pdfs"
        pdfs.mkdir(parents=True)
        # Act
        resp = fastapi_client.put("/api/settings/paths", json={
            "db_path": str(db),
            "log_path": str(pdfs),
        })
        # Assert
        assert resp.status_code == 400


class TestValidatePaths:
    """POST /api/settings/validate"""

    def test_valid_paths_returns_true(self, fastapi_client, tmp_path):
        """合法路径 → valid=True"""
        # Arrange
        db = tmp_path / "v_db"
        log = tmp_path / "v_log"
        # Act
        resp = fastapi_client.post("/api/settings/validate", json={
            "db_path": str(db),
            "log_path": str(log),
        })
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert data["valid"] is True
        assert data["error"] is None

    def test_invalid_paths_returns_false_with_error(self, fastapi_client, tmp_path):
        """非法路径 → valid=False + error_msg"""
        # Arrange
        same = tmp_path / "same"
        # Act
        resp = fastapi_client.post("/api/settings/validate", json={
            "db_path": str(same),
            "log_path": str(same),
        })
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert data["valid"] is False
        assert data["error"] is not None


class TestPreviewStructure:
    """POST /api/settings/preview"""

    def test_returns_structure_preview(self, fastapi_client):
        """返回 db_structure + log_structure"""
        # Arrange & Act
        resp = fastapi_client.post("/api/settings/preview", json={
            "db_path": "/preview/db",
            "log_path": "/preview/log",
        })
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert "db_structure" in data
        assert "log_structure" in data
        assert isinstance(data["db_structure"], list)
        assert isinstance(data["log_structure"], list)


class TestRestart:
    """POST /api/settings/restart"""

    def test_returns_restart_action(self, fastapi_client):
        """返回 action=restart + message"""
        # Arrange & Act
        resp = fastapi_client.post("/api/settings/restart")
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert data["action"] == "restart"
        assert "message" in data
