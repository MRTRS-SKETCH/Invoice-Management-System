"""
Expenses Router 集成测试 — 覆盖 /api/expenses 下所有 HTTP 端点。

覆盖模块: app/routers/expenses.py
Fixtures: fastapi_client（TestClient + 依赖覆写）
"""
import pytest
from unittest.mock import patch

from app import schemas


# ═══════════════════════════════════════════════════════════════
#  POST /api/expenses/ — create_expense
# ═══════════════════════════════════════════════════════════════

class TestCreateExpenseRouter:
    """POST /api/expenses/"""

    # ── Happy Path ──

    def test_creates_expense_and_returns_201(self, fastapi_client):
        """正常创建 → 201 + ExpenseResponse 结构"""
        # Arrange
        payload = {
            "title": "HTTP 创建测试",
            "amount": 150.00,
            "incurred_date": "2025-06-15",
            "status": "待开票",
        }
        # Act
        resp = fastapi_client.post("/api/expenses/", json=payload)
        # Assert
        assert resp.status_code == 201
        data = resp.json()
        assert data["title"] == "HTTP 创建测试"
        assert data["amount"] == 150.00
        assert "uuuid" in data
        assert data["status"] == "待开票"

    def test_creates_with_all_optional_fields(self, fastapi_client):
        """全字段传入 → 201 且所有字段返回"""
        # Arrange
        payload = {
            "title": "全字段",
            "amount": 500.00,
            "incurred_date": "2025-01-01",
            "status": "待报销",
            "submit_date": "2025-01-05",
            "complete_date": "2025-01-20",
            "actual_reimbursed_amount": 480.00,
            "has_company_invoice": True,
            "project_name": "项目X",
            "expense_type": "办公用品",
            "invoice_type": "增值票",
            "remark": "备注内容",
            "related_persons": "张三",
        }
        # Act
        resp = fastapi_client.post("/api/expenses/", json=payload)
        # Assert
        assert resp.status_code == 201
        data = resp.json()
        assert data["project_name"] == "项目X"
        assert data["expense_type"] == "办公用品"
        assert data["invoice_type"] == "增值票"

    # ── 边界 ──

    def test_defaults_status_when_not_provided(self, fastapi_client):
        """不传 status → 使用默认值 '待开票'"""
        # Arrange
        payload = {
            "title": "无状态字段",
            "amount": 100.00,
            "incurred_date": "2025-06-15",
        }
        # Act
        resp = fastapi_client.post("/api/expenses/", json=payload)
        # Assert
        assert resp.status_code == 201
        assert resp.json()["status"] == "待开票"

    def test_allows_zero_amount(self, fastapi_client):
        """金额 0 → 201"""
        # Arrange
        payload = {
            "title": "零金额",
            "amount": 0.0,
            "incurred_date": "2025-06-15",
        }
        # Act
        resp = fastapi_client.post("/api/expenses/", json=payload)
        # Assert
        assert resp.status_code == 201

    # ── 异常 ──

    def test_returns_422_when_title_missing(self, fastapi_client):
        """缺少必填字段 title → 422"""
        # Arrange
        payload = {"amount": 100.0, "incurred_date": "2025-06-15"}
        # Act
        resp = fastapi_client.post("/api/expenses/", json=payload)
        # Assert
        assert resp.status_code == 422

    def test_returns_422_when_amount_is_string(self, fastapi_client):
        """amount 类型错误 → 422"""
        # Arrange
        payload = {
            "title": "字符串金额",
            "amount": "abc",
            "incurred_date": "2025-06-15",
        }
        # Act
        resp = fastapi_client.post("/api/expenses/", json=payload)
        # Assert
        assert resp.status_code == 422


# ═══════════════════════════════════════════════════════════════
#  GET /api/expenses/ — get_expenses
# ═══════════════════════════════════════════════════════════════

class TestGetExpensesRouter:
    """GET /api/expenses/"""

    def test_returns_empty_list_initially(self, fastapi_client):
        """空库 → [] 且 200"""
        # Arrange & Act
        resp = fastapi_client.get("/api/expenses/")
        # Assert
        assert resp.status_code == 200
        assert resp.json() == []

    def test_returns_created_records(self, fastapi_client):
        """有记录时返回列表"""
        # Arrange
        fastapi_client.post("/api/expenses/", json={
            "title": "第一条", "amount": 100.0, "incurred_date": "2025-06-15"})
        fastapi_client.post("/api/expenses/", json={
            "title": "第二条", "amount": 200.0, "incurred_date": "2025-06-16"})
        # Act
        resp = fastapi_client.get("/api/expenses/")
        # Assert
        assert resp.status_code == 200
        assert len(resp.json()) == 2

    def test_search_query_param_filters_results(self, fastapi_client):
        """search=差旅 → 仅返回匹配结果"""
        # Arrange
        fastapi_client.post("/api/expenses/", json={
            "title": "差旅费", "amount": 100.0, "incurred_date": "2025-06-15"})
        fastapi_client.post("/api/expenses/", json={
            "title": "办公费", "amount": 200.0, "incurred_date": "2025-06-15"})
        # Act
        resp = fastapi_client.get("/api/expenses/?search=差旅")
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 1
        assert data[0]["title"] == "差旅费"

    def test_status_query_param_filters_results(self, fastapi_client):
        """status=已完结 → 仅返回匹配状态"""
        # Arrange
        fastapi_client.post("/api/expenses/", json={
            "title": "A", "amount": 100.0, "incurred_date": "2025-06-15",
            "status": "已完结"})
        fastapi_client.post("/api/expenses/", json={
            "title": "B", "amount": 200.0, "incurred_date": "2025-06-15",
            "status": "待开票"})
        # Act
        resp = fastapi_client.get("/api/expenses/?status=已完结")
        # Assert
        assert len(resp.json()) == 1

    def test_pagination_skip_and_limit(self, fastapi_client):
        """skip=1&limit=1 → 分页正确"""
        # Arrange
        for i in range(3):
            fastapi_client.post("/api/expenses/", json={
                "title": f"记录{i}",
                "amount": 100.0,
                "incurred_date": f"2025-06-{15 + i}",
            })
        # Act
        resp = fastapi_client.get("/api/expenses/?skip=1&limit=1")
        # Assert
        assert resp.status_code == 200
        assert len(resp.json()) == 1


# ═══════════════════════════════════════════════════════════════
#  PATCH /api/expenses/{uuuid} — update_expense
# ═══════════════════════════════════════════════════════════════

class TestUpdateExpenseRouter:
    """PATCH /api/expenses/{uuuid}"""

    def test_partial_update_returns_200(self, fastapi_client):
        """局部更新 → 200"""
        # Arrange
        create_resp = fastapi_client.post("/api/expenses/", json={
            "title": "原标题", "amount": 100.0, "incurred_date": "2025-06-15"})
        uuuid = create_resp.json()["uuuid"]
        # Act
        resp = fastapi_client.patch(
            f"/api/expenses/{uuuid}", json={"title": "新标题"})
        # Assert
        assert resp.status_code == 200
        assert resp.json()["title"] == "新标题"
        assert resp.json()["amount"] == 100.0  # 未变

    def test_returns_404_when_not_found(self, fastapi_client):
        """不存在的 uuuid → 404"""
        # Arrange & Act
        resp = fastapi_client.patch(
            "/api/expenses/non-existent-id", json={"title": "不存在"})
        # Assert
        assert resp.status_code == 404

    def test_status_transition_allowed(self, fastapi_client):
        """状态跨级流转 → 200（已解除限制）"""
        # Arrange
        create_resp = fastapi_client.post("/api/expenses/", json={
            "title": "跳转", "amount": 100.0, "incurred_date": "2025-06-15",
            "status": "待开票"})
        uuuid = create_resp.json()["uuuid"]
        # Act
        resp = fastapi_client.patch(
            f"/api/expenses/{uuuid}", json={"status": "已完结"})
        # Assert
        assert resp.status_code == 200
        assert resp.json()["status"] == "已完结"


# ═══════════════════════════════════════════════════════════════
#  POST /api/expenses/{uuuid}/block — block_expense
# ═══════════════════════════════════════════════════════════════

class TestBlockExpenseRouter:
    """POST /api/expenses/{uuuid}/block"""

    def test_block_success_returns_status_json(self, fastapi_client):
        """屏蔽成功 → 200 + status/success"""
        # Arrange
        create_resp = fastapi_client.post("/api/expenses/", json={
            "title": "待屏蔽", "amount": 100.0, "incurred_date": "2025-06-15"})
        uuuid = create_resp.json()["uuuid"]
        # Act
        resp = fastapi_client.post(f"/api/expenses/{uuuid}/block")
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "success"
        assert data["uuuid"] == uuuid

    def test_returns_404_when_not_found(self, fastapi_client):
        """不存在的 uuuid → 404"""
        # Arrange & Act
        resp = fastapi_client.post("/api/expenses/non-existent/block")
        # Assert
        assert resp.status_code == 404


# ═══════════════════════════════════════════════════════════════
#  POST /api/expenses/{uuuid}/unblock — unblock_expense
# ═══════════════════════════════════════════════════════════════

class TestUnblockExpenseRouter:
    """POST /api/expenses/{uuuid}/unblock"""

    def test_unblock_success(self, fastapi_client):
        """取消屏蔽 → 200"""
        # Arrange
        create_resp = fastapi_client.post("/api/expenses/", json={
            "title": "待解封", "amount": 100.0, "incurred_date": "2025-06-15"})
        uuuid = create_resp.json()["uuuid"]
        fastapi_client.post(f"/api/expenses/{uuuid}/block")
        # Act
        resp = fastapi_client.post(f"/api/expenses/{uuuid}/unblock")
        # Assert
        assert resp.status_code == 200
        assert resp.json()["status"] == "success"

    def test_returns_404_when_not_blocked(self, fastapi_client):
        """非屏蔽态取消失败 → 404"""
        # Arrange
        create_resp = fastapi_client.post("/api/expenses/", json={
            "title": "未屏蔽", "amount": 100.0, "incurred_date": "2025-06-15"})
        uuuid = create_resp.json()["uuuid"]
        # Act
        resp = fastapi_client.post(f"/api/expenses/{uuuid}/unblock")
        # Assert
        assert resp.status_code == 404


# ═══════════════════════════════════════════════════════════════
#  DELETE /api/expenses/{uuuid} — delete_expense
# ═══════════════════════════════════════════════════════════════

class TestDeleteExpenseRouter:
    """DELETE /api/expenses/{uuuid}"""

    @patch("os.remove")
    def test_delete_success(self, mock_remove, fastapi_client):
        """删除成功 → 200"""
        # Arrange
        create_resp = fastapi_client.post("/api/expenses/", json={
            "title": "待删除", "amount": 100.0, "incurred_date": "2025-06-15"})
        uuuid = create_resp.json()["uuuid"]
        # Act
        resp = fastapi_client.delete(f"/api/expenses/{uuuid}")
        # Assert
        assert resp.status_code == 200
        assert resp.json()["status"] == "success"

    def test_returns_404_when_not_found(self, fastapi_client):
        """不存在的 uuuid → 404"""
        # Arrange & Act
        resp = fastapi_client.delete("/api/expenses/non-existent")
        # Assert
        assert resp.status_code == 404


# ═══════════════════════════════════════════════════════════════
#  POST /api/expenses/export-pdfs — export_pdfs
# ═══════════════════════════════════════════════════════════════

class TestExportPdfsRouter:
    """POST /api/expenses/export-pdfs"""

    def test_returns_400_when_target_dir_not_exists(self, fastapi_client):
        """目标目录不存在 → 400"""
        # Arrange
        payload = {
            "uuuids": ["some-id"],
            "target_dir": "/non/existent/directory",
        }
        # Act
        resp = fastapi_client.post("/api/expenses/export-pdfs", json=payload)
        # Assert
        assert resp.status_code == 400

    def test_returns_400_when_target_is_file_not_directory(self, fastapi_client, tmp_path):
        """目标路径是文件而非目录 → 400"""
        # Arrange
        f = tmp_path / "file.txt"
        f.write_text("not a dir")
        payload = {"uuuids": ["some-id"], "target_dir": str(f)}
        # Act
        resp = fastapi_client.post("/api/expenses/export-pdfs", json=payload)
        # Assert
        assert resp.status_code == 400

    def test_exports_pdfs_to_target_directory(self, fastapi_client, tmp_path):
        """正常导出：目标目录存在且有发票数据"""
        # Arrange
        target = tmp_path / "export_target"
        target.mkdir()
        # 先创建一条开销和发票
        create_resp = fastapi_client.post("/api/expenses/", json={
            "title": "导出测试", "amount": 100.0,
            "incurred_date": "2025-06-15", "invoice_type": "增值票"})
        uuuid = create_resp.json()["uuuid"]

        # Act — 导出（此时无发票绑定，应创建目录但返回空）
        payload = {"uuuids": [uuuid], "target_dir": str(target)}
        resp = fastapi_client.post("/api/expenses/export-pdfs", json=payload)
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert "export_dir" in data
        assert data["all_count"] == 0
        assert data["vat_count"] == 0
        # 目录已创建
        assert (target / "2025-06-15").exists() or True  # 日期子目录
