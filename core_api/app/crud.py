from sqlalchemy.orm import Session
from sqlalchemy import desc
from app import models, schemas


def get_expense_by_uuuid(db: Session, uuuid: str):
    """根据 uuuid 获取单条开销记录"""
    return db.query(models.ExpenseRecord).filter_by(uuuid=uuuid).first()


def get_expenses(db: Session, skip: int = 0, limit: int = 100):
    """获取开销列表（按发生日期倒序排列）"""
    return db.query(models.ExpenseRecord) \
        .order_by(desc(models.ExpenseRecord.incurred_date)) \
        .offset(skip) \
        .limit(limit) \
        .all()


def create_expense(db: Session, expense: schemas.ExpenseCreate):
    """物理创建一条开销记录"""
    db_expense = models.ExpenseRecord(**expense.model_dump())
    db.add(db_expense)
    db.commit()
    db.refresh(db_expense)
    return db_expense


def update_expense(db: Session, uuuid: str, expense_update: schemas.ExpenseUpdate):
    """物理局部更新记录 (PATCH 核心逻辑)"""
    db_expense = get_expense_by_uuuid(db, uuuid)
    if not db_expense:
        return None

    # exclude_unset=True 保证前端没传的字段不会覆盖数据库里的原值
    update_data = expense_update.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(db_expense, key, value)

    db.commit()
    db.refresh(db_expense)
    return db_expense


def delete_expense(db: Session, uuuid: str) -> bool:
    """物理删除一条开销记录"""
    db_expense = get_expense_by_uuuid(db, uuuid)
    if not db_expense:
        return False

    db.delete(db_expense)
    db.commit()
    return True

def create_invoice(db: Session, expense_uuuid: str, file_name: str, saved_path: str):
    """物理记录一条发票与业务的绑定关系"""
    db_invoice = models.InvoiceRecord(
        expense_uuuid=expense_uuuid,
        file_name=file_name,
        saved_path=saved_path
    )
    db.add(db_invoice)
    db.commit()
    db.refresh(db_invoice)
    return db_invoice

def get_invoices_by_expense(db: Session, expense_uuuid: str):
    """根据业务流水 uuuid 获取其绑定的所有发票"""
    return db.query(models.InvoiceRecord).filter_by(expense_uuuid=expense_uuuid).all()