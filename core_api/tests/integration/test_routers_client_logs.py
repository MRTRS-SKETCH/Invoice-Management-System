"""
Client Logs Router 集成测试 — 覆盖 /api/client-logs/batch 端点。

覆盖模块: app/routers/client_logs.py
Fixtures: fastapi_client
"""
import pytest


class TestReceiveClientLogs:
    """POST /api/client-logs/batch"""

    def test_receives_single_info_log(self, fastapi_client):
        """单条 INFO 日志 → 200 + count=1"""
        # Arrange
        payload = [{"level": "INFO", "message": "前端启动完成"}]
        # Act
        resp = fastapi_client.post("/api/client-logs/batch", json=payload)
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert data["count"] == 1

    def test_receives_multiple_entries_all_levels(self, fastapi_client):
        """多条不同级别日志 → 200"""
        # Arrange
        payload = [
            {"level": "INFO", "message": "info msg"},
            {"level": "WARNING", "message": "warning msg"},
            {"level": "ERROR", "message": "error msg"},
        ]
        # Act
        resp = fastapi_client.post("/api/client-logs/batch", json=payload)
        # Assert
        assert resp.status_code == 200
        assert resp.json()["count"] == 3

    def test_receives_empty_list(self, fastapi_client):
        """空列表 → 200 + count=0"""
        # Arrange
        payload = []
        # Act
        resp = fastapi_client.post("/api/client-logs/batch", json=payload)
        # Assert
        assert resp.status_code == 200
        assert resp.json()["count"] == 0

    def test_handles_unknown_level_gracefully(self, fastapi_client):
        """未知 level（如 DEBUG）→ 不崩溃，当作 INFO 写入"""
        # Arrange
        payload = [{"level": "DEBUG", "message": "debug message"}]
        # Act
        resp = fastapi_client.post("/api/client-logs/batch", json=payload)
        # Assert
        assert resp.status_code == 200

    def test_returns_422_when_level_missing(self, fastapi_client):
        """缺少 level 字段 → 422"""
        # Arrange
        payload = [{"message": "no level"}]
        # Act
        resp = fastapi_client.post("/api/client-logs/batch", json=payload)
        # Assert
        assert resp.status_code == 422

    def test_returns_422_when_message_missing(self, fastapi_client):
        """缺少 message 字段 → 422"""
        # Arrange
        payload = [{"level": "INFO"}]
        # Act
        resp = fastapi_client.post("/api/client-logs/batch", json=payload)
        # Assert
        assert resp.status_code == 422
