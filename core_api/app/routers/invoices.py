from shutil import copy2
from os import remove
from re import sub
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from app.database import get_db
from app import schemas, crud

router = APIRouter(
    prefix="/api/invoices",
    tags=["发票与 PDF (Invoices)"]
)

# 📍 魔法锚点：获取 core_api 目录绝对路径
BASE_DIR = Path(__file__).resolve().parent.parent.parent
PDF_STORAGE_DIR = BASE_DIR / "data" / "pdfs"

# 确保安全的本地物理存储目录存在
PDF_STORAGE_DIR.mkdir(parents=True, exist_ok=True)


@router.post("/bind", response_model=schemas.InvoiceResponse, status_code=status.HTTP_201_CREATED)
def bind_invoice(request: schemas.InvoiceBindRequest, db: Session = Depends(get_db)):
    # 1. 验证对应的“开销记录”是否存在
    expense = crud.get_expense_by_uuuid(db, request.expense_uuuid)
    if not expense:
        raise HTTPException(status_code=404, detail="未找到对应的开销记录，无法绑定发票")

    # 2. 验证前端传来的本地文件是否存在
    source_path = Path(request.source_file_path)
    if not source_path.exists() or not source_path.is_file():
        raise HTTPException(status_code=400, detail="提供的本地文件路径无效或不存在")

    if source_path.suffix.lower() != ".pdf":
        raise HTTPException(status_code=400, detail="目前仅支持绑定 PDF 格式的文件")

    # 👉 3. 终极命名优化：使用 "流水ID_报销事由_原文件名.pdf"
    extension = source_path.suffix  # 提取后缀名 (比如 .pdf)
    base_stem = source_path.stem  # 提取没有后缀的文件原名

    # 清洗标题中的非法路径字符
    safe_title = sub(r'[\\/*?:"<>|]', "", expense.title) if expense.title else "未命名"

    # 预拼接基础名称 (流水ID_报销事由_原文件名)
    raw_base_name = f"{expense.uuuid}_{safe_title}_{base_stem}"

    # 计算并执行安全截断 (最大总长200 - 后缀长度)
    max_length = 200
    allowed_base_length = max_length - len(extension)

    if len(raw_base_name) > allowed_base_length:
        raw_base_name = raw_base_name[:allowed_base_length]  # 超出部分直接咔嚓掉

    # 重新组装出绝对安全的文件名
    safe_filename = f"{raw_base_name}{extension}"
    file_name = source_path.name  # 保持存入数据库的原始 file_name 字段不变

    dest_path = PDF_STORAGE_DIR / safe_filename

    # 4. 执行物理拷贝
    try:
        copy2(source_path, dest_path)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"底层文件拷贝失败: {str(e)}")

    # 5. 路径写入数据库
    try:
        saved_path = f"data/pdfs/{safe_filename}"
        db_invoice = crud.create_invoice(
            db=db,
            expense_uuuid=request.expense_uuuid,
            file_name=file_name,
            saved_path=saved_path
        )
        # 👉 重点：返回给前端时，动态拼装成系统的绝对物理路径
        return {
            "uuuid": db_invoice.uuuid,
            "expense_uuuid": db_invoice.expense_uuuid,
            "file_name": db_invoice.file_name,
            "saved_path": str(BASE_DIR / db_invoice.saved_path)
        }
    except Exception as e:
        if dest_path.exists():
            remove(dest_path)
        raise HTTPException(status_code=500, detail=f"数据库绑定记录失败: {str(e)}")


@router.get("/by-expense/{expense_uuuid}", response_model=List[schemas.InvoiceResponse])
def get_expense_invoices(expense_uuuid: str, db: Session = Depends(get_db)):
    """获取某条业务流水下绑定的所有发票"""
    invoices = crud.get_invoices_by_expense(db, expense_uuuid)
    result = []
    for inv in invoices:
        # 👉 重点：查询时也转换为绝对物理路径交还给前端渲染
        abs_path = str(BASE_DIR / inv.saved_path)
        result.append({
            "uuuid": inv.uuuid,
            "expense_uuuid": inv.expense_uuuid,
            "file_name": inv.file_name,
            "saved_path": abs_path
        })
    return result


@router.delete("/{uuuid}")
def unbind_invoice(uuuid: str, db: Session = Depends(get_db)):
    """解绑并删除单张发票（同时清理物理 PDF 文件）"""
    success = crud.delete_invoice(db=db, uuuid=uuuid)
    if not success:
        raise HTTPException(status_code=404, detail="未找到该发票记录")
    return {"status": "success", "message": "发票已解绑并删除", "uuuid": uuuid}