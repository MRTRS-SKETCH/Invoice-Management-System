from pydantic import BaseModel, Field
from typing import Optional
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
    related_persons: Optional[str] = Field(default=None, description="报销单有关人")


# 1. 创建记录入参校验
class ExpenseCreate(ExpenseBase):
    pass


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
    related_persons: Optional[str] = None


# 3. 向前端返回数据校验：强行要求携带主键 uuuid
class ExpenseResponse(ExpenseBase):
    uuuid: str

    # Pydantic v2 配置：允许兼容 SQLAlchemy ORM 对象
    model_config = {
        "from_attributes": True
    }