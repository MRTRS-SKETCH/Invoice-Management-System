from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from typing import List, Optional
from loguru import logger

from app.database import get_db
from app import schemas, crud

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

# 4. 删除某条记录
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