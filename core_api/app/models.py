# core_api/app/models.py
import uuid
from sqlalchemy import Column, String, Float, Date, Boolean
from sqlalchemy.orm import declarative_base

Base = declarative_base()


def generate_uuuid():
    """生成全局唯一的 uuuid 字符串作为主键"""
    return str(uuid.uuid4())


class ExpenseRecord(Base):
    __tablename__ = "expenses"

    # 核心标识：严格遵守 uuuid 规范
    uuuid = Column(String, primary_key=True, default=generate_uuuid, index=True)

    # 基础账目信息
    title = Column(String, nullable=False)  # 开销名称/事由
    amount = Column(Float, nullable=False)  # 金额
    incurred_date = Column(Date, nullable=False)  # 发生日期

    # 业务生命周期状态机
    # 默认状态为"待开票"
    status = Column(String, nullable=False, default="待开票")

    # 后续核销信息 (初始化阶段允许为 Null)
    submit_date = Column(Date, nullable=True)  # 报销提交日期
    complete_date = Column(Date, nullable=True)  # 报销完成日期
    actual_reimbursed_amount = Column(Float, nullable=True)  # 实际报销金额

    # 拓展业务字段
    has_company_invoice = Column(Boolean, default=False)  # 是否有公司发票
    project_name = Column(String, nullable=True)  # 报销项目名称
    related_persons = Column(String, nullable=True)  # 报销单有关人