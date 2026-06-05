from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from typing import List, Optional
from loguru import logger
from pathlib import Path
from shutil import copy2
from datetime import date

from app.database import get_db
from app import schemas, crud, models, config_manager

router = APIRouter(
    prefix="/api/expenses",
    tags=["业务流水 (Expenses)"]
)

# 1. 新增开销记录
@router.post("/", response_model=schemas.ExpenseResponse, status_code=status.HTTP_201_CREATED)
def create_expense(expense: schemas.ExpenseCreate, db: Session = Depends(get_db)):
    logger.info("POST /api/expenses/ | 创建开销请求 | title={} amount={:.2f}", expense.title, expense.amount)
    try:
        return crud.create_expense(db=db, expense=expense)
    except Exception as e:
        logger.opt(exception=True).error("创建开销失败 | title={}", expense.title)
        db.rollback()
        raise HTTPException(status_code=500, detail=f"服务器内部错误，创建失败: {str(e)}")

# 2. 获取开销列表（支持搜索、状态、日期范围筛选）
@router.get("/", response_model=List[schemas.ExpenseResponse])
def get_expenses(
    skip: int = 0,
    limit: int = 100,
    search: Optional[str] = Query(None, description="按事由模糊搜索"),
    status: Optional[str] = Query(None, description="按状态筛选：待开票/已开票/待报销/核销中/已完结"),
    date_from: Optional[str] = Query(None, description="发生日期起始 (YYYY-MM-DD)"),
    date_to: Optional[str] = Query(None, description="发生日期截止 (YYYY-MM-DD)"),
    db: Session = Depends(get_db),
):
    try:
        return crud.get_expenses(
            db=db, skip=skip, limit=limit,
            search=search, status=status,
            date_from=date_from, date_to=date_to,
        )
    except Exception as e:
        logger.opt(exception=True).error("查询开销列表失败")
        raise HTTPException(status_code=500, detail=f"数据查询失败: {str(e)}")

# 3. 局部更新开销记录
@router.patch("/{uuuid}", response_model=schemas.ExpenseResponse)
def update_expense(uuuid: str, expense_update: schemas.ExpenseUpdate, db: Session = Depends(get_db)):
    logger.info("PATCH /api/expenses/{} | 更新开销请求", uuuid)
    try:
        db_expense = crud.update_expense(db=db, uuuid=uuuid, expense_update=expense_update)
        if not db_expense:
            logger.warning("更新失败：记录不存在 | uuuid={}", uuuid)
            raise HTTPException(status_code=404, detail="未找到该笔开销记录")
        return db_expense
    except ValueError as ve:
        raise HTTPException(status_code=422, detail=str(ve))
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.opt(exception=True).error("更新开销失败 | uuuid={}", uuuid)
        db.rollback()
        raise HTTPException(status_code=500, detail=f"更新操作失败: {str(e)}")

# 4. 屏蔽某条记录（独立旁路，不参与正常流转）
@router.post("/{uuuid}/block")
def block_expense(uuuid: str, db: Session = Depends(get_db)):
    logger.info("POST /api/expenses/{}/block | 屏蔽请求", uuuid)
    try:
        success = crud.block_expense(db=db, uuuid=uuuid)
        if not success:
            raise HTTPException(status_code=404, detail="未找到该笔开销记录或已处于屏蔽态")
        return {"status": "success", "message": "记录已屏蔽", "uuuid": uuuid}
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.opt(exception=True).error("屏蔽失败 | uuuid={}", uuuid)
        db.rollback()
        raise HTTPException(status_code=500, detail=f"屏蔽操作失败: {str(e)}")

# 5. 取消屏蔽
@router.post("/{uuuid}/unblock")
def unblock_expense(uuuid: str, db: Session = Depends(get_db)):
    logger.info("POST /api/expenses/{}/unblock | 取消屏蔽请求", uuuid)
    try:
        success = crud.unblock_expense(db=db, uuuid=uuuid)
        if not success:
            raise HTTPException(status_code=404, detail="未找到该笔记录或当前并非屏蔽态")
        return {"status": "success", "message": "已取消屏蔽", "uuuid": uuuid}
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.opt(exception=True).error("取消屏蔽失败 | uuuid={}", uuuid)
        db.rollback()
        raise HTTPException(status_code=500, detail=f"取消屏蔽操作失败: {str(e)}")

# 6. 删除某条记录
@router.delete("/{uuuid}")
def delete_expense(uuuid: str, db: Session = Depends(get_db)):
    logger.info("DELETE /api/expenses/{} | 删除开销请求", uuuid)
    try:
        success = crud.delete_expense(db=db, uuuid=uuuid)
        if not success:
            logger.warning("删除失败：记录不存在 | uuuid={}", uuuid)
            raise HTTPException(status_code=404, detail="未找到该笔开销记录")
        return {"status": "success", "message": "记录已成功删除", "uuuid": uuuid}
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.opt(exception=True).error("删除开销失败 | uuuid={}", uuuid)
        db.rollback()
        raise HTTPException(status_code=500, detail=f"删除操作失败: {str(e)}")


# 7. 导出选中明细的 PDF 到指定目录
@router.post("/export-pdfs", response_model=schemas.ExportPdfsResponse)
def export_pdfs(request: schemas.ExportPdfsRequest, db: Session = Depends(get_db)):
    logger.info("POST /api/expenses/export-pdfs | 导出PDF请求 | uuuids={}", request.uuuids)

    target_base = Path(request.target_dir)
    if not target_base.exists():
        logger.warning("导出失败：目标目录不存在 | path={}", request.target_dir)
        raise HTTPException(status_code=400, detail="目标目录不存在")
    if not target_base.is_dir():
        raise HTTPException(status_code=400, detail="目标路径不是目录")

    # 在目标目录下创建以今天日期命名的子文件夹
    today = date.today().isoformat()  # e.g. "2025-07-11"
    export_dir = target_base / today
    export_dir.mkdir(parents=True, exist_ok=True)

    exported_files: List[str] = []
    for uuuid in request.uuuids:
        invoices = db.query(models.InvoiceRecord).filter_by(expense_uuuid=uuuid).all()
        for inv in invoices:
            try:
                src = config_manager.resolve_absolute_pdf_path(inv.saved_path)
            except Exception as e:
                logger.warning("解析PDF路径失败 | saved_path={} | error={}", inv.saved_path, e)
                continue
            if not src.exists():
                logger.warning("PDF源文件不存在，跳过 | path={}", src)
                continue

            # 处理重名：若已存在则加 (1)、(2) 后缀
            dest = export_dir / inv.file_name
            if dest.exists():
                stem = dest.stem
                suffix = dest.suffix
                counter = 1
                while dest.exists():
                    dest = export_dir / f"{stem}({counter}){suffix}"
                    counter += 1

            try:
                copy2(src, dest)
                exported_files.append(dest.name)
                logger.info("PDF导出成功 | src={} dest={}", src, dest)
            except Exception as e:
                logger.opt(exception=True).error("复制PDF失败 | src={} dest={}", src, dest)

    return schemas.ExportPdfsResponse(
        export_dir=str(export_dir),
        file_count=len(exported_files),
        files=exported_files,
    )