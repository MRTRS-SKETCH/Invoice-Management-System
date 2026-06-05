from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import date


# 公共基类：定义费用的核心通用字段
class ExpenseBase(BaseModel):
    title: str = Field(..., description="开销名称/事由")
    amount: float = Field(..., description="金额")
    incurred_date: date = Field(..., description="发生日期")
    status: str = Field(default="待开票", description="当前状态")

    submit_date: Optional[date] = Field(default=None, description="报销提交日期")
    complete_date: Optional[date] = Field(default=None, description="报销完成日期")
    actual_reimbursed_amount: Optional[float] = Field(default=None, description="实际报销金额")

    has_company_invoice: bool = Field(default=False, description="是否有公司发票")
    project_name: Optional[str] = Field(default=None, description="报销项目名称")
    expense_type: Optional[str] = Field(default=None, description="开销类型（如差旅交通/云服务采购）")
    invoice_type: Optional[str] = Field(default="备注", description="发票类型：'普票' | '增值票' | '备注'")
    remark: Optional[str] = Field(default=None, description="发票备注信息（订单号等）")
    related_persons: Optional[str] = Field(default=None, description="报销单有关人")
    blocked_from_status: Optional[str] = Field(default=None, description="被屏蔽前的原始状态（已屏蔽条目专用）")


# 1. 创建记录入参校验
class ExpenseCreate(ExpenseBase):
    pass


# ── 服务端分页计数 ──
class ExpenseCountResponse(BaseModel):
    total: int = Field(..., description="符合条件的开销记录总数")


# 2. 局部更新 (PATCH) 校验：全部变为 Optional，前端传什么就改什么
class ExpenseUpdate(BaseModel):
    title: Optional[str] = None
    amount: Optional[float] = None
    incurred_date: Optional[date] = None
    status: Optional[str] = None
    submit_date: Optional[date] = None
    complete_date: Optional[date] = None
    actual_reimbursed_amount: Optional[float] = None
    has_company_invoice: Optional[bool] = None
    project_name: Optional[str] = None
    expense_type: Optional[str] = None
    invoice_type: Optional[str] = None
    remark: Optional[str] = None
    related_persons: Optional[str] = None
    blocked_from_status: Optional[str] = None

# 3. 向前端返回数据校验：强行要求携带主键 uuuid
class ExpenseResponse(ExpenseBase):
    uuuid: str

    # Pydantic v2 配置：允许兼容 SQLAlchemy ORM 对象
    model_config = {
        "from_attributes": True
    }


# --- 发票 PDF 绑定 ---
# 接收 Flutter 传来的本地物理路径和业务流水ID
class InvoiceBindRequest(BaseModel):
    expense_uuuid: Optional[str] = Field(default=None, description="要绑定的业务流水主键 uuuid（为空时自动建档）")
    source_file_path: str = Field(..., description="Windows系统上的本地物理绝对路径 (如 D:\\Downloads\\fapiao.pdf)")
    project_name: Optional[str] = Field(default=None, description="开销项目名称（自动建档时可选填入）")
    expense_type: Optional[str] = Field(default=None, description="开销类型（自动建档时可选填入）")


# 返回给前端的渲染数据
class InvoiceResponse(BaseModel):
    uuuid: str
    expense_uuuid: str
    file_name: str
    saved_path: str  # Flutter 拿到这个相对路径后，就可以直接加载本地 PDF

    model_config = {
        "from_attributes": True
    }

# 顶层统计卡片
class DashboardSummary(BaseModel):
    total_amount: float     # 累计报销总额
    pending_amount: float   # 待处理/待开票总额
    pending_reimburse: float  # 待报销+核销中总额（前端免遍历）
    invoice_count: int      # 绑定的发票总张数

# 趋势图数据项
class TrendItem(BaseModel):
    month: str              # 格式: "2026-05"
    amount: float           # 当月报销总额

# 分布图数据项
class DistributionItem(BaseModel):
    category: str           # 类目名称 (如: 差旅, 餐饮, 采购)
    amount: float           # 该类目总额
    percentage: float       # 占比 (0.0 ~ 1.0)


# 热力图数据项（近90天每日开销频次）
class HeatmapItem(BaseModel):
    date: str               # 格式: "2026-05-20"
    count: int              # 当日开销记录数


# ── 前端日志批量上报 ──
class ClientLogEntry(BaseModel):
    level: str = Field(..., description="日志级别：INFO / WARNING / ERROR")
    message: str = Field(..., description="日志内容")

# ── 设置 / 路径管理 ──
class SettingsPathsResponse(BaseModel):
    db_path: str = Field(..., description="数据库目录绝对路径")
    log_path: str = Field(..., description="日志目录绝对路径")
    pdf_path: str = Field(..., description="当前 PDF 存储目录（只读，跟随数据库路径）")
    current_pdf_shard: int = Field(default=0, description="当前 PDF 分片编号")
    shard_file_count: int = Field(default=0, description="当前分片文件数")


class SettingsPathsUpdate(BaseModel):
    db_path: str = Field(..., description="新的数据库目录绝对路径")
    log_path: str = Field(..., description="新的日志目录绝对路径")


class SettingsValidateResult(BaseModel):
    valid: bool
    error: Optional[str] = None


class SettingsPreviewRequest(BaseModel):
    db_path: str = Field(..., description="预览目标数据库目录")
    log_path: str = Field(..., description="预览目标日志目录")


class SettingsPreviewResponse(BaseModel):
    db_path: str
    log_path: str
    pdf_path: str
    db_structure: List[str] = Field(default_factory=list, description="数据库目录将创建的文件/文件夹清单")
    log_structure: List[str] = Field(default_factory=list, description="日志目录将创建的文件/文件夹清单")


class SettingsRestartResponse(BaseModel):
    action: str = Field(default="restart", description="前端应执行的操作")
    message: str = Field(default="请杀死后端进程并重新拉起", description="提示信息")


# ── PDF 导出 ──
class ExportPdfsRequest(BaseModel):
    uuuids: List[str] = Field(..., min_length=1, description="要导出的开销记录 uuuid 列表")
    target_dir: str = Field(..., description="用户选择的目标目录绝对路径")


class ExportPdfsResponse(BaseModel):
    export_dir: str = Field(..., description="日期子文件夹路径（如 D:/桌面/2025-07-11）")
    all_dir: str = Field(..., description="全部发票子文件夹路径")
    vat_dir: str = Field(..., description="增值票子文件夹路径（仅含增值税专用发票）")
    all_count: int = Field(..., description="全部发票数量")
    vat_count: int = Field(..., description="增值票数量")
    files: List[str] = Field(default_factory=list, description="导出的全部文件名列表")
