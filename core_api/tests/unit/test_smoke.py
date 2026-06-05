"""
冒烟测试 — 验证整个测试基础设施（fixture 联动）可正常运行。

不覆盖具体业务逻辑，仅确认：
1. test_db_session 可正常读写
2. fastapi_client 可发送 HTTP 请求并获得正确响应
3. mock_config_manager / _silence_loguru 已生效
"""
import pytest
from datetime import date

from app import crud, schemas


class TestDatabaseSession:
    """验证 test_db_session fixture 基础能力"""

    def test_create_and_read_expense(self, test_db_session):
        """创建一条开销记录并立即查回，验证 CRUD 基础路径"""
        db = test_db_session

        # ── 创建 ──
        payload = schemas.ExpenseCreate(
            title="冒烟测试开销",
            amount=100.50,
            incurred_date=date(2025, 6, 15),
            status="待开票",
            project_name="测试项目",
            expense_type="差旅交通",
        )
        created = crud.create_expense(db, payload)
        assert created.uuuid is not None
        assert created.title == "冒烟测试开销"
        assert created.amount == 100.50

        # ── 读取 ──
        fetched = crud.get_expense_by_uuuid(db, created.uuuid)
        assert fetched is not None
        assert fetched.uuuid == created.uuuid
        assert fetched.project_name == "测试项目"

    def test_session_isolation(self, test_db_session):
        """验证不同测试之间的数据隔离：每次都应从空表开始"""
        db = test_db_session
        results = crud.get_expenses(db, skip=0, limit=10)
        # 前一个测试的数据已被回滚，此处应为空
        assert len(results) == 0


class TestFastApiClient:
    """验证 fastapi_client fixture + 依赖注入覆写"""

    def test_create_expense_api(self, fastapi_client):
        """通过 TestClient 创建开销，验证 HTTP 层到 DB 层的全链路"""
        resp = fastapi_client.post("/api/expenses/", json={
            "title": "API 冒烟测试",
            "amount": 200.00,
            "incurred_date": "2025-06-15",
            "status": "待开票",
        })
        assert resp.status_code == 201
        data = resp.json()
        assert data["title"] == "API 冒烟测试"
        assert data["amount"] == 200.00
        assert "uuuid" in data

    def test_get_expenses_empty(self, fastapi_client):
        """新会话应返回空列表（事务隔离生效）"""
        resp = fastapi_client.get("/api/expenses/")
        assert resp.status_code == 200
        assert resp.json() == []

    def test_dashboard_summary(self, fastapi_client):
        """看板汇总接口可正常访问"""
        resp = fastapi_client.get("/api/dashboard/summary")
        assert resp.status_code == 200
        data = resp.json()
        assert data["total_amount"] == 0.0
        assert data["pending_amount"] == 0.0
        assert data["invoice_count"] == 0

    def test_settings_paths(self, fastapi_client):
        """设置接口返回的路径应指向临时目录（非真实 config）"""
        resp = fastapi_client.get("/api/settings/paths")
        assert resp.status_code == 200
        data = resp.json()
        # 临时目录不包含真实项目名
        assert "api_server" not in data["db_path"]
        assert "Invoice-Management" not in data["db_path"]


class TestMockFixtures:
    """验证 Mock Fixture 行为正确"""

    def test_pdfplumber_mock(self, mock_pdfplumber):
        """验证 pdfplumber.open 已被替换为 Mock"""
        from app.utils.invoice_parser import parse_invoice_pdf
        result = parse_invoice_pdf("any_fake_path.pdf")
        assert result["invoice_type"] == "增值票"
        assert result["amount"] == 2996.00
        assert result["incurred_date"] == "2024-05-20"
        assert result["item_name"] == "*酒*汾酒精品"
        assert result["remark"] == "订单号:2007064325443298"

    def test_config_manager_patched(self, tmp_data_dir):
        """验证 config_manager 已指向临时目录"""
        from app import config_manager as cm
        cfg = cm.load_config()
        assert cfg["db_path"] == tmp_data_dir["db_path"]
        assert cfg["log_path"] == tmp_data_dir["log_path"]
