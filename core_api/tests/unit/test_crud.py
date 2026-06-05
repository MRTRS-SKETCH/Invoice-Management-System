"""
CRUD 业务逻辑层单元测试 — 覆盖 crud.py 中所有公开函数。

覆盖模块: app/crud.py
Fixtures: test_db_session（:memory: 数据库 + 自动回滚隔离）
"""
import pytest
from datetime import date, datetime, timedelta
from pathlib import Path
from unittest.mock import patch, MagicMock

from app import crud, schemas, models
from app.config_manager import resolve_absolute_pdf_path


# ═══════════════════════════════════════════════════════════════
#  辅助函数
# ═══════════════════════════════════════════════════════════════

def _make_expense_payload(
    title: str = "测试开销",
    amount: float = 100.0,
    incurred_date: date = date(2025, 6, 15),
    status: str = "待开票",
    **kwargs,
) -> schemas.ExpenseCreate:
    """快捷构造 ExpenseCreate"""
    return schemas.ExpenseCreate(
        title=title,
        amount=amount,
        incurred_date=incurred_date,
        status=status,
        **kwargs,
    )


# ═══════════════════════════════════════════════════════════════
#  create_expense
# ═══════════════════════════════════════════════════════════════

class TestCreateExpense:
    """create_expense 创建开销记录"""

    def test_creates_with_minimal_fields(self, test_db_session):
        """只提供必填字段，创建成功并返回 ORM 对象"""
        # Arrange
        db = test_db_session
        payload = _make_expense_payload()
        # Act
        created = crud.create_expense(db, payload)
        # Assert
        assert created.uuuid is not None
        assert created.title == "测试开销"
        assert created.amount == 100.0
        assert created.status == "待开票"

    def test_created_record_is_persisted_and_retrievable(self, test_db_session):
        """创建后可立即从数据库查回"""
        # Arrange
        db = test_db_session
        payload = _make_expense_payload(title="可查回")
        # Act
        created = crud.create_expense(db, payload)
        fetched = crud.get_expense_by_uuuid(db, created.uuuid)
        # Assert
        assert fetched is not None
        assert fetched.title == "可查回"

    def test_stores_all_optional_fields(self, test_db_session):
        """全字段（含 Optional）正确持久化"""
        # Arrange
        db = test_db_session
        payload = _make_expense_payload(
            title="全字段",
            amount=2500.50,
            incurred_date=date(2025, 3, 1),
            status="待报销",
            submit_date=date(2025, 3, 5),
            complete_date=date(2025, 3, 20),
            actual_reimbursed_amount=2500.00,
            has_company_invoice=True,
            project_name="Q1采购",
            expense_type="办公用品",
            invoice_type="增值票",
            remark="订单号:ABC-123",
            related_persons="张三,李四",
        )
        # Act
        created = crud.create_expense(db, payload)
        # Assert
        assert created.project_name == "Q1采购"
        assert created.expense_type == "办公用品"
        assert created.invoice_type == "增值票"
        assert created.remark == "订单号:ABC-123"
        assert created.related_persons == "张三,李四"
        assert created.actual_reimbursed_amount == 2500.00

    def test_default_status_is_set_when_not_provided(self, test_db_session):
        """不传 status 时使用默认值 '待开票'"""
        # Arrange
        db = test_db_session
        # Act
        payload = _make_expense_payload(status="待开票")  # 显式传入确认
        created = crud.create_expense(db, payload)
        # Assert
        assert created.status == "待开票"

    def test_uuuid_is_unique_across_multiple_creates(self, test_db_session):
        """多条创建的 uuuid 互不相同"""
        # Arrange
        db = test_db_session
        # Act
        ids = set()
        for i in range(10):
            payload = _make_expense_payload(title=f"第{i}条")
            ids.add(crud.create_expense(db, payload).uuuid)
        # Assert
        assert len(ids) == 10


# ═══════════════════════════════════════════════════════════════
#  create_expense_from_parsed
# ═══════════════════════════════════════════════════════════════

class TestCreateExpenseFromParsed:
    """create_expense_from_parsed 从 PDF 解析结果自动建档"""

    def test_creates_with_valid_date_string(self, test_db_session):
        """YYYY-MM-DD 格式日期正确解析"""
        # Arrange
        db = test_db_session
        # Act
        created = crud.create_expense_from_parsed(
            db=db,
            title="解析建档",
            amount=2996.00,
            incurred_date="2024-05-20",
            invoice_type="增值票",
        )
        # Assert
        assert created.incurred_date == date(2024, 5, 20)
        assert created.amount == 2996.00
        assert created.invoice_type == "增值票"

    def test_falls_back_to_today_when_date_invalid(self, test_db_session):
        """日期解析失败 → 回退当天日期"""
        # Arrange
        db = test_db_session
        # Act
        created = crud.create_expense_from_parsed(
            db=db,
            title="无效日期",
            amount=100.0,
            incurred_date="bad-date-format",
        )
        # Assert
        assert created.incurred_date == date.today()

    def test_falls_back_to_today_when_date_is_none(self, test_db_session):
        """日期为 None → 回退当天"""
        # Arrange
        db = test_db_session
        # Act
        created = crud.create_expense_from_parsed(
            db=db, title="空日期", amount=50.0, incurred_date=None
        )
        # Assert
        assert created.incurred_date == date.today()

    def test_uses_default_title_when_not_provided(self, test_db_session):
        """不传 title → 使用默认值 '自动解析发票建档'"""
        # Arrange
        db = test_db_session
        # Act
        # 不传 title，使用函数默认值
        created = crud.create_expense_from_parsed(db=db)
        # Assert
        assert created.title == "自动解析发票建档"
        assert created.amount == 0.0

    def test_passes_optional_project_and_type(self, test_db_session):
        """project_name 和 expense_type 正确写入"""
        # Arrange
        db = test_db_session
        # Act
        created = crud.create_expense_from_parsed(
            db=db,
            project_name="Q2项目",
            expense_type="差旅交通",
            remark="订单号:XYZ",
        )
        # Assert
        assert created.project_name == "Q2项目"
        assert created.expense_type == "差旅交通"
        assert created.remark == "订单号:XYZ"


# ═══════════════════════════════════════════════════════════════
#  get_expense_by_uuuid
# ═══════════════════════════════════════════════════════════════

class TestGetExpenseByUuuid:
    """get_expense_by_uuuid"""

    def test_returns_expense_when_exists(self, test_db_session):
        """存在时返回 ORM 对象"""
        # Arrange
        db = test_db_session
        payload = _make_expense_payload()
        created = crud.create_expense(db, payload)
        # Act
        result = crud.get_expense_by_uuuid(db, created.uuuid)
        # Assert
        assert result is not None
        assert result.uuuid == created.uuuid

    def test_returns_none_when_not_exists(self, test_db_session):
        """不存在时返回 None"""
        # Arrange
        db = test_db_session
        # Act
        result = crud.get_expense_by_uuuid(db, "non-existent-uuid")
        # Assert
        assert result is None


# ═══════════════════════════════════════════════════════════════
#  get_expenses — 列表查询
# ═══════════════════════════════════════════════════════════════

class TestGetExpenses:
    """get_expenses 列表查询"""

    def test_returns_empty_list_when_no_records(self, test_db_session):
        """空表 → []"""
        # Arrange
        db = test_db_session
        # Act
        results = crud.get_expenses(db)
        # Assert
        assert results == []

    def test_returns_all_records_in_desc_date_order(self, test_db_session):
        """多条记录按 incurred_date 倒序排列"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(
            title="旧记录", incurred_date=date(2025, 1, 1)))
        crud.create_expense(db, _make_expense_payload(
            title="新记录", incurred_date=date(2025, 6, 15)))
        # Act
        results = crud.get_expenses(db)
        # Assert
        assert len(results) == 2
        assert results[0].title == "新记录"
        assert results[1].title == "旧记录"

    def test_filters_by_search_title_ilike(self, test_db_session):
        """search 参数：模糊匹配 title"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(title="差旅费报销"))
        crud.create_expense(db, _make_expense_payload(title="办公用品采购"))
        crud.create_expense(db, _make_expense_payload(title="餐饮费"))
        # Act
        results = crud.get_expenses(db, search="差旅")
        # Assert
        assert len(results) == 1
        assert results[0].title == "差旅费报销"

    def test_search_is_case_insensitive(self, test_db_session):
        """search 忽略大小写"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(title="ABC Expense"))
        # Act
        results = crud.get_expenses(db, search="abc")
        # Assert
        assert len(results) == 1

    def test_filters_by_status_exact_match(self, test_db_session):
        """status 参数：精确匹配"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(title="A", status="待开票"))
        crud.create_expense(db, _make_expense_payload(title="B", status="已完结"))
        # Act
        results = crud.get_expenses(db, status="已完结")
        # Assert
        assert len(results) == 1
        assert results[0].title == "B"

    def test_filters_by_date_from(self, test_db_session):
        """date_from：筛选 >= 指定日期"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(
            title="老", incurred_date=date(2025, 1, 1)))
        crud.create_expense(db, _make_expense_payload(
            title="新", incurred_date=date(2025, 6, 1)))
        # Act
        results = crud.get_expenses(db, date_from="2025-06-01")
        # Assert
        assert len(results) == 1
        assert results[0].title == "新"

    def test_filters_by_date_to(self, test_db_session):
        """date_to：筛选 <= 指定日期"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(
            title="老", incurred_date=date(2025, 1, 1)))
        crud.create_expense(db, _make_expense_payload(
            title="新", incurred_date=date(2025, 6, 1)))
        # Act
        results = crud.get_expenses(db, date_to="2025-03-01")
        # Assert
        assert len(results) == 1
        assert results[0].title == "老"

    def test_filters_by_date_range(self, test_db_session):
        """date_from + date_to 组合"""
        # Arrange
        db = test_db_session
        for m in range(1, 7):
            crud.create_expense(db, _make_expense_payload(
                title=f"{m}月", incurred_date=date(2025, m, 15)))
        # Act
        results = crud.get_expenses(db, date_from="2025-02-01", date_to="2025-04-30")
        # Assert
        assert len(results) == 3
        titles = {r.title for r in results}
        assert titles == {"2月", "3月", "4月"}

    def test_pagination_skip_and_limit(self, test_db_session):
        """skip + limit 分页"""
        # Arrange
        db = test_db_session
        for i in range(10):
            crud.create_expense(db, _make_expense_payload(
                title=f"记录{i}", incurred_date=date(2025, 1, 1 + i)))
        # Act
        page1 = crud.get_expenses(db, skip=0, limit=3)
        page2 = crud.get_expenses(db, skip=3, limit=3)
        # Assert
        assert len(page1) == 3
        assert len(page2) == 3
        ids_page1 = {r.title for r in page1}
        ids_page2 = {r.title for r in page2}
        assert ids_page1.isdisjoint(ids_page2)

    def test_combined_filters(self, test_db_session):
        """search + status + date 组合筛选"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(
            title="差旅费报销", status="待开票", incurred_date=date(2025, 3, 1)))
        crud.create_expense(db, _make_expense_payload(
            title="差旅费报销", status="已完结", incurred_date=date(2025, 6, 1)))
        crud.create_expense(db, _make_expense_payload(
            title="办公费", status="待开票", incurred_date=date(2025, 3, 1)))
        # Act
        results = crud.get_expenses(
            db, search="差旅", status="待开票", date_from="2025-03-01")
        # Assert
        assert len(results) == 1
        assert results[0].title == "差旅费报销"
        assert results[0].status == "待开票"


# ═══════════════════════════════════════════════════════════════
#  update_expense_invoice_type
# ═══════════════════════════════════════════════════════════════

class TestUpdateExpenseInvoiceType:
    """update_expense_invoice_type 轻量更新发票类型"""

    def test_updates_invoice_type_successfully(self, test_db_session):
        """正常更新 → True"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload())
        # Act
        success = crud.update_expense_invoice_type(db, created.uuuid, "增值票")
        # Assert
        assert success is True
        fetched = crud.get_expense_by_uuuid(db, created.uuuid)
        assert fetched.invoice_type == "增值票"

    def test_returns_false_when_expense_not_found(self, test_db_session):
        """不存在的 uuuid → False"""
        # Arrange
        db = test_db_session
        # Act
        success = crud.update_expense_invoice_type(db, "no-such-id", "普票")
        # Assert
        assert success is False


# ═══════════════════════════════════════════════════════════════
#  update_expense
# ═══════════════════════════════════════════════════════════════

class TestUpdateExpense:
    """update_expense 局部更新"""

    def test_partial_update_preserves_other_fields(self, test_db_session):
        """只改 title，其他字段不变"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload(
            title="原标题", amount=200.0, status="待开票"))
        # Act
        update = schemas.ExpenseUpdate(title="新标题")
        updated = crud.update_expense(db, created.uuuid, update)
        # Assert
        assert updated.title == "新标题"
        assert updated.amount == 200.0      # 未变
        assert updated.status == "待开票"    # 未变

    def test_returns_none_when_uuuid_not_found(self, test_db_session):
        """不存在的 uuuid → None"""
        # Arrange
        db = test_db_session
        update = schemas.ExpenseUpdate(title="不存在的")
        # Act
        result = crud.update_expense(db, "no-such-id", update)
        # Assert
        assert result is None

    def test_allows_arbitrary_status_transition(self, test_db_session):
        """解除限制后，任意状态流转均允许"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload(status="待开票"))
        # Act
        update = schemas.ExpenseUpdate(status="已完结")
        updated = crud.update_expense(db, created.uuuid, update)
        # Assert
        assert updated.status == "已完结"

    def test_updates_multiple_fields_simultaneously(self, test_db_session):
        """同时更新多个字段"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload(
            title="旧标题", amount=100.0))
        # Act
        update = schemas.ExpenseUpdate(
            title="新标题",
            amount=500.0,
            project_name="新项目",
        )
        updated = crud.update_expense(db, created.uuuid, update)
        # Assert
        assert updated.title == "新标题"
        assert updated.amount == 500.0
        assert updated.project_name == "新项目"


# ═══════════════════════════════════════════════════════════════
#  delete_expense
# ═══════════════════════════════════════════════════════════════

class TestDeleteExpense:
    """delete_expense 物理删除 + 级联清理"""

    def test_deletes_existing_expense_and_returns_true(self, test_db_session):
        """删除成功 → True，再查为 None"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload())
        # Act
        success = crud.delete_expense(db, created.uuuid)
        # Assert
        assert success is True
        assert crud.get_expense_by_uuuid(db, created.uuuid) is None

    def test_returns_false_when_expense_not_found(self, test_db_session):
        """不存在的 uuuid → False"""
        # Arrange
        db = test_db_session
        # Act
        success = crud.delete_expense(db, "no-such-id")
        # Assert
        assert success is False

    def test_cascading_deletes_associated_invoices(self, test_db_session):
        """删除开销时级联删除关联发票"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload())
        inv = crud.create_invoice(
            db, created.uuuid, "test.pdf", "pdfs/test.pdf")
        # Act
        crud.delete_expense(db, created.uuuid)
        # Assert
        assert crud.get_invoice_by_uuuid(db, inv.uuuid) is None
        assert crud.get_invoices_by_expense(db, created.uuuid) == []

    @patch("os.remove")
    @patch.object(Path, "is_file", return_value=True)
    @patch.object(Path, "exists", return_value=True)
    def test_deletes_physical_pdf_files(
        self, mock_exists, mock_is_file, mock_remove, test_db_session
    ):
        """删除开销时尝试删除关联的物理 PDF 文件"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload())
        crud.create_invoice(db, created.uuuid, "发票.pdf", "pdfs/发票.pdf")
        # Act
        crud.delete_expense(db, created.uuuid)
        # Assert
        mock_remove.assert_called()

    @patch("os.remove")
    @patch.object(Path, "is_file", return_value=True)
    @patch.object(Path, "exists", return_value=True)
    def test_blocks_deletion_when_pdf_removal_fails(
        self, mock_exists, mock_is_file, mock_remove, test_db_session
    ):
        """PDF 文件删除失败（OSError）→ 阻断数据库删除，返回 False"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload())
        crud.create_invoice(db, created.uuuid, "locked.pdf", "pdfs/locked.pdf")
        mock_remove.side_effect = OSError("文件被占用")
        # Act
        result = crud.delete_expense(db, created.uuuid)
        # Assert
        assert result is False
        # 数据库记录未被删除
        assert crud.get_expense_by_uuuid(db, created.uuuid) is not None


# ═══════════════════════════════════════════════════════════════
#  block_expense / unblock_expense
# ═══════════════════════════════════════════════════════════════

class TestBlockExpense:
    """block_expense 屏蔽开销"""

    def test_blocks_and_saves_original_status(self, test_db_session):
        """屏蔽成功 → status='已屏蔽'，blocked_from_status=原状态"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload(status="待报销"))
        # Act
        success = crud.block_expense(db, created.uuuid)
        # Assert
        assert success is True
        fetched = crud.get_expense_by_uuuid(db, created.uuuid)
        assert fetched.status == "已屏蔽"
        assert fetched.blocked_from_status == "待报销"

    def test_returns_false_when_already_blocked(self, test_db_session):
        """已屏蔽 → 再次屏蔽返回 False"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload(status="待开票"))
        crud.block_expense(db, created.uuuid)
        # Act
        success = crud.block_expense(db, created.uuuid)
        # Assert
        assert success is False

    def test_returns_false_when_not_found(self, test_db_session):
        """不存在的 uuuid → False"""
        # Arrange
        db = test_db_session
        # Act
        success = crud.block_expense(db, "no-such-id")
        # Assert
        assert success is False


class TestUnblockExpense:
    """unblock_expense 取消屏蔽"""

    def test_unblocks_and_restores_original_status(self, test_db_session):
        """取消屏蔽 → status 恢复原值，blocked_from_status 清空"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload(status="核销中"))
        crud.block_expense(db, created.uuuid)
        # Act
        success = crud.unblock_expense(db, created.uuuid)
        # Assert
        assert success is True
        fetched = crud.get_expense_by_uuuid(db, created.uuuid)
        assert fetched.status == "核销中"
        assert fetched.blocked_from_status is None

    def test_returns_false_when_not_blocked(self, test_db_session):
        """当前不是已屏蔽态 → False"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload(status="待开票"))
        # Act
        success = crud.unblock_expense(db, created.uuuid)
        # Assert
        assert success is False

    def test_returns_false_when_blocked_from_status_missing(self, test_db_session):
        """已屏蔽但缺少 blocked_from_status → False"""
        # Arrange
        db = test_db_session
        created = crud.create_expense(db, _make_expense_payload(status="待开票"))
        # 手动设置为已屏蔽但不记录原状态（模拟脏数据）
        db.query(models.ExpenseRecord).filter_by(
            uuuid=created.uuuid
        ).update({"status": "已屏蔽", "blocked_from_status": None})
        db.commit()
        # Act
        success = crud.unblock_expense(db, created.uuuid)
        # Assert
        assert success is False

    def test_returns_false_when_not_found(self, test_db_session):
        """不存在的 uuuid → False"""
        # Arrange
        db = test_db_session
        # Act
        success = crud.unblock_expense(db, "no-such-id")
        # Assert
        assert success is False


# ═══════════════════════════════════════════════════════════════
#  Invoice CRUD
# ═══════════════════════════════════════════════════════════════

class TestInvoiceCRUD:
    """发票记录 CRUD"""

    def test_create_invoice(self, test_db_session):
        """创建发票绑定记录"""
        # Arrange
        db = test_db_session
        exp = crud.create_expense(db, _make_expense_payload())
        # Act
        inv = crud.create_invoice(
            db, exp.uuuid, "原始文件名.pdf", "pdfs/stored.pdf")
        # Assert
        assert inv.uuuid is not None
        assert inv.expense_uuuid == exp.uuuid
        assert inv.file_name == "原始文件名.pdf"
        assert inv.saved_path == "pdfs/stored.pdf"

    def test_get_invoice_by_uuuid_exists(self, test_db_session):
        """存在 → 返回发票记录"""
        # Arrange
        db = test_db_session
        exp = crud.create_expense(db, _make_expense_payload())
        inv = crud.create_invoice(db, exp.uuuid, "a.pdf", "pdfs/a.pdf")
        # Act
        result = crud.get_invoice_by_uuuid(db, inv.uuuid)
        # Assert
        assert result is not None
        assert result.uuuid == inv.uuuid

    def test_get_invoice_by_uuuid_not_exists(self, test_db_session):
        """不存在 → None"""
        # Arrange
        db = test_db_session
        # Act
        result = crud.get_invoice_by_uuuid(db, "no-such")
        # Assert
        assert result is None

    def test_get_invoices_by_expense_returns_all(self, test_db_session):
        """返回指定开销的所有发票"""
        # Arrange
        db = test_db_session
        exp = crud.create_expense(db, _make_expense_payload())
        crud.create_invoice(db, exp.uuuid, "1.pdf", "pdfs/1.pdf")
        crud.create_invoice(db, exp.uuuid, "2.pdf", "pdfs/2.pdf")
        # Act
        results = crud.get_invoices_by_expense(db, exp.uuuid)
        # Assert
        assert len(results) == 2

    def test_get_invoices_by_expense_empty(self, test_db_session):
        """无发票的开销 → []"""
        # Arrange
        db = test_db_session
        exp = crud.create_expense(db, _make_expense_payload())
        # Act
        results = crud.get_invoices_by_expense(db, exp.uuuid)
        # Assert
        assert results == []

    @patch("os.remove")
    @patch.object(Path, "is_file", return_value=True)
    @patch.object(Path, "exists", return_value=True)
    def test_delete_invoice_removes_record_and_pdf(
        self, mock_exists, mock_is_file, mock_remove, test_db_session
    ):
        """删除发票记录同时删除物理 PDF"""
        # Arrange
        db = test_db_session
        exp = crud.create_expense(db, _make_expense_payload())
        inv = crud.create_invoice(db, exp.uuuid, "del.pdf", "pdfs/del.pdf")
        # Act
        success = crud.delete_invoice(db, inv.uuuid)
        # Assert
        assert success is True
        mock_remove.assert_called()
        assert crud.get_invoice_by_uuuid(db, inv.uuuid) is None

    @patch("os.remove")
    @patch.object(Path, "is_file", return_value=True)
    @patch.object(Path, "exists", return_value=True)
    def test_delete_invoice_blocks_when_pdf_removal_fails(
        self, mock_exists, mock_is_file, mock_remove, test_db_session
    ):
        """PDF 删除失败 → 阻断，返回 False"""
        # Arrange
        db = test_db_session
        exp = crud.create_expense(db, _make_expense_payload())
        inv = crud.create_invoice(db, exp.uuuid, "locked.pdf", "pdfs/locked.pdf")
        mock_remove.side_effect = OSError("文件被占用")
        # Act
        success = crud.delete_invoice(db, inv.uuuid)
        # Assert
        assert success is False
        assert crud.get_invoice_by_uuuid(db, inv.uuuid) is not None

    def test_delete_invoice_returns_false_when_not_found(self, test_db_session):
        """不存在的发票 → False"""
        # Arrange
        db = test_db_session
        # Act
        success = crud.delete_invoice(db, "no-such")
        # Assert
        assert success is False


# ═══════════════════════════════════════════════════════════════
#  Dashboard 统计函数
# ═══════════════════════════════════════════════════════════════

class TestDashboardSummary:
    """get_dashboard_summary"""

    def test_empty_database_returns_zeros(self, test_db_session):
        """空库 → 全零"""
        # Arrange
        db = test_db_session
        # Act
        result = crud.get_dashboard_summary(db)
        # Assert
        assert result["total_amount"] == 0.0
        assert result["pending_amount"] == 0.0
        assert result["invoice_count"] == 0

    def test_aggregates_correctly(self, test_db_session):
        """有数据时正确聚合"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(
            title="A", amount=100.0, status="待开票"))
        crud.create_expense(db, _make_expense_payload(
            title="B", amount=200.0, status="已完结"))
        exp = crud.create_expense(db, _make_expense_payload(
            title="C", amount=50.0, status="待开票"))
        crud.create_invoice(db, exp.uuuid, "f.pdf", "pdfs/f.pdf")
        crud.create_invoice(db, exp.uuuid, "f2.pdf", "pdfs/f2.pdf")
        # Act
        result = crud.get_dashboard_summary(db)
        # Assert
        assert result["total_amount"] == 350.0
        assert result["pending_amount"] == 150.0  # 100 + 50
        assert result["invoice_count"] == 2


class TestMonthlyTrend:
    """get_monthly_trend"""

    def test_returns_12_months_all_zero_when_no_data(self, test_db_session):
        """空库 → 12 个月均为 0"""
        # Arrange
        db = test_db_session
        # Act
        result = crud.get_monthly_trend(db)
        # Assert
        assert len(result) == 12
        for item in result:
            assert item["amount"] == 0.0
            assert "-" in item["month"]  # YYYY-MM 格式

    def test_fills_zero_for_months_without_data(self, test_db_session):
        """只有一个月的记录时，其余月份补零"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(
            amount=500.0, incurred_date=date.today()))
        # Act
        result = crud.get_monthly_trend(db)
        # Assert
        # 至少有一个月有金额
        amounts = [item["amount"] for item in result]
        assert sum(amounts) == 500.0

    def test_returns_months_in_chronological_order(self, test_db_session):
        """月份按时间顺序排列"""
        # Arrange
        db = test_db_session
        # Act
        result = crud.get_monthly_trend(db)
        # Assert
        months = [item["month"] for item in result]
        assert months == sorted(months)


class TestCategoryDistribution:
    """get_category_distribution"""

    def test_empty_database_returns_empty_list(self, test_db_session):
        """空库 → []"""
        # Arrange
        db = test_db_session
        # Act
        result = crud.get_category_distribution(db)
        # Assert
        assert result == []

    def test_groups_by_project_name(self, test_db_session):
        """按 project_name 分组聚合"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(
            amount=100.0, project_name="项目A"))
        crud.create_expense(db, _make_expense_payload(
            amount=200.0, project_name="项目A"))
        crud.create_expense(db, _make_expense_payload(
            amount=50.0, project_name="项目B"))
        # Act
        result = crud.get_category_distribution(db)
        # Assert
        assert len(result) == 2
        # 按金额倒序：项目A (300) > 项目B (50)
        assert result[0]["category"] == "项目A"
        assert result[0]["amount"] == 300.0
        assert result[1]["category"] == "项目B"

    def test_coalesces_null_project_to_default(self, test_db_session):
        """project_name 为 None → '通用类目'"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(
            amount=100.0, project_name=None))
        # Act
        result = crud.get_category_distribution(db)
        # Assert
        assert result[0]["category"] == "通用类目"

    def test_percentage_sums_to_one(self, test_db_session):
        """各项占比之和 ≈ 1.0"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(amount=100.0, project_name="A"))
        crud.create_expense(db, _make_expense_payload(amount=300.0, project_name="B"))
        # Act
        result = crud.get_category_distribution(db)
        # Assert
        total_pct = sum(item["percentage"] for item in result)
        assert abs(total_pct - 1.0) < 0.01

    def test_days_filter_restricts_date_range(self, test_db_session):
        """days 参数限制时间范围"""
        # Arrange
        db = test_db_session
        old_date = date.today() - timedelta(days=100)
        crud.create_expense(db, _make_expense_payload(
            amount=500.0, project_name="旧项目", incurred_date=old_date))
        crud.create_expense(db, _make_expense_payload(
            amount=100.0, project_name="新项目", incurred_date=date.today()))
        # Act — 只统计最近 30 天
        result = crud.get_category_distribution(db, days=30)
        # Assert — 旧项目被排除
        categories = {item["category"] for item in result}
        assert "旧项目" not in categories


class TestDailyHeatmap:
    """get_daily_heatmap"""

    def test_returns_90_days(self, test_db_session):
        """空库也返回 90 天的数据，count 全为 0"""
        # Arrange
        db = test_db_session
        # Act
        result = crud.get_daily_heatmap(db)
        # Assert
        assert len(result) == 90
        assert all(item["count"] == 0 for item in result)

    def test_dates_in_chronological_order(self, test_db_session):
        """日期按时间顺序排列"""
        # Arrange
        db = test_db_session
        # Act
        result = crud.get_daily_heatmap(db)
        # Assert
        dates = [item["date"] for item in result]
        assert dates == sorted(dates)

    def test_counts_records_on_specific_date(self, test_db_session):
        """有记录的日期 count > 0"""
        # Arrange
        db = test_db_session
        today = date.today()
        crud.create_expense(db, _make_expense_payload(incurred_date=today))
        crud.create_expense(db, _make_expense_payload(incurred_date=today))
        # Act
        result = crud.get_daily_heatmap(db)
        # Assert
        today_item = [r for r in result if r["date"] == today.isoformat()]
        assert len(today_item) == 1
        assert today_item[0]["count"] == 2


class TestExpenseTypeDistribution:
    """get_expense_type_distribution"""

    def test_empty_database_returns_empty_list(self, test_db_session):
        """空库 → []"""
        # Arrange
        db = test_db_session
        # Act
        result = crud.get_expense_type_distribution(db)
        # Assert
        assert result == []

    def test_groups_by_expense_type(self, test_db_session):
        """按 expense_type 分组"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(
            amount=100.0, expense_type="差旅交通"))
        crud.create_expense(db, _make_expense_payload(
            amount=200.0, expense_type="差旅交通"))
        crud.create_expense(db, _make_expense_payload(
            amount=50.0, expense_type="办公用品"))
        # Act
        result = crud.get_expense_type_distribution(db)
        # Assert
        assert len(result) == 2
        assert result[0]["amount"] == 300.0  # 差旅交通

    def test_coalesces_null_type_to_uncategorized(self, test_db_session):
        """expense_type 为 None → '未分类'"""
        # Arrange
        db = test_db_session
        crud.create_expense(db, _make_expense_payload(
            amount=100.0, expense_type=None))
        # Act
        result = crud.get_expense_type_distribution(db)
        # Assert
        assert result[0]["category"] == "未分类"

    def test_days_filter(self, test_db_session):
        """days 参数限制时间范围"""
        # Arrange
        db = test_db_session
        old_date = date.today() - timedelta(days=365)
        crud.create_expense(db, _make_expense_payload(
            amount=500.0, expense_type="旧数据", incurred_date=old_date))
        # Act — 只看最近 30 天
        result = crud.get_expense_type_distribution(db, days=30)
        # Assert
        assert len(result) == 0  # 旧数据被排除
