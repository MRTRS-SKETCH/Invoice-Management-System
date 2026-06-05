"""
ORM 模型单元测试 — 验证表结构、列定义、generate_uuuid 唯一性。

覆盖模块: app/models.py
Fixtures: 无（纯模型验证）
"""
import pytest
from sqlalchemy import inspect

from app import models
from app.database import Base


# ═══════════════════════════════════════════════════════════════
#  generate_uuuid
# ═══════════════════════════════════════════════════════════════

class TestGenerateUuuid:
    """generate_uuuid 主键生成函数"""

    def test_returns_string(self):
        """返回值为字符串"""
        # Arrange & Act
        uuuid = models.generate_uuuid()
        # Assert
        assert isinstance(uuuid, str)

    def test_is_uuid4_format(self):
        """返回值符合 UUID4 格式（36 字符，含 4 个连字符）"""
        # Arrange & Act
        uuuid = models.generate_uuuid()
        # Assert
        assert len(uuuid) == 36
        assert uuuid.count("-") == 4

    def test_generates_unique_values(self):
        """连续生成不重复"""
        # Arrange & Act
        ids = {models.generate_uuuid() for _ in range(100)}
        # Assert
        assert len(ids) == 100

    def test_follows_uuid4_version_indicator(self):
        """UUID v4 的版本位为 4（第 15 个字符）"""
        # Arrange & Act
        uuuid = models.generate_uuuid()
        version_char = uuuid.split("-")[2][0]
        # Assert
        assert version_char == "4"


# ═══════════════════════════════════════════════════════════════
#  ExpenseRecord 模型
# ═══════════════════════════════════════════════════════════════

class TestExpenseRecord:
    """ExpenseRecord ORM 模型"""

    def test_table_name_is_expenses(self):
        """表名为 'expenses'"""
        # Assert
        assert models.ExpenseRecord.__tablename__ == "expenses"

    def test_uuuid_is_primary_key_with_index(self):
        """uuuid 列为主键且已索引"""
        # Arrange
        cols = inspect(models.ExpenseRecord).columns
        uuuid_col = cols["uuuid"]
        # Assert
        assert uuuid_col.primary_key is True
        assert uuuid_col.index is True

    def test_title_is_non_nullable(self):
        """title 列不可为空"""
        # Arrange
        cols = inspect(models.ExpenseRecord).columns
        # Assert
        assert cols["title"].nullable is False

    def test_amount_is_float_type(self):
        """amount 列为 Float 类型"""
        # Arrange
        cols = inspect(models.ExpenseRecord).columns
        # Assert
        from sqlalchemy import Float
        assert isinstance(cols["amount"].type, Float)

    def test_incurred_date_has_index(self):
        """incurred_date 列已索引"""
        # Arrange
        cols = inspect(models.ExpenseRecord).columns
        # Assert
        assert cols["incurred_date"].index is True

    def test_status_has_default_value(self):
        """status 默认值为 '待开票'"""
        # Arrange
        cols = inspect(models.ExpenseRecord).columns
        # Assert
        assert cols["status"].default.arg == "待开票"

    def test_status_has_index(self):
        """status 列已索引"""
        # Arrange
        cols = inspect(models.ExpenseRecord).columns
        # Assert
        assert cols["status"].index is True

    def test_project_name_is_nullable(self):
        """project_name 可为空"""
        # Arrange
        cols = inspect(models.ExpenseRecord).columns
        # Assert
        assert cols["project_name"].nullable is True

    def test_has_blocked_from_status_column(self):
        """包含 blocked_from_status 列（屏蔽旁路）"""
        # Arrange
        cols = inspect(models.ExpenseRecord).columns
        # Assert
        assert "blocked_from_status" in cols

    def test_all_expected_columns_exist(self):
        """验证所有预期列均存在"""
        # Arrange
        cols = inspect(models.ExpenseRecord).columns
        expected = {
            "uuuid", "title", "amount", "incurred_date", "status",
            "submit_date", "complete_date", "actual_reimbursed_amount",
            "has_company_invoice", "project_name", "expense_type",
            "invoice_type", "remark", "related_persons",
            "blocked_from_status",
        }
        # Assert
        assert set(cols.keys()) == expected


# ═══════════════════════════════════════════════════════════════
#  InvoiceRecord 模型
# ═══════════════════════════════════════════════════════════════

class TestInvoiceRecord:
    """InvoiceRecord ORM 模型"""

    def test_table_name_is_invoices(self):
        """表名为 'invoices'"""
        # Assert
        assert models.InvoiceRecord.__tablename__ == "invoices"

    def test_expense_uuuid_is_indexed(self):
        """expense_uuuid 列已索引（高频关联查询）"""
        # Arrange
        cols = inspect(models.InvoiceRecord).columns
        # Assert
        assert cols["expense_uuuid"].index is True

    def test_expense_uuuid_is_non_nullable(self):
        """expense_uuuid 不可为空"""
        # Arrange
        cols = inspect(models.InvoiceRecord).columns
        # Assert
        assert cols["expense_uuuid"].nullable is False

    def test_created_at_has_default_now(self):
        """created_at 默认值为 func.now()"""
        # Arrange
        cols = inspect(models.InvoiceRecord).columns
        # Assert
        assert cols["created_at"].default is not None

    def test_all_expected_columns_exist(self):
        """验证所有预期列均存在"""
        # Arrange
        cols = inspect(models.InvoiceRecord).columns
        expected = {
            "uuuid", "expense_uuuid", "file_name", "saved_path",
            "created_at",
        }
        # Assert
        assert set(cols.keys()) == expected
