import os
from pathlib import Path
from sqlalchemy.orm import Session
from sqlalchemy import desc, func
from loguru import logger
from app import models, schemas

# ── 状态流转白名单 ──
VALID_TRANSITIONS = {
    "待开票": ["已开票"],
    "已开票": ["待报销"],
    "待报销": ["核销中"],
    "核销中": ["已完结"],
    "已完结": [],  # 终态，不可再流转
}


def get_expense_by_uuuid(db: Session, uuuid: str):
    """根据 uuuid 获取单条开销记录"""
    return db.query(models.ExpenseRecord).filter_by(uuuid=uuuid).first()


def get_expenses(
    db: Session,
    skip: int = 0,
    limit: int = 100,
    search: str | None = None,
    status: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
):
    """获取开销列表（按发生日期倒序排列），支持搜索、状态、日期范围筛选"""
    logger.info(
        "查询开销列表 | skip={} limit={} | search={} status={} date_from={} date_to={}",
        skip, limit, search, status, date_from, date_to,
    )
    q = db.query(models.ExpenseRecord)

    if search:
        q = q.filter(models.ExpenseRecord.title.ilike(f"%{search}%"))
    if status:
        q = q.filter(models.ExpenseRecord.status == status)
    if date_from:
        q = q.filter(models.ExpenseRecord.incurred_date >= date_from)
    if date_to:
        q = q.filter(models.ExpenseRecord.incurred_date <= date_to)

    return q.order_by(desc(models.ExpenseRecord.incurred_date)) \
            .offset(skip) \
            .limit(limit) \
            .all()


def create_expense(db: Session, expense: schemas.ExpenseCreate):
    """物理创建一条开销记录"""
    db_expense = models.ExpenseRecord(**expense.model_dump())
    db.add(db_expense)
    db.commit()
    db.refresh(db_expense)
    logger.info(
        "创建开销记录 | uuuid={} title={} amount={:.2f} status={}",
        db_expense.uuuid, db_expense.title, db_expense.amount, db_expense.status,
    )
    return db_expense


def update_expense(db: Session, uuuid: str, expense_update: schemas.ExpenseUpdate):
    """物理局部更新记录 (PATCH 核心逻辑)，含状态流转校验"""
    db_expense = get_expense_by_uuuid(db, uuuid)
    if not db_expense:
        return None

    # exclude_unset=True 保证前端没传的字段不会覆盖数据库里的原值
    update_data = expense_update.model_dump(exclude_unset=True)

    # ── 状态流转白名单校验 ──
    if "status" in update_data:
        new_status = update_data["status"]
        current_status = db_expense.status
        allowed = VALID_TRANSITIONS.get(current_status, [])
        if new_status not in allowed:
            logger.warning(
                "非法状态流转被拒绝 | uuuid={} 当前={} → 请求={} 允许={}",
                uuuid, current_status, new_status, allowed,
            )
            raise ValueError(
                f"非法的状态流转：不允许从「{current_status}」直接跳转到「{new_status}」。"
                f"允许的下一状态：{allowed if allowed else '无（已是终态）'}"
            )

    for key, value in update_data.items():
        setattr(db_expense, key, value)

    db.commit()
    db.refresh(db_expense)
    status_change = (
        f"状态: {current_status} → {new_status}"
        if "status" in update_data else "状态无变化"
    )
    logger.info("更新开销记录 | uuuid={} | {}", uuuid, status_change)
    return db_expense


def delete_expense(db: Session, uuuid: str) -> bool:
    """物理删除一条开销记录，同时级联删除关联发票记录与物理 PDF 文件"""
    db_expense = get_expense_by_uuuid(db, uuuid)
    if not db_expense:
        return False

    # 1. 查询关联的所有发票记录
    invoices = db.query(models.InvoiceRecord).filter_by(expense_uuuid=uuuid).all()

    # 2. 构造 PDF 存储目录的绝对路径
    base_dir = Path(__file__).resolve().parent.parent  # core_api/

    # 3. 逐条删除发票：先删物理文件，再删数据库记录
    deleted_pdfs = 0
    for inv in invoices:
        pdf_path = base_dir / inv.saved_path
        try:
            if pdf_path.exists() and pdf_path.is_file():
                os.remove(pdf_path)
                deleted_pdfs += 1
        except OSError as e:
            logger.opt(exception=True).error("删除物理PDF失败 | path={}", pdf_path)
        db.delete(inv)

    # 4. 删除开销记录本身
    db.delete(db_expense)
    db.commit()
    logger.info(
        "删除开销记录 | uuuid={} title={} | 级联清理发票={}条 PDF={}个",
        uuuid, db_expense.title, len(invoices), deleted_pdfs,
    )
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
    logger.info(
        "绑定发票 | uuuid={} expense_uuuid={} file_name={}",
        db_invoice.uuuid, expense_uuuid, file_name,
    )
    return db_invoice

def get_invoice_by_uuuid(db: Session, uuuid: str):
    """根据 uuuid 获取单条发票记录"""
    return db.query(models.InvoiceRecord).filter_by(uuuid=uuuid).first()


def get_invoices_by_expense(db: Session, expense_uuuid: str):
    """根据业务流水 uuuid 获取其绑定的所有发票"""
    return db.query(models.InvoiceRecord).filter_by(expense_uuuid=expense_uuuid).all()


def delete_invoice(db: Session, uuuid: str) -> bool:
    """删除单条发票记录及其物理 PDF 文件"""
    db_invoice = get_invoice_by_uuuid(db, uuuid)
    if not db_invoice:
        logger.warning("尝试删除不存在的发票 | uuuid={}", uuuid)
        return False

    base_dir = Path(__file__).resolve().parent.parent
    pdf_path = base_dir / db_invoice.saved_path
    try:
        if pdf_path.exists() and pdf_path.is_file():
            os.remove(pdf_path)
            logger.info("删除发票PDF文件 | path={}", pdf_path)
    except OSError as e:
        logger.opt(exception=True).error("删除物理PDF失败 | path={}", pdf_path)

    db.delete(db_invoice)
    db.commit()
    logger.info("删除发票记录 | uuuid={} expense_uuuid={} file_name={}", uuuid, db_invoice.expense_uuuid, db_invoice.file_name)
    return True


def get_dashboard_summary(db: Session) -> dict:
    """看板汇总统计"""
    logger.info("查询看板汇总")
    # 1. 累计报销总额
    total_amount = db.query(func.sum(models.ExpenseRecord.amount)).scalar() or 0.0

    # 2. 待处理金额 (对应你的默认状态 "待开票")
    pending_amount = db.query(func.sum(models.ExpenseRecord.amount)) \
                         .filter(models.ExpenseRecord.status == "待开票") \
                         .scalar() or 0.0

    # 3. 真实发票总数 (直接查你的 InvoiceRecord 物理表！)
    invoice_count = db.query(func.count(models.InvoiceRecord.uuuid)).scalar() or 0

    return {
        "total_amount": float(total_amount),
        "pending_amount": float(pending_amount),
        "invoice_count": invoice_count
    }


def get_monthly_trend(db: Session) -> list:
    """返回最近 12 个月的报销金额趋势，无数据的月份填 0"""
    from datetime import datetime

    # 纯 stdlib 生成最近 12 个月的月份标签
    now = datetime.now()
    all_months = []
    for i in range(11, -1, -1):
        year = now.year
        month = now.month - i
        while month <= 0:
            month += 12
            year -= 1
        all_months.append(f"{year}-{month:02d}")

    # 数据库聚合查询
    query = db.query(
        func.strftime('%Y-%m', models.ExpenseRecord.incurred_date).label('month'),
        func.sum(models.ExpenseRecord.amount).label('total')
    ).group_by('month').order_by('month').all()

    db_map = {row.month: float(row.total or 0.0) for row in query}

    return [{"month": m, "amount": db_map.get(m, 0.0)} for m in all_months]


def get_category_distribution(db: Session) -> list:
    # 按【报销项目名称 project_name】分组统计
    # func.coalesce 用于如果 project_name 是空的，就归类为 "无项目"
    query = db.query(
        func.coalesce(models.ExpenseRecord.project_name, "通用类目").label('category'),
        func.sum(models.ExpenseRecord.amount).label('total')
    ).group_by('category').all()

    total_all = sum(row.total for row in query if row.total) or 1.0

    result = []
    for row in query:
        amt = float(row.total or 0.0)
        result.append({
            "category": row.category,
            "amount": amt,
            "percentage": round(amt / total_all, 4)
        })

    return sorted(result, key=lambda x: x["amount"], reverse=True)