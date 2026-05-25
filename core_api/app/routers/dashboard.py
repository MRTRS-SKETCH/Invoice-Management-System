from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import List

from app.database import get_db
from app import schemas, crud

router = APIRouter(
    prefix="/api/dashboard",
    tags=["Dashboard 看板统计"]
)

@router.get("/summary", response_model=schemas.DashboardSummary)
def read_dashboard_summary(db: Session = Depends(get_db)):
    """获取顶层核心指标"""
    return crud.get_dashboard_summary(db)

@router.get("/trend", response_model=List[schemas.TrendItem])
def read_monthly_trend(db: Session = Depends(get_db)):
    """获取近 12 个月的报销金额趋势"""
    return crud.get_monthly_trend(db)

@router.get("/distribution", response_model=List[schemas.DistributionItem])
def read_category_distribution(db: Session = Depends(get_db)):
    """获取各项报销项目(Project)金额与占比"""
    return crud.get_category_distribution(db)