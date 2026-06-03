from sqlalchemy import Column, String, Float, Date, Boolean,DateTime
from sqlalchemy.sql import func
from app.database import Base


def generate_uuuid():
    """生成全局唯一的 uuuid 字符串作为主键"""
    from uuid import uuid4
    return str(uuid4())


class ExpenseRecord(Base):
    __tablename__ = "expenses"

    # 核心标识：严格遵守 uuuid 规范
    uuuid = Column(String, primary_key=True, default=generate_uuuid, index=True)

    # 基础账目信息
    title = Column(String, nullable=False)  # 开销名称/事由
    amount = Column(Float, nullable=False)  # 金额
    incurred_date = Column(Date, nullable=False, index=True)  # 发生日期 — 排序/范围查询高频列

    # 业务生命周期状态机
    # 默认状态为"待开票"
    status = Column(String, nullable=False, default="待开票", index=True)  # 筛选高频列

    # 后续核销信息 (初始化阶段允许为 Null)
    submit_date = Column(Date, nullable=True)  # 报销提交日期
    complete_date = Column(Date, nullable=True)  # 报销完成日期
    actual_reimbursed_amount = Column(Float, nullable=True)  # 实际报销金额

    # 拓展业务字段
    has_company_invoice = Column(Boolean, default=False)  # 是否有公司发票
    project_name = Column(String, nullable=True, index=True)  # 报销项目名称 — group_by 高频列
    expense_type = Column(String, nullable=True, index=True)   # 开销类型 — group_by 高频列
    invoice_type = Column(String, nullable=True, default="备注")  # 发票类型：'普票' | '增值票' | '备注'
    remark = Column(String, nullable=True)  # 发票备注信息（订单号等）
    related_persons = Column(String, nullable=True)  # 报销单有关人

    # 屏蔽机制：独立旁路状态，不参与正常流转
    # 屏蔽时记录原状态，取消屏蔽时恢复
    blocked_from_status = Column(String, nullable=True)  # 被屏蔽前的原始状态


class InvoiceRecord(Base):
    __tablename__ = "invoices"

    # 核心标识
    uuuid = Column(String, primary_key=True, default=generate_uuuid, index=True)

    # 关系绑定：对应哪一笔开销
    expense_uuuid = Column(String, nullable=False, index=True)

    # 文件物理信息
    file_name = Column(String, nullable=False)  # 原始文件名（例如：滴滴出行发票.pdf）
    saved_path = Column(String, nullable=False)  # 系统内的相对保存路径（例如：user_data/pdfs/xxx.pdf）

    # 绑定时间
    created_at = Column(DateTime, default=func.now())