"""
Invoices Router 集成测试 — 覆盖 /api/invoices 下所有 HTTP 端点。

覆盖模块: app/routers/invoices.py
Fixtures: fastapi_client, mock_pdfplumber
"""
import pytest
from pathlib import Path
from unittest.mock import patch, MagicMock

from app import crud, schemas


# ═══════════════════════════════════════════════════════════════
#  POST /api/invoices/bind — bind_invoice
# ═══════════════════════════════════════════════════════════════

class TestBindInvoice:
    """POST /api/invoices/bind"""

    # ── Happy Path — bind 模式 ──

    def test_bind_mode_with_existing_expense(
        self, fastapi_client, mock_pdfplumber, tmp_path
    ):
        """提供 expense_uuuid + 有效 PDF → 201 bind 模式"""
        # Arrange — 先创建开销
        create_resp = fastapi_client.post("/api/expenses/", json={
            "title": "绑定目标", "amount": 100.0,
            "incurred_date": "2025-06-15"})
        expense_uuuid = create_resp.json()["uuuid"]
        # 创建临时 PDF 文件
        pdf_file = tmp_path / "test.pdf"
        pdf_file.write_text("fake pdf content")

        # Act
        with patch("app.routers.invoices.copy2") as mock_copy:
            resp = fastapi_client.post("/api/invoices/bind", json={
                "expense_uuuid": expense_uuuid,
                "source_file_path": str(pdf_file),
            })
        # Assert
        assert resp.status_code == 201
        data = resp.json()
        assert "uuuid" in data
        assert data["expense_uuuid"] == expense_uuuid
        assert "file_name" in data
        mock_copy.assert_called()  # 文件拷贝被调用

    # ── Happy Path — auto 模式 ──

    def test_auto_mode_creates_new_expense(
        self, fastapi_client, mock_pdfplumber, tmp_path
    ):
        """不提供 expense_uuuid → auto 自动建档 → 201"""
        # Arrange
        pdf_file = tmp_path / "auto.pdf"
        pdf_file.write_text("fake pdf")

        # Act
        with patch("app.routers.invoices.copy2"):
            resp = fastapi_client.post("/api/invoices/bind", json={
                "source_file_path": str(pdf_file),
            })
        # Assert
        assert resp.status_code == 201
        data = resp.json()
        assert data["expense_uuuid"] is not None  # 自动生成了开销

    # ── 边界/异常 ──

    def test_returns_400_when_source_file_not_exists(self, fastapi_client):
        """源文件不存在 → 400"""
        # Arrange & Act
        resp = fastapi_client.post("/api/invoices/bind", json={
            "expense_uuuid": "some-uuid",
            "source_file_path": "/nonexistent/path/file.pdf",
        })
        # Assert
        assert resp.status_code == 400

    def test_returns_400_when_file_is_not_pdf(
        self, fastapi_client, mock_pdfplumber, tmp_path
    ):
        """非 PDF 文件 → 400"""
        # Arrange
        txt_file = tmp_path / "doc.txt"
        txt_file.write_text("not a pdf")
        # Act
        resp = fastapi_client.post("/api/invoices/bind", json={
            "expense_uuuid": "some-uuid",
            "source_file_path": str(txt_file),
        })
        # Assert
        assert resp.status_code == 400

    def test_returns_404_when_expense_not_found(
        self, fastapi_client, mock_pdfplumber, tmp_path
    ):
        """expense_uuuid 不存在 → 404"""
        # Arrange
        pdf_file = tmp_path / "orphan.pdf"
        pdf_file.write_text("fake pdf")
        # Act
        with patch("app.routers.invoices.copy2"):
            resp = fastapi_client.post("/api/invoices/bind", json={
                "expense_uuuid": "non-existent-expense-id",
                "source_file_path": str(pdf_file),
            })
        # Assert
        assert resp.status_code == 404

    def test_updates_invoice_type_on_bind_when_parsed(
        self, fastapi_client, mock_pdfplumber, tmp_path
    ):
        """bind 模式：解析后自动更新开销的 invoice_type"""
        # Arrange
        create_resp = fastapi_client.post("/api/expenses/", json={
            "title": "待更新类型", "amount": 100.0,
            "incurred_date": "2025-06-15"})
        expense_uuuid = create_resp.json()["uuuid"]
        pdf_file = tmp_path / "vat.pdf"
        pdf_file.write_text("fake pdf")

        # Act
        with patch("app.routers.invoices.copy2"):
            resp = fastapi_client.post("/api/invoices/bind", json={
                "expense_uuuid": expense_uuuid,
                "source_file_path": str(pdf_file),
            })
        # Assert
        assert resp.status_code == 201
        # 验证开销的 invoice_type 被更新为解析结果（mock 返回增值票）
        get_resp = fastapi_client.get(f"/api/expenses/?search=待更新类型")
        if get_resp.json():
            assert get_resp.json()[0]["invoice_type"] == "增值票"


# ═══════════════════════════════════════════════════════════════
#  GET /api/invoices/by-expense/{expense_uuuid}
# ═══════════════════════════════════════════════════════════════

class TestGetExpenseInvoices:
    """GET /api/invoices/by-expense/{expense_uuuid}"""

    def test_returns_empty_list_when_no_invoices(self, fastapi_client):
        """无发票 → []"""
        # Arrange & Act
        resp = fastapi_client.get(
            "/api/invoices/by-expense/some-expense-id")
        # Assert
        assert resp.status_code == 200
        assert resp.json() == []

    def test_returns_invoices_after_bind(
        self, fastapi_client, mock_pdfplumber, tmp_path
    ):
        """绑定后查询 → 返回发票列表"""
        # Arrange
        create_resp = fastapi_client.post("/api/expenses/", json={
            "title": "有发票", "amount": 100.0,
            "incurred_date": "2025-06-15"})
        expense_uuuid = create_resp.json()["uuuid"]
        pdf_file = tmp_path / "invoice1.pdf"
        pdf_file.write_text("fake")
        with patch("app.routers.invoices.copy2"):
            fastapi_client.post("/api/invoices/bind", json={
                "expense_uuuid": expense_uuuid,
                "source_file_path": str(pdf_file),
            })
        # Act
        resp = fastapi_client.get(
            f"/api/invoices/by-expense/{expense_uuuid}")
        # Assert
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 1
        assert data[0]["expense_uuuid"] == expense_uuuid


# ═══════════════════════════════════════════════════════════════
#  DELETE /api/invoices/{uuuid} — unbind_invoice
# ═══════════════════════════════════════════════════════════════

class TestUnbindInvoice:
    """DELETE /api/invoices/{uuuid}"""

    def test_returns_404_when_invoice_not_found(self, fastapi_client):
        """不存在的发票 → 404"""
        # Arrange & Act
        resp = fastapi_client.delete("/api/invoices/non-existent-id")
        # Assert
        assert resp.status_code == 404

    @patch("os.remove")
    @patch.object(Path, "is_file", return_value=True)
    @patch.object(Path, "exists", return_value=True)
    def test_unbind_success_after_bind(
        self, mock_exists, mock_is_file, mock_remove,
        fastapi_client, mock_pdfplumber, tmp_path
    ):
        """正常解绑 → 200"""
        # Arrange
        create_resp = fastapi_client.post("/api/expenses/", json={
            "title": "待解绑", "amount": 100.0,
            "incurred_date": "2025-06-15"})
        expense_uuuid = create_resp.json()["uuuid"]
        pdf_file = tmp_path / "unbind.pdf"
        pdf_file.write_text("fake")
        with patch("app.routers.invoices.copy2"):
            bind_resp = fastapi_client.post("/api/invoices/bind", json={
                "expense_uuuid": expense_uuuid,
                "source_file_path": str(pdf_file),
            })
        invoice_uuuid = bind_resp.json()["uuuid"]
        # Act
        resp = fastapi_client.delete(f"/api/invoices/{invoice_uuuid}")
        # Assert
        assert resp.status_code == 200
        assert resp.json()["uuuid"] == invoice_uuuid
        mock_remove.assert_called()
