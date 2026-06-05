"""
Dashboard Router 集成测试 — 覆盖 /api/dashboard 下所有端点。

覆盖模块: app/routers/dashboard.py
Fixtures: fastapi_client
"""
import pytest


class TestDashboardSummary:
    """GET /api/dashboard/summary"""

    def test_returns_200_with_all_fields(self, fastapi_client):
        """空库正常返回 200 + 3 个字段"""
        # Arrange & Act
        resp = fastapi_client.get("/api/dashboard/summary")
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert "total_amount" in data
        assert "pending_amount" in data
        assert "invoice_count" in data
        assert data["total_amount"] == 0.0

    def test_counts_pending_correctly_after_create(self, fastapi_client):
        """创建待开票记录后 pending_amount 正确"""
        # Arrange
        fastapi_client.post("/api/expenses/", json={
            "title": "待开票A", "amount": 100.0,
            "incurred_date": "2025-06-15", "status": "待开票"})
        fastapi_client.post("/api/expenses/", json={
            "title": "已完结B", "amount": 200.0,
            "incurred_date": "2025-06-15", "status": "已完结"})
        # Act
        resp = fastapi_client.get("/api/dashboard/summary")
        # Assert
        data = resp.json()
        assert data["total_amount"] == 300.0
        assert data["pending_amount"] == 100.0


class TestDashboardTrend:
    """GET /api/dashboard/trend"""

    def test_returns_12_months(self, fastapi_client):
        """空库也返回 12 个月的数据"""
        # Arrange & Act
        resp = fastapi_client.get("/api/dashboard/trend")
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 12
        for item in data:
            assert "month" in item
            assert "amount" in item
            assert item["amount"] == 0.0

    def test_each_item_has_yyyy_mm_format(self, fastapi_client):
        """month 字段符合 YYYY-MM 格式"""
        # Arrange & Act
        resp = fastapi_client.get("/api/dashboard/trend")
        # Assert
        for item in resp.json():
            parts = item["month"].split("-")
            assert len(parts) == 2
            assert len(parts[0]) == 4  # YYYY
            assert 1 <= int(parts[1]) <= 12  # MM


class TestDashboardDistribution:
    """GET /api/dashboard/distribution"""

    def test_returns_empty_list_initially(self, fastapi_client):
        """空库 → []"""
        # Arrange & Act
        resp = fastapi_client.get("/api/dashboard/distribution")
        # Assert
        assert resp.status_code == 200
        assert resp.json() == []

    def test_supports_days_query_param(self, fastapi_client):
        """days=30 参数合法"""
        # Arrange & Act
        resp = fastapi_client.get("/api/dashboard/distribution?days=30")
        # Assert
        assert resp.status_code == 200

    def test_returns_items_with_category_amount_percentage(self, fastapi_client):
        """有数据时返回 category/amount/percentage"""
        # Arrange
        fastapi_client.post("/api/expenses/", json={
            "title": "差旅", "amount": 100.0,
            "incurred_date": "2025-06-15", "project_name": "差旅项目"})
        # Act
        resp = fastapi_client.get("/api/dashboard/distribution")
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) >= 1
        assert "category" in data[0]
        assert "amount" in data[0]
        assert "percentage" in data[0]


class TestDashboardHeatmap:
    """GET /api/dashboard/heatmap"""

    def test_returns_90_days(self, fastapi_client):
        """空库返回 90 天数据"""
        # Arrange & Act
        resp = fastapi_client.get("/api/dashboard/heatmap")
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 90
        for item in data:
            assert "date" in item
            assert "count" in item

    def test_dates_are_chronological(self, fastapi_client):
        """日期升序排列"""
        # Arrange & Act
        resp = fastapi_client.get("/api/dashboard/heatmap")
        # Assert
        dates = [item["date"] for item in resp.json()]
        assert dates == sorted(dates)


class TestDashboardTypeDistribution:
    """GET /api/dashboard/type-distribution"""

    def test_returns_empty_list_initially(self, fastapi_client):
        """空库 → []"""
        # Arrange & Act
        resp = fastapi_client.get("/api/dashboard/type-distribution")
        # Assert
        assert resp.status_code == 200
        assert resp.json() == []

    def test_supports_days_query_param(self, fastapi_client):
        """days=7 参数合法"""
        # Arrange & Act
        resp = fastapi_client.get("/api/dashboard/type-distribution?days=7")
        # Assert
        assert resp.status_code == 200

    def test_returns_type_distribution_with_data(self, fastapi_client):
        """有数据时按 expense_type 分组"""
        # Arrange
        fastapi_client.post("/api/expenses/", json={
            "title": "办公采购", "amount": 50.0,
            "incurred_date": "2025-06-15", "expense_type": "办公用品"})
        # Act
        resp = fastapi_client.get("/api/dashboard/type-distribution")
        # Assert
        data = resp.json()
        assert len(data) >= 1
        assert "category" in data[0]
        assert "amount" in data[0]
        assert "percentage" in data[0]
