from shutil import copy2
from os import remove
from re import sub
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from loguru import logger

from app.database import get_db
from app import schemas, crud
from app.utils.invoice_parser import parse_invoice_pdf

router = APIRouter(
    prefix="/api/invoices",
    tags=["发票与 PDF (Invoices)"]
)

# 📍 魔法锚点：获取 core_api 目录绝对路径
BASE_DIR = Path(__file__).resolve().parent.parent.parent
PDF_STORAGE_DIR = BASE_DIR / "user_data" / "pdfs"

# 确保安全的本地物理存储目录存在
PDF_STORAGE_DIR.mkdir(parents=True, exist_ok=True)


@router.post("/bind", response_model=schemas.InvoiceResponse, status_code=status.HTTP_201_CREATED)
def bind_invoice(request: schemas.InvoiceBindRequest, db: Session = Depends(get_db)):
    logger.info("POST /api/invoices/bind | 绑定发票请求 | expense_uuuid={} source={}",
                request.expense_uuuid, request.source_file_path)

    # ── 1. 验证前端传来的本地文件 ──
    source_path = Path(request.source_file_path)
    if not source_path.exists() or not source_path.is_file():
        logger.warning("绑定发票失败：源文件不存在 | path={}", request.source_file_path)
        raise HTTPException(status_code=400, detail="提供的本地文件路径无效或不存在")

    if source_path.suffix.lower() != ".pdf":
        logger.warning("绑定发票失败：非PDF文件 | suffix={}", source_path.suffix)
        raise HTTPException(status_code=400, detail="目前仅支持绑定 PDF 格式的文件")

    # ── 2. PDF 智能解析 ──
    parsed = parse_invoice_pdf(str(source_path))
    logger.info(
        "PDF 解析结果 | type={} date={} item={} amount={:.2f}",
        parsed["invoice_type"], parsed["incurred_date"],
        parsed["item_name"], parsed["amount"],
    )

    # ── 3. 双模式：解析开销归属 ──
    if request.expense_uuuid:
        # 场景 A：绑定到已有流水 — 验证存在性并更新发票类型
        expense = crud.get_expense_by_uuuid(db, request.expense_uuuid)
        if not expense:
            logger.warning("绑定发票失败：开销记录不存在 | expense_uuuid={}", request.expense_uuuid)
            raise HTTPException(status_code=404, detail="未找到对应的开销记录，无法绑定发票")
        if parsed["invoice_type"] != "备注":
            crud.update_expense_invoice_type(db, request.expense_uuuid, parsed["invoice_type"])
        mode = "bind"
    else:
        # 场景 B：全自动建档 — 用解析结果创建新开销记录
        expense = crud.create_expense_from_parsed(
            db=db,
            title=parsed["item_name"],
            amount=parsed["amount"],
            incurred_date=parsed["incurred_date"],
            invoice_type=parsed["invoice_type"],
            project_name=request.project_name,
            expense_type=request.expense_type,
            remark=parsed.get("remark") or None,
        )
        mode = "auto"

    logger.info("发票绑定模式={} | expense_uuuid={}", mode, expense.uuuid)

    # ── 4. 文件命名与物理拷贝（复用原有安全逻辑） ──
    extension = source_path.suffix
    base_stem = source_path.stem

    safe_title = sub(r'[\\/*?:"<>|]', "", expense.title) if expense.title else "未命名"
    raw_base_name = f"{expense.uuuid}_{safe_title}_{base_stem}"

    max_length = 200
    allowed_base_length = max_length - len(extension)
    if len(raw_base_name) > allowed_base_length:
        raw_base_name = raw_base_name[:allowed_base_length]

    safe_filename = f"{raw_base_name}{extension}"
    file_name = source_path.name
    dest_path = PDF_STORAGE_DIR / safe_filename

    try:
        copy2(source_path, dest_path)
        logger.info("发票文件拷贝成功 | src={} → dest={}", source_path, dest_path)
    except Exception as e:
        logger.opt(exception=True).error("发票文件拷贝失败 | src={} → dest={}", source_path, dest_path)
        raise HTTPException(status_code=500, detail=f"底层文件拷贝失败: {str(e)}")

    # ── 5. 发票绑定记录写入数据库 ──
    try:
        saved_path = f"user_data/pdfs/{safe_filename}"
        db_invoice = crud.create_invoice(
            db=db,
            expense_uuuid=expense.uuuid,
            file_name=file_name,
            saved_path=saved_path
        )
        return {
            "uuuid": db_invoice.uuuid,
            "expense_uuuid": db_invoice.expense_uuuid,
            "file_name": db_invoice.file_name,
            "saved_path": str(BASE_DIR / db_invoice.saved_path)
        }
    except Exception as e:
        logger.opt(exception=True).error("数据库绑定发票记录失败 | expense_uuuid={}", expense.uuuid)
        if dest_path.exists():
            remove(dest_path)
            logger.info("已回滚：删除已拷贝的PDF文件 | path={}", dest_path)
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
    logger.info("DELETE /api/invoices/{} | 解绑发票请求", uuuid)
    success = crud.delete_invoice(db=db, uuuid=uuuid)
    if not success:
        raise HTTPException(status_code=404, detail="未找到该发票记录")
    return {"status": "success", "message": "发票已解绑并删除", "uuuid": uuuid}
