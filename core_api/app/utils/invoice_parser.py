"""
PDF 发票智能解析工具
使用 pdfplumber 提取电子发票（普票/增值票）的核心字段：
  发票类型、开票日期、项目名称、开票金额、备注
"""

import re
from typing import Any

import pdfplumber
from loguru import logger


# ── 解析失败时的默认回退字典 ──
FALLBACK_RESULT: dict[str, Any] = {
    "invoice_type": "备注",
    "incurred_date": "",
    "item_name": "自动解析失败",
    "amount": 0.0,
    "remark": "",
}


def parse_invoice_pdf(file_path: str) -> dict[str, Any]:
    """
    解析电子发票 PDF，提取 5 个核心字段。

    对发票第一页文本按行分割后，依次调用各子提取函数。
    任一字段提取异常均回退到 FALLBACK_RESULT 的对应默认值，
    不会因单字段失败中断整个解析流程。

    Args:
        file_path: PDF 文件的本地绝对路径

    Returns:
        dict: {
            "invoice_type": str,   # '普票' | '增值票' | '备注'
            "incurred_date": str,  # 'YYYY-MM-DD' 或 ""
            "item_name": str,      # 如 '*酒*汾酒精品' 或 '自动解析失败'
            "amount": float,       # 价税合计金额
            "remark": str,         # 备注文本 或 ""
        }
    """
    # ── 打开 PDF 并提取第一页文本 ──
    try:
        with pdfplumber.open(file_path) as pdf:
            if not pdf.pages:
                logger.warning("PDF 无页面 | file={}", file_path)
                return dict(FALLBACK_RESULT)
            first_page = pdf.pages[0]
            text = first_page.extract_text()
            if not text:
                logger.warning("PDF 第一页无可提取文本 | file={}", file_path)
                return dict(FALLBACK_RESULT)
    except Exception as e:
        logger.error("pdfplumber 打开/解析失败 | file={} error={}", file_path, e)
        return dict(FALLBACK_RESULT)

    lines = text.splitlines()
    result: dict[str, Any] = {}

    # ── 1. 发票类型 ──
    try:
        result["invoice_type"] = _extract_invoice_type(text)
    except Exception as e:
        logger.warning("发票类型提取异常 | error={}", e)
        result["invoice_type"] = FALLBACK_RESULT["invoice_type"]

    # ── 2. 开票日期 ──
    try:
        result["incurred_date"] = _extract_incurred_date(text)
    except Exception as e:
        logger.warning("开票日期提取异常 | error={}", e)
        result["incurred_date"] = FALLBACK_RESULT["incurred_date"]

    # ── 3. 项目名称 ──
    try:
        result["item_name"] = _extract_item_name(lines)
    except Exception as e:
        logger.warning("项目名称提取异常 | error={}", e)
        result["item_name"] = FALLBACK_RESULT["item_name"]

    # ── 4. 开票金额 ──
    try:
        result["amount"] = _extract_amount(text)
    except Exception as e:
        logger.warning("开票金额提取异常 | error={}", e)
        result["amount"] = FALLBACK_RESULT["amount"]

    # ── 5. 备注 ──
    try:
        result["remark"] = _extract_remark(lines)
    except Exception as e:
        logger.warning("备注提取异常 | error={}", e)
        result["remark"] = FALLBACK_RESULT["remark"]

    logger.info(
        "发票解析完成 | type={} date={} item={} amount={} remark={}",
        result["invoice_type"],
        result["incurred_date"],
        result["item_name"],
        result["amount"],
        result["remark"],
    )
    return result


# ═══════════════════════════════════════════════════════════════
#  各字段独立提取子函数
# ═══════════════════════════════════════════════════════════════

def _extract_invoice_type(text: str) -> str:
    """通过关键字识别发票类型"""
    if "增值税专用发票" in text:
        return "增值票"
    if "普通发票" in text:
        return "普票"
    return "备注"


def _extract_incurred_date(text: str) -> str:
    """
    匹配 "开票日期：2024年05月20日" / "开票日期: 2024年05月20日" 格式，
    全角/半角冒号均兼容，转换为 "YYYY-MM-DD" 返回。
    """
    match = re.search(r"开票日期[：:]\s*(\d{4})\s*年\s*(\d{2})\s*月\s*(\d{2})\s*日\s*", text)
    if match:
        return f"{match.group(1)}-{match.group(2)}-{match.group(3)}"
    logger.warning("未匹配到开票日期")
    return ""


def _extract_item_name(lines: list[str]) -> str:
    """
    定位 "项目名称 规格型号" 所在行，读取下一行，
    提取开头的 *类别*商品名 部分。
    """
    for i, line in enumerate(lines):
        if "项目名称" in line and "规格型号" in line:
            if i + 1 < len(lines):
                next_line = lines[i + 1].strip()
                # 匹配行首的 *xxx*yyy 模式（两个星号段，不含空格）
                match = re.match(r"^(\*[^*]+\*[^\s]+)", next_line)
                if match:
                    return match.group(1)
            break
    logger.warning("未匹配到项目名称")
    return "自动解析失败"


def _extract_amount(text: str) -> float:
    """
    匹配 "（小写）¥2996.00" / "(小写)￥1271.50" 等格式，
    全角/半角括号均兼容，提取数字并转为 float。
    """
    match = re.search(r"[(（]小写[)）]\s*[¥￥]\s*([0-9.]+)", text)
    if match:
        return float(match.group(1))
    logger.warning("未匹配到开票金额")
    return 0.0


def _extract_remark(lines: list[str]) -> str:
    """
    定位 "价税合计（大写）" / "价税合计(大写)" 所在行，读取下一行：
      全角/半角括号均兼容。
      - 若下一行为 "备" 或 "注" → 原票无备注，返回 ""
      - 否则将该行文本作为备注返回
    """
    for i, line in enumerate(lines):
        if "价税合计（大写）" in line or "价税合计(大写)" in line:
            if i + 1 < len(lines):
                next_line = lines[i + 1].strip()
                if next_line in ("备", "注", ""):
                    return ""
                return next_line
            break
    return ""
