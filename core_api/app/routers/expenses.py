from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from app.database import get_db
from app import schemas, crud  # 🔥 引入新抽离的 crud 模块

router = APIRouter(
    prefix="/api/expenses",
    tags=["业务流水 (Expenses)"]
)

# 1. 新增开销记录
@router.post("/", response_model=schemas.ExpenseResponse, status_code=status.HTTP_201_CREATED)
def create_expense(expense: schemas.ExpenseCreate, db: Session = Depends(get_db)):
    try:
        return crud.create_expense(db=db, expense=expense)
    except Exception as e:
        db.rollback()  # 发生非业务异常时安全回滚
        raise HTTPException(status_code=500, detail=f"服务器内部错误，创建失败: {str(e)}")

# 2. 获取开销列表
@router.get("/", response_model=List[schemas.ExpenseResponse])
def get_expenses(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    try:
        return crud.get_expenses(db=db, skip=skip, limit=limit)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"数据查询失败: {str(e)}")

# 3. 局部更新开销记录
@router.patch("/{uuuid}", response_model=schemas.ExpenseResponse)
def update_expense(uuuid: str, expense_update: schemas.ExpenseUpdate, db: Session = Depends(get_db)):
    try:
        db_expense = crud.update_expense(db=db, uuuid=uuuid, expense_update=expense_update)
        if not db_expense:
            raise HTTPException(status_code=404, detail="未找到该笔开销记录")
        return db_expense
    except HTTPException as he:
        raise he
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"更新操作失败: {str(e)}")

# 4. 删除某条记录
@router.delete("/{uuuid}")
def delete_expense(uuuid: str, db: Session = Depends(get_db)):
    try:
        success = crud.delete_expense(db=db, uuuid=uuuid)
        if not success:
            raise HTTPException(status_code=404, detail="未找到该笔开销记录")
        return {"status": "success", "message": "记录已成功删除", "uuuid": uuuid}
    except HTTPException as he:
        raise he
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"删除操作失败: {str(e)}")