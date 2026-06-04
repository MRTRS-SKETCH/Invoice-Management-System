"""
设置 API — 数据库 / 日志路径的自定义管理。

GET   /api/settings/paths     → 返回当前配置
PUT   /api/settings/paths     → 更新配置（保存后预建目录结构）
POST  /api/settings/validate  → 预览校验（保存前防误操作）
POST  /api/settings/preview   → 预览目录结构（不实际创建）
POST  /api/settings/restart   → 返回重启信号给前端
"""
from fastapi import APIRouter, HTTPException
from loguru import logger

from app import schemas, config_manager

router = APIRouter(
    prefix="/api/settings",
    tags=["设置 (Settings)"]
)


@router.get("/paths", response_model=schemas.SettingsPathsResponse)
def get_paths():
    """返回当前数据库、日志、PDF 路径及分片状态"""
    summary = config_manager.get_config_for_api()
    return schemas.SettingsPathsResponse(
        db_path=summary["db_path"],
        log_path=summary["log_path"],
        pdf_path=summary["pdf_path"],
        current_pdf_shard=summary["current_pdf_shard"],
        shard_file_count=summary["shard_file_count"],
    )


@router.put("/paths", response_model=schemas.SettingsPathsResponse)
def update_paths(body: schemas.SettingsPathsUpdate):
    """更新数据库/日志路径并持久化到 config.json，同时预建目录结构。

    ⚠️ 新路径在**重启后端**后完全生效，当前运行实例继续使用旧路径。
    """
    logger.info("PUT /api/settings/paths | db_path={} log_path={}", body.db_path, body.log_path)

    # 校验
    valid, error = config_manager.validate_paths(body.db_path, body.log_path)
    if not valid:
        raise HTTPException(status_code=400, detail=error)

    # 保存 + 预建目录（save_config 内部调用 _prebuild_structure）
    config_manager.save_config(body.db_path, body.log_path)

    summary = config_manager.get_config_for_api()
    return schemas.SettingsPathsResponse(
        db_path=summary["db_path"],
        log_path=summary["log_path"],
        pdf_path=summary["pdf_path"],
        current_pdf_shard=summary["current_pdf_shard"],
        shard_file_count=summary["shard_file_count"],
    )


@router.post("/validate", response_model=schemas.SettingsValidateResult)
def validate_paths(body: schemas.SettingsPathsUpdate):
    """预览校验：前端在用户输入时可实时调用，不修改任何配置"""
    valid, error = config_manager.validate_paths(body.db_path, body.log_path)
    return schemas.SettingsValidateResult(valid=valid, error=error)


@router.post("/preview", response_model=schemas.SettingsPreviewResponse)
def preview_structure(body: schemas.SettingsPreviewRequest):
    """预览指定路径下将自动创建的子目录与文件结构（纯展示，不实际创建）"""
    preview = config_manager.preview_directory_structure(body.db_path, body.log_path)
    return schemas.SettingsPreviewResponse(
        db_path=preview["db_path"],
        log_path=preview["log_path"],
        pdf_path=preview["pdf_path"],
        db_structure=preview["db_structure"],
        log_structure=preview["log_structure"],
    )


@router.post("/restart", response_model=schemas.SettingsRestartResponse)
def restart_backend():
    """向前端返回重启信号。前端收到后负责杀进程 + 重新拉起。"""
    logger.info("POST /api/settings/restart | 收到重启请求")
    return schemas.SettingsRestartResponse(
        action="restart",
        message="请杀死后端进程并重新拉起"
    )
