"""
Pydantic Schema 模型校验测试 — 验证请求/响应模型的字段约束、默认值、边界值行为。

覆盖模块: app/schemas.py
Fixtures: 无（纯逻辑，不涉及 I/O）
"""
import pytest
from datetime import date
from pydantic import ValidationError

from app import schemas


# ═══════════════════════════════════════════════════════════════
#  ExpenseCreate
# ═══════════════════════════════════════════════════════════════

class TestExpenseCreate:
    """ExpenseCreate 请求体校验"""

    # ── Happy Path ──

    def test_creates_with_minimal_required_fields(self):
        """仅传必填字段即可成功创建"""
        # Arrange & Act
        obj = schemas.ExpenseCreate(
            title="测试开销",
            amount=100.0,
            incurred_date=date(2025, 6, 15),
        )
        # Assert
        assert obj.title == "测试开销"
        assert obj.amount == 100.0
        assert obj.incurred_date == date(2025, 6, 15)
        assert obj.status == "待开票"          # 默认值
        assert obj.invoice_type == "备注"      # 默认值

    def test_creates_with_all_fields(self):
        """全字段传入，无遗漏"""
        # Arrange & Act
        obj = schemas.ExpenseCreate(
            title="全字段开销",
            amount=2500.50,
            incurred_date=date(2025, 3, 1),
            status="待报销",
            submit_date=date(2025, 3, 5),
            complete_date=date(2025, 3, 20),
            actual_reimbursed_amount=2500.00,
            has_company_invoice=True,
            project_name="Q1 采购",
            expense_type="办公用品",
            invoice_type="增值票",
            remark="订单号:ABC-123",
            related_persons="张三,李四",
            blocked_from_status=None,
        )
        # Assert
        assert obj.project_name == "Q1 采购"
        assert obj.actual_reimbursed_amount == 2500.00

    # ── 边界值 ──

    def test_allows_zero_amount(self):
        """金额为 0.0 应被接受"""
        # Arrange & Act
        obj = schemas.ExpenseCreate(
            title="零金额",
            amount=0.0,
            incurred_date=date(2025, 1, 1),
        )
        # Assert
        assert obj.amount == 0.0

    def test_allows_negative_amount(self):
        """金额为负数应被接受（Pydantic 不做业务约束，由 CRUD 层处理）"""
        # Arrange & Act
        obj = schemas.ExpenseCreate(
            title="负数金额",
            amount=-500.0,
            incurred_date=date(2025, 1, 1),
        )
        # Assert
        assert obj.amount == -500.0

    def test_allows_empty_project_name(self):
        """project_name 可选，传 None 合法"""
        # Arrange & Act
        obj = schemas.ExpenseCreate(
            title="空项目",
            amount=50.0,
            incurred_date=date(2025, 1, 1),
            project_name=None,
        )
        # Assert
        assert obj.project_name is None

    # ── 异常 ──

    def test_raises_when_title_missing(self):
        """缺少必填字段 title 应抛出 ValidationError"""
        # Arrange & Act & Assert
        with pytest.raises(ValidationError):
            schemas.ExpenseCreate(
                amount=100.0,
                incurred_date=date(2025, 6, 15),
            )

    def test_raises_when_amount_missing(self):
        """缺少必填字段 amount 应抛出 ValidationError"""
        # Arrange & Act & Assert
        with pytest.raises(ValidationError):
            schemas.ExpenseCreate(
                title="无金额",
                incurred_date=date(2025, 6, 15),
            )

    def test_raises_when_incurred_date_missing(self):
        """缺少必填字段 incurred_date 应抛出 ValidationError"""
        # Arrange & Act & Assert
        with pytest.raises(ValidationError):
            schemas.ExpenseCreate(
                title="无日期",
                amount=100.0,
            )

    def test_raises_when_amount_is_string(self):
        """amount 类型错误（字符串而非 float）应抛出 ValidationError"""
        # Arrange & Act & Assert
        with pytest.raises(ValidationError):
            schemas.ExpenseCreate(
                title="字符串金额",
                amount="not_a_number",
                incurred_date=date(2025, 1, 1),
            )


# ═══════════════════════════════════════════════════════════════
#  ExpenseUpdate
# ═══════════════════════════════════════════════════════════════

class TestExpenseUpdate:
    """ExpenseUpdate 局部更新校验"""

    def test_allows_empty_body_all_fields_none(self):
        """PATCH 允许空 body（所有字段 Optional、默认 None）"""
        # Arrange & Act
        obj = schemas.ExpenseUpdate()
        # Assert
        assert obj.title is None
        assert obj.amount is None
        assert obj.status is None

    def test_exclude_unset_returns_only_passed_fields(self):
        """exclude_unset=True 只返回显式传入的字段"""
        # Arrange & Act
        obj = schemas.ExpenseUpdate(title="只改标题")
        data = obj.model_dump(exclude_unset=True)
        # Assert
        assert data == {"title": "只改标题"}

    def test_single_field_update_preserves_others_none(self):
        """只传一个字段，其他字段为 None（由 CRUD 的 exclude_unset 跳过）"""
        # Arrange & Act
        obj = schemas.ExpenseUpdate(status="已完结")
        # Assert
        assert obj.status == "已完结"
        assert obj.title is None
        assert obj.amount is None

    def test_allows_none_value_for_optional_fields(self):
        """将 Optional 字段显式设为 None 合法"""
        # Arrange & Act
        obj = schemas.ExpenseUpdate(remark=None, project_name=None)
        # Assert
        assert obj.remark is None
        assert obj.project_name is None


# ═══════════════════════════════════════════════════════════════
#  ExpenseResponse
# ═══════════════════════════════════════════════════════════════

class TestExpenseResponse:
    """ExpenseResponse 响应体校验"""

    def test_requires_uuuid_field(self):
        """uuuid 为必填字段"""
        # Arrange & Act & Assert
        with pytest.raises(ValidationError):
            schemas.ExpenseResponse(
                title="无 uuuid",
                amount=100.0,
                incurred_date=date(2025, 1, 1),
            )

    def test_creates_with_uuuid(self):
        """传入 uuuid 即可成功创建"""
        # Arrange & Act
        obj = schemas.ExpenseResponse(
            uuuid="test-uuid-123",
            title="有 uuuid",
            amount=100.0,
            incurred_date=date(2025, 1, 1),
        )
        # Assert
        assert obj.uuuid == "test-uuid-123"

    def test_from_attributes_config_present(self):
        """model_config 包含 from_attributes=True（兼容 ORM 对象）"""
        # Arrange & Act
        config = schemas.ExpenseResponse.model_config
        # Assert
        assert config.get("from_attributes") is True


# ═══════════════════════════════════════════════════════════════
#  InvoiceBindRequest
# ═══════════════════════════════════════════════════════════════

class TestInvoiceBindRequest:
    """InvoiceBindRequest 校验"""

    def test_creates_with_expense_uuuid(self):
        """expense_uuuid 可选，传值时用作 bind 模式"""
        # Arrange & Act
        obj = schemas.InvoiceBindRequest(
            expense_uuuid="some-uuid",
            source_file_path="D:/Downloads/fapiao.pdf",
        )
        # Assert
        assert obj.expense_uuuid == "some-uuid"

    def test_creates_without_expense_uuuid_for_auto_mode(self):
        """不传 expense_uuuid 时为 auto 自动建档模式"""
        # Arrange & Act
        obj = schemas.InvoiceBindRequest(
            source_file_path="D:/Downloads/fapiao.pdf",
        )
        # Assert
        assert obj.expense_uuuid is None

    def test_raises_when_source_file_path_missing(self):
        """source_file_path 为必填字段"""
        # Arrange & Act & Assert
        with pytest.raises(ValidationError):
            schemas.InvoiceBindRequest()

    def test_accepts_optional_project_and_type(self):
        """project_name 和 expense_type 可选"""
        # Arrange & Act
        obj = schemas.InvoiceBindRequest(
            source_file_path="D:/a.pdf",
            project_name="测试项目",
            expense_type="差旅交通",
        )
        # Assert
        assert obj.project_name == "测试项目"
        assert obj.expense_type == "差旅交通"


# ═══════════════════════════════════════════════════════════════
#  ExportPdfsRequest
# ═══════════════════════════════════════════════════════════════

class TestExportPdfsRequest:
    """ExportPdfsRequest 校验"""

    def test_creates_with_valid_data(self):
        """正常创建"""
        # Arrange & Act
        obj = schemas.ExportPdfsRequest(
            uuuids=["uuid-1", "uuid-2"],
            target_dir="D:/桌面",
        )
        # Assert
        assert len(obj.uuuids) == 2

    def test_raises_when_uuuids_empty_list(self):
        """空 uuuids 列表违反 min_length=1"""
        # Arrange & Act & Assert
        with pytest.raises(ValidationError):
            schemas.ExportPdfsRequest(
                uuuids=[],
                target_dir="D:/桌面",
            )

    def test_raises_when_uuuids_missing(self):
        """uuuids 必填"""
        # Arrange & Act & Assert
        with pytest.raises(ValidationError):
            schemas.ExportPdfsRequest(
                target_dir="D:/桌面",
            )


# ═══════════════════════════════════════════════════════════════
#  ClientLogEntry
# ═══════════════════════════════════════════════════════════════

class TestClientLogEntry:
    """ClientLogEntry 校验"""

    def test_creates_with_valid_levels(self):
        """INFO / WARNING / ERROR 均合法"""
        # Arrange & Act
        for level in ("INFO", "WARNING", "ERROR"):
            obj = schemas.ClientLogEntry(level=level, message="test")
            # Assert
            assert obj.level == level

    def test_accepts_any_string_as_level(self):
        """Pydantic 不做 level 枚举约束（由下游 router 处理），任意字符串通过"""
        # Arrange & Act
        obj = schemas.ClientLogEntry(level="DEBUG", message="debug msg")
        # Assert
        assert obj.level == "DEBUG"

    def test_raises_when_level_missing(self):
        """level 必填"""
        # Arrange & Act & Assert
        with pytest.raises(ValidationError):
            schemas.ClientLogEntry(message="no level")

    def test_raises_when_message_missing(self):
        """message 必填"""
        # Arrange & Act & Assert
        with pytest.raises(ValidationError):
            schemas.ClientLogEntry(level="INFO")


# ═══════════════════════════════════════════════════════════════
#  Dashboard / Settings / Invoice 响应模型
# ═══════════════════════════════════════════════════════════════

class TestDashboardSchemas:
    """Dashboard 系列响应模型"""

    def test_dashboard_summary_fields(self):
        """DashboardSummary 三个字段"""
        # Arrange & Act
        obj = schemas.DashboardSummary(
            total_amount=1000.0,
            pending_amount=200.0,
            invoice_count=5,
        )
        # Assert
        assert obj.total_amount == 1000.0
        assert obj.pending_amount == 200.0
        assert obj.invoice_count == 5

    def test_trend_item_format(self):
        """TrendItem month 字段应为 'YYYY-MM' 格式"""
        # Arrange & Act
        obj = schemas.TrendItem(month="2025-06", amount=1500.0)
        # Assert
        assert obj.month == "2025-06"

    def test_distribution_item_percentage_range(self):
        """DistributionItem percentage 可为 0.0 ~ 1.0"""
        # Arrange & Act
        obj = schemas.DistributionItem(
            category="差旅",
            amount=500.0,
            percentage=0.25,
        )
        # Assert
        assert obj.percentage == 0.25

    def test_heatmap_item(self):
        """HeatmapItem date + count"""
        # Arrange & Act
        obj = schemas.HeatmapItem(date="2025-06-20", count=3)
        # Assert
        assert obj.date == "2025-06-20"
        assert obj.count == 3


class TestSettingsSchemas:
    """Settings 系列请求/响应模型"""

    def test_settings_paths_response(self):
        """SettingsPathsResponse 全字段"""
        # Arrange & Act
        obj = schemas.SettingsPathsResponse(
            db_path="/data",
            log_path="/logs",
            pdf_path="/data/pdfs",
            current_pdf_shard=0,
            shard_file_count=42,
        )
        # Assert
        assert obj.db_path == "/data"
        assert obj.shard_file_count == 42

    def test_settings_paths_update(self):
        """SettingsPathsUpdate 两个必填字段"""
        # Arrange & Act
        obj = schemas.SettingsPathsUpdate(
            db_path="/new/db",
            log_path="/new/log",
        )
        # Assert
        assert obj.db_path == "/new/db"

    def test_settings_validate_result(self):
        """SettingsValidateResult valid + error"""
        # Arrange & Act
        valid_obj = schemas.SettingsValidateResult(valid=True, error=None)
        invalid_obj = schemas.SettingsValidateResult(valid=False, error="路径相同")
        # Assert
        assert valid_obj.valid is True
        assert invalid_obj.error == "路径相同"

    def test_settings_restart_response(self):
        """SettingsRestartResponse 固定 action=restart"""
        # Arrange & Act
        obj = schemas.SettingsRestartResponse(
            action="restart",
            message="请重启",
        )
        # Assert
        assert obj.action == "restart"


class TestInvoiceResponse:
    """InvoiceResponse 响应模型"""

    def test_creates_with_all_fields(self):
        """全字段正常"""
        # Arrange & Act
        obj = schemas.InvoiceResponse(
            uuuid="inv-001",
            expense_uuuid="exp-001",
            file_name="发票.pdf",
            saved_path="/data/pdfs/发票.pdf",
        )
        # Assert
        assert obj.uuuid == "inv-001"
        assert obj.file_name == "发票.pdf"

    def test_from_attributes_config(self):
        """model_config 包含 from_attributes=True"""
        # Arrange & Act
        config = schemas.InvoiceResponse.model_config
        # Assert
        assert config.get("from_attributes") is True
