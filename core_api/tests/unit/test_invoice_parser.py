"""
发票 PDF 解析逻辑单元测试 — 覆盖 parse_invoice_pdf 及 5 个子提取函数。

覆盖模块: app/utils/invoice_parser.py
Fixtures: mock_pdfplumber（替换 pdfplumber.open）
"""
import pytest
from unittest.mock import MagicMock

from app.utils.invoice_parser import (
    parse_invoice_pdf,
    _extract_invoice_type,
    _extract_incurred_date,
    _extract_item_name,
    _extract_amount,
    _extract_remark,
    FALLBACK_RESULT,
)


# ═══════════════════════════════════════════════════════════════
#  _extract_invoice_type — 发票类型识别
# ═══════════════════════════════════════════════════════════════

class TestExtractInvoiceType:
    """发票类型子函数"""

    def test_returns_vat_for_special_vat_invoice(self):
        """识别「增值税专用发票」→ '增值票'"""
        # Arrange & Act
        result = _extract_invoice_type("这是一张增值税专用发票")
        # Assert
        assert result == "增值票"

    def test_returns_normal_for_regular_invoice(self):
        """识别「普通发票」→ '普票'"""
        # Arrange & Act
        result = _extract_invoice_type("电子普通发票")
        # Assert
        assert result == "普票"

    def test_returns_note_for_unrecognized(self):
        """未识别类型 → '备注'"""
        # Arrange & Act
        result = _extract_invoice_type("这是一张奇怪的票据")
        # Assert
        assert result == "备注"

    def test_returns_note_for_empty_string(self):
        """空文本 → '备注'"""
        # Arrange & Act
        result = _extract_invoice_type("")
        # Assert
        assert result == "备注"


# ═══════════════════════════════════════════════════════════════
#  _extract_incurred_date — 开票日期提取
# ═══════════════════════════════════════════════════════════════

class TestExtractIncurredDate:
    """开票日期子函数"""

    def test_extracts_standard_date_format(self):
        """标准格式 '开票日期：2024年05月20日' → '2024-05-20'"""
        # Arrange & Act
        result = _extract_incurred_date("开票日期：2024年05月20日")
        # Assert
        assert result == "2024-05-20"

    def test_extracts_single_digit_month_and_day(self):
        """个位数月/日 → '2024-01-03'"""
        # Arrange & Act
        result = _extract_incurred_date("开票日期：2024年01月03日")
        # Assert
        assert result == "2024-01-03"

    def test_returns_empty_when_no_match(self):
        """无匹配 → ''"""
        # Arrange & Act
        result = _extract_incurred_date("没有日期信息")
        # Assert
        assert result == ""

    def test_returns_empty_for_empty_string(self):
        """空字符串 → ''"""
        # Arrange & Act
        result = _extract_incurred_date("")
        # Assert
        assert result == ""


# ═══════════════════════════════════════════════════════════════
#  _extract_item_name — 项目名称提取
# ═══════════════════════════════════════════════════════════════

class TestExtractItemName:
    """项目名称子函数"""

    def test_extracts_item_name_from_standard_lines(self):
        """标准行结构：项目名称行 + 下一行为商品信息 → 提取 *xx*yy 部分"""
        # Arrange
        lines = [
            "项目名称 规格型号 数量 单价 金额 税率 税额",
            "*酒*汾酒精品 53度 500ml*6瓶 箱 2 1325.66 2651.33 13% 344.67",
        ]
        # Act
        result = _extract_item_name(lines)
        # Assert
        assert result == "*酒*汾酒精品"

    def test_returns_fallback_when_no_header_line(self):
        """缺少「项目名称 规格型号」标题行 → '自动解析失败'"""
        # Arrange
        lines = ["只有商品行", "*办公*打印纸 A4 2 50.00 100.00"]
        # Act
        result = _extract_item_name(lines)
        # Assert
        assert result == "自动解析失败"

    def test_returns_fallback_when_header_but_no_next_line(self):
        """有标题行但无下一行（行尾）→ '自动解析失败'"""
        # Arrange
        lines = ["项目名称 规格型号 数量"]
        # Act
        result = _extract_item_name(lines)
        # Assert
        assert result == "自动解析失败"

    def test_returns_fallback_when_next_line_no_star_pattern(self):
        """下一行没有 *xx*yy 模式 → '自动解析失败'"""
        # Arrange
        lines = [
            "项目名称 规格型号 数量 单价",
            "普通文本无星号",
        ]
        # Act
        result = _extract_item_name(lines)
        # Assert
        assert result == "自动解析失败"

    def test_handles_multiple_star_segments(self):
        """包含多个星号段的文本，regex 匹配到第一个空格前的所有星号段"""
        # Arrange
        lines = [
            "项目名称 规格型号",
            "*办公*打印纸*额外星号 A4",
        ]
        # Act
        result = _extract_item_name(lines)
        # Assert
        # 实际 regex ^(\*[^*]+\*[^\s]+) 会匹配到第一个空格前的所有内容
        assert result == "*办公*打印纸*额外星号"


# ═══════════════════════════════════════════════════════════════
#  _extract_amount — 价税合计金额提取
# ═══════════════════════════════════════════════════════════════

class TestExtractAmount:
    """金额子函数"""

    def test_extracts_amount_with_yuan_sign(self):
        """（小写）¥2996.00 → 2996.0"""
        # Arrange & Act
        result = _extract_amount("价税合计（小写）¥2996.00")
        # Assert
        assert result == 2996.00

    def test_extracts_amount_with_rmb_sign(self):
        """（小写）￥1271.50 → 1271.50"""
        # Arrange & Act
        result = _extract_amount("（小写）￥1271.50")
        # Assert
        assert result == 1271.50

    def test_extracts_amount_with_optional_space(self):
        """（小写）¥ 和数字之间有空格 → 仍可提取"""
        # Arrange & Act
        result = _extract_amount("（小写）¥ 500.00")
        # Assert
        assert result == 500.00

    def test_returns_zero_when_no_match(self):
        """无匹配 → 0.0"""
        # Arrange & Act
        result = _extract_amount("没有金额信息")
        # Assert
        assert result == 0.0

    def test_returns_zero_for_empty_string(self):
        """空字符串 → 0.0"""
        # Arrange & Act
        result = _extract_amount("")
        # Assert
        assert result == 0.0

    def test_handles_integer_amount(self):
        """整数金额（无小数部分）→ float"""
        # Arrange & Act
        result = _extract_amount("（小写）¥1000")
        # Assert
        assert result == 1000.0


# ═══════════════════════════════════════════════════════════════
#  _extract_remark — 备注提取
# ═══════════════════════════════════════════════════════════════

class TestExtractRemark:
    """备注子函数"""

    def test_extracts_remark_when_present(self):
        """备注存在 → 提取文本"""
        # Arrange
        lines = [
            "价税合计（大写）贰仟玖佰玖拾陆圆整",
            "订单号:2007064325443298",
        ]
        # Act
        result = _extract_remark(lines)
        # Assert
        assert result == "订单号:2007064325443298"

    def test_returns_empty_when_next_line_is_bei(self):
        """下一行为「备」→ 无备注，返回 "" """
        # Arrange
        lines = [
            "价税合计（大写）壹佰圆整",
            "备",
        ]
        # Act
        result = _extract_remark(lines)
        # Assert
        assert result == ""

    def test_returns_empty_when_next_line_is_zhu(self):
        """下一行为「注」→ 无备注，返回 "" """
        # Arrange
        lines = [
            "价税合计（大写）壹佰圆整",
            "注",
        ]
        # Act
        result = _extract_remark(lines)
        # Assert
        assert result == ""

    def test_returns_empty_when_next_line_is_empty(self):
        """下一行为空字符串 → 无备注"""
        # Arrange
        lines = [
            "价税合计（大写）壹佰圆整",
            "",
        ]
        # Act
        result = _extract_remark(lines)
        # Assert
        assert result == ""

    def test_returns_empty_when_no_heji_line(self):
        """缺少「价税合计（大写）」行 → ''"""
        # Arrange
        lines = ["没有合计行", "也没有备注"]
        # Act
        result = _extract_remark(lines)
        # Assert
        assert result == ""

    def test_returns_empty_when_heji_last_line(self):
        """「价税合计（大写）」是最后一行（无下一行）→ ''"""
        # Arrange
        lines = ["价税合计（大写）壹佰圆整"]
        # Act
        result = _extract_remark(lines)
        # Assert
        assert result == ""


# ═══════════════════════════════════════════════════════════════
#  parse_invoice_pdf — 集成解析（依赖 mock_pdfplumber fixture）
# ═══════════════════════════════════════════════════════════════

class TestParseInvoicePdfHappyPath:
    """parse_invoice_pdf Happy Path"""

    def test_parses_vat_invoice_completely(self, mock_pdfplumber):
        """增值票：全部 5 个字段正确解析"""
        # Act
        result = parse_invoice_pdf("fake.pdf")
        # Assert
        assert result["invoice_type"] == "增值票"
        assert result["incurred_date"] == "2024-05-20"
        assert result["item_name"] == "*酒*汾酒精品"
        assert result["amount"] == 2996.00
        assert result["remark"] == "订单号:2007064325443298"

    def test_parses_normal_invoice(self, mock_pdfplumber):
        """普票：发票类型正确识别"""
        # Arrange — 修改 mock 返回普通发票文本
        mock_pdfplumber.return_value.pages[0].extract_text.return_value = (
            "电子普通发票\n"
            "开票日期：2024年03月15日\n"
            "项目名称 规格型号 数量 单价 金额 税率 税额\n"
            "*餐*工作餐 2 150.00 300.00\n"
            "价税合计（大写）叁佰圆整 （小写）¥300.00\n"
            "注\n"
        )
        # Act
        result = parse_invoice_pdf("fake2.pdf")
        # Assert
        assert result["invoice_type"] == "普票"
        assert result["amount"] == 300.00
        assert result["remark"] == ""

    def test_handles_unrecognized_invoice_type(self, mock_pdfplumber):
        """无法识别发票类型 → '备注'"""
        # Arrange
        mock_pdfplumber.return_value.pages[0].extract_text.return_value = (
            "未知票据类型\n"
            "开票日期：2024年01月01日\n"
            "项目名称 规格型号\n"
            "*杂*杂项 1 50.00 50.00\n"
            "价税合计（大写）伍拾圆整 （小写）¥50.00\n"
            "备注内容可提取\n"
        )
        # Act
        result = parse_invoice_pdf("fake3.pdf")
        # Assert
        assert result["invoice_type"] == "备注"
        assert result["amount"] == 50.00

    def test_handles_missing_date(self, mock_pdfplumber):
        """无开票日期 → 回退空字符串"""
        # Arrange
        mock_pdfplumber.return_value.pages[0].extract_text.return_value = (
            "增值税专用发票\n"
            "无日期行\n"
            "项目名称 规格型号\n"
            "*酒*汾酒精品\n"
            "价税合计（大写）壹佰圆整 （小写）¥100.00\n"
        )
        # Act
        result = parse_invoice_pdf("fake4.pdf")
        # Assert
        assert result["incurred_date"] == ""

    def test_handles_missing_item_name(self, mock_pdfplumber):
        """无项目名称 → 回退 '自动解析失败'"""
        # Arrange
        mock_pdfplumber.return_value.pages[0].extract_text.return_value = (
            "增值税专用发票\n"
            "开票日期：2024年05月20日\n"
            "价税合计（大写）壹佰圆整 （小写）¥100.00\n"
        )
        # Act
        result = parse_invoice_pdf("fake5.pdf")
        # Assert
        assert result["item_name"] == "自动解析失败"


class TestParseInvoicePdfEdgeCases:
    """parse_invoice_pdf 边界与异常"""

    def test_returns_fallback_when_pdf_has_no_pages(self, mock_pdfplumber):
        """PDF 无页面 → 返回完整 FALLBACK_RESULT"""
        # Arrange
        mock_pdfplumber.return_value.pages = []
        # Act
        result = parse_invoice_pdf("empty.pdf")
        # Assert
        assert result == dict(FALLBACK_RESULT)

    def test_returns_fallback_when_first_page_has_no_text(self, mock_pdfplumber):
        """第一页无文本 → 返回完整 FALLBACK_RESULT"""
        # Arrange
        mock_pdfplumber.return_value.pages[0].extract_text.return_value = None
        # Act
        result = parse_invoice_pdf("notext.pdf")
        # Assert
        assert result == dict(FALLBACK_RESULT)

    def test_returns_fallback_when_pdfplumber_raises_exception(self, mock_pdfplumber):
        """pdfplumber.open 抛异常 → 返回 FALLBACK_RESULT 且不向上传播"""
        # Arrange
        mock_pdfplumber.side_effect = Exception("Corrupted PDF")
        # Act
        result = parse_invoice_pdf("corrupted.pdf")
        # Assert
        assert result == dict(FALLBACK_RESULT)

    def test_fallback_result_is_a_copy_not_reference(self, mock_pdfplumber):
        """返回的 FALLBACK_RESULT 是副本，修改不影响原常量"""
        # Arrange
        mock_pdfplumber.return_value.pages = []
        # Act
        result1 = parse_invoice_pdf("a.pdf")
        result2 = parse_invoice_pdf("b.pdf")
        result1["amount"] = 9999.0
        # Assert — 原 FALLBACK_RESULT 未被污染
        assert result2["amount"] == 0.0
        assert FALLBACK_RESULT["amount"] == 0.0

    def test_handles_partial_text_with_only_some_fields(self, mock_pdfplumber):
        """仅部分字段可解析，其余字段回退默认值"""
        # Arrange
        mock_pdfplumber.return_value.pages[0].extract_text.return_value = (
            "普通发票\n"
            # 无日期行
            # 无项目名称行
            "（小写）¥250.00\n"
        )
        # Act
        result = parse_invoice_pdf("partial.pdf")
        # Assert
        assert result["invoice_type"] == "普票"
        assert result["incurred_date"] == ""
        assert result["item_name"] == "自动解析失败"
        assert result["amount"] == 250.00
        assert result["remark"] == ""

    def test_mock_pdfplumber_called_with_correct_path(self, mock_pdfplumber):
        """验证 pdfplumber.open 被调用时传入正确的文件路径"""
        # Act
        parse_invoice_pdf("D:/specific/path.pdf")
        # Assert
        mock_pdfplumber.assert_called_with("D:/specific/path.pdf")
