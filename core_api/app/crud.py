import os
from pathlib import Path
from sqlalchemy.orm import Session
from sqlalchemy import desc, func
from loguru import logger
from app import models, schemas

# ── 状态流转白名单 ──
# 「已屏蔽」是独立旁路状态：任意非终态可屏蔽，屏蔽后可恢复原状态或删除
VALID_TRANSITIONS = {
    "待开票": ["已开票", "已屏蔽"],
    "已开票": ["待报销", "已屏蔽"],
    "待报销": ["核销中", "已屏蔽"],
    "核销中": ["已完结", "已屏蔽"],
    "已完结": [],       # 终态，不可再流转
    "已屏蔽": [],       # 屏蔽态：只能取消屏蔽（恢复原状态）或删除，不走正常流转
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


def create_expense_from_parsed(
    db: Session,
    *,
    title: str = "自动解析发票建档",
    amount: float = 0.0,
    incurred_date: str = "",
    invoice_type: str = "备注",
    status: str = "待报销",
    project_name: str | None = None,
    expense_type: str | None = None,
    remark: str | None = None,
):
    """从 PDF 解析结果全自动创建开销记录（绕过 Pydantic schema，直接写库）

    Args:
        title: 开销标题，默认 "自动解析发票建档"
        amount: 价税合计金额
        incurred_date: YYYY-MM-DD 格式字符串，解析失败则使用当天
        invoice_type: '普票' | '增值票' | '备注'
        status: 初始状态，默认 "待报销"
        project_name: 开销项目名称
        expense_type: 开销类型
        remark: 发票备注（订单号等）
    """
    from datetime import date as date_type

    # ── 日期解析：优先用 PDF 提取值，失败回退到当天 ──
    parsed_date = date_type.today()
    if incurred_date:
        try:
            parsed_date = date_type.fromisoformat(incurred_date)
        except (ValueError, TypeError):
            logger.warning("PDF 解析日期无效，回退为当天 | raw={}", incurred_date)

    db_expense = models.ExpenseRecord(
        title=title,
        amount=amount,
        incurred_date=parsed_date,
        invoice_type=invoice_type,
        status=status,
        project_name=project_name,
        expense_type=expense_type,
        remark=remark,
    )
    db.add(db_expense)
    db.commit()
    db.refresh(db_expense)
    logger.info(
        "自动建档 | uuuid={} title={} amount={:.2f} date={} invoice_type={} project={} type={}",
        db_expense.uuuid, db_expense.title, db_expense.amount,
        db_expense.incurred_date, invoice_type, project_name, expense_type,
    )
    return db_expense


def update_expense_invoice_type(db: Session, uuuid: str, invoice_type: str) -> bool:
    """仅更新开销记录的发票类型字段（轻量操作，不触发完整状态校验）"""
    db_expense = get_expense_by_uuuid(db, uuuid)
    if not db_expense:
        return False
    db_expense.invoice_type = invoice_type
    db.commit()
    logger.info("更新发票类型 | uuuid={} invoice_type={}", uuuid, invoice_type)
    return True


def update_expense(db: Session, uuuid: str, expense_update: schemas.ExpenseUpdate):
    """物理局部更新记录 (PATCH 核心逻辑)，含状态流转校验"""
    db_expense = get_expense_by_uuuid(db, uuuid)
    if not db_expense:
        return None

    # exclude_unset=True 保证前端没传的字段不会覆盖数据库里的原值
    update_data = expense_update.model_dump(exclude_unset=True)

    # ── 状态流转：不再拦截，允许自由切换任意状态 ──
    if "status" in update_data:
        new_status = update_data["status"]
        current_status = db_expense.status
        logger.info("状态变更 | uuuid={} {} → {}", uuuid, current_status, new_status)

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
            return False  # 文件锁未释放，阻断 DB 删除，防止僵尸记录
        db.delete(inv)

    # 4. 删除开销记录本身
    db.delete(db_expense)
    db.commit()
    logger.info(
        "删除开销记录 | uuuid={} title={} | 级联清理发票={}条 PDF={}个",
        uuuid, db_expense.title, len(invoices), deleted_pdfs,
    )
    return True

def block_expense(db: Session, uuuid: str) -> bool:
    """屏蔽一条开销记录：记录当前状态后置为「已屏蔽」"""
    db_expense = get_expense_by_uuuid(db, uuuid)
    if not db_expense:
        return False
    if db_expense.status == "已屏蔽":
        logger.warning("重复屏蔽 | uuuid={}", uuuid)
        return False

    db_expense.blocked_from_status = db_expense.status
    db_expense.status = "已屏蔽"
    db.commit()
    db.refresh(db_expense)
    logger.info("屏蔽开销记录 | uuuid={} 原状态={}", uuuid, db_expense.blocked_from_status)
    return True


def unblock_expense(db: Session, uuuid: str) -> bool:
    """取消屏蔽：恢复到屏蔽前的原始状态"""
    db_expense = get_expense_by_uuuid(db, uuuid)
    if not db_expense:
        return False
    if db_expense.status != "已屏蔽":
        logger.warning("取消屏蔽失败：当前并非屏蔽态 | uuuid={} status={}", uuuid, db_expense.status)
        return False
    if not db_expense.blocked_from_status:
        logger.warning("取消屏蔽失败：缺少原始状态 | uuuid={}", uuuid)
        return False

    restored = db_expense.blocked_from_status
    db_expense.status = restored
    db_expense.blocked_from_status = None
    db.commit()
    db.refresh(db_expense)
    logger.info("取消屏蔽 | uuuid={} 恢复为={}", uuuid, restored)
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
        return False  # 文件锁未释放，阻断 DB 删除，防止僵尸记录

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


def get_category_distribution(db: Session, days: int | None = None) -> list:
    """按【报销项目名称 project_name】分组统计，可选时间范围筛选"""
    from datetime import datetime, timedelta

    q = db.query(
        func.coalesce(models.ExpenseRecord.project_name, "通用类目").label('category'),
        func.sum(models.ExpenseRecord.amount).label('total')
    )
    if days is not None:
        cutoff = (datetime.now() - timedelta(days=days)).date()
        q = q.filter(models.ExpenseRecord.incurred_date >= cutoff)
    query = q.group_by('category').all()

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


def get_daily_heatmap(db: Session) -> list:
    """返回近 90 天每日开销记录数，无数据的日期填 0（用于前端热力图）"""
    from datetime import datetime, timedelta

    logger.info("查询每日开销频次热力图")

    # 生成近 90 天的日期列表
    today = datetime.now().date()
    all_days = [(today - timedelta(days=i)).isoformat() for i in range(89, -1, -1)]

    # 数据库聚合查询：按 incurred_date 分组统计条数
    query = db.query(
        func.date(models.ExpenseRecord.incurred_date).label('day'),
        func.count(models.ExpenseRecord.uuuid).label('cnt')
    ).group_by('day').all()

    db_map = {row.day: row.cnt for row in query}

    return [{"date": d, "count": db_map.get(d, 0)} for d in all_days]


def get_expense_type_distribution(db: Session, days: int | None = None) -> list:
    """按 expense_type 分组统计金额与占比（用于环形图），可选时间范围筛选"""
    logger.info("查询开销类型分布")

    from datetime import datetime, timedelta

    q = db.query(
        func.coalesce(models.ExpenseRecord.expense_type, "未分类").label('category'),
        func.sum(models.ExpenseRecord.amount).label('total')
    )
    if days is not None:
        cutoff = (datetime.now() - timedelta(days=days)).date()
        q = q.filter(models.ExpenseRecord.incurred_date >= cutoff)
    query = q.group_by('category').all()

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