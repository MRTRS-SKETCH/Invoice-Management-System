"""
配置管理模块 — 统一管理数据库、日志、PDF 存放路径。

配置文件位置：{backend_root}/config/config.json
首次运行自动生成默认值；JSON 损坏时回退默认值。
"""
from __future__ import annotations
import json
import os
from pathlib import Path
from loguru import logger

# ── 配置文件路径：{backend_root}/config/config.json ──
_BACKEND_ROOT = Path(__file__).resolve().parent.parent
_CONFIG_DIR = _BACKEND_ROOT / "config"
_CONFIG_PATH = _CONFIG_DIR / "config.json"

# ── 默认值 ──
_DEFAULT_DB_DIR = str(_BACKEND_ROOT / "user_data")
_DEFAULT_LOG_DIR = str(_BACKEND_ROOT / "logs")
_DEFAULT_PDF_SHARD_SIZE = 1000  # 单目录 PDF 数上限

# ── 内存缓存 ──
_config_cache: dict | None = None


def _default_config() -> dict:
    """生成默认配置字典"""
    return {
        "db_path": _DEFAULT_DB_DIR,
        "log_path": _DEFAULT_LOG_DIR,
        "pdf_shard_size": _DEFAULT_PDF_SHARD_SIZE,
        "current_pdf_shard": 0,
        "shard_file_count": 0,
    }


def load_config() -> dict:
    """加载配置（带缓存）。返回完整配置字典。"""
    global _config_cache
    if _config_cache is not None:
        return _config_cache

    if _CONFIG_PATH.exists():
        try:
            raw = _CONFIG_PATH.read_text(encoding="utf-8")
            cfg = json.loads(raw)
            # 校验必要字段
            if "db_path" not in cfg or "log_path" not in cfg:
                raise ValueError("缺少必要字段 db_path / log_path")
            _config_cache = cfg
            logger.info("配置加载成功 | db_path={} log_path={}",
                        cfg["db_path"], cfg["log_path"])
            return cfg
        except Exception as e:
            logger.warning("配置加载失败，回退默认值 | error={}", e)

    # 首次运行 / 文件损坏 — 回退默认
    _config_cache = _default_config()
    _save_raw(_config_cache)
    logger.info("已生成默认配置文件 | path={}", _CONFIG_PATH)
    return _config_cache


def save_config(db_path: str, log_path: str) -> dict:
    """保存新路径配置并预建目录结构。返回更新后的配置字典。"""
    global _config_cache
    cfg = load_config().copy()
    cfg["db_path"] = db_path
    cfg["log_path"] = log_path
    # 切换路径时重置分片计数器
    cfg["current_pdf_shard"] = 0
    cfg["shard_file_count"] = _count_files_in_dir(_get_pdf_dir(cfg))
    _save_raw(cfg)
    _config_cache = cfg

    # 预建目录结构 — 确保关闭设置对话框后文件夹已就绪
    _prebuild_structure(db_path, log_path)

    logger.info("配置已更新 | db_path={} log_path={}", db_path, log_path)
    return cfg


def update_shard_state(shard: int, count: int) -> None:
    """更新 PDF 分片计数器并持久化"""
    global _config_cache
    cfg = load_config().copy()
    cfg["current_pdf_shard"] = shard
    cfg["shard_file_count"] = count
    _save_raw(cfg)
    _config_cache = cfg


def get_db_path() -> Path:
    """获取数据库目录路径（已确保存在）"""
    p = Path(load_config()["db_path"])
    p.mkdir(parents=True, exist_ok=True)
    return p


def get_db_file_path() -> Path:
    """获取数据库文件完整路径"""
    return get_db_path() / "invoice_system.db"


def get_log_path() -> Path:
    """获取日志目录路径（已确保存在）"""
    p = Path(load_config()["log_path"])
    p.mkdir(parents=True, exist_ok=True)
    return p


def get_pdf_dir() -> Path:
    """获取当前 PDF 存储目录（含分片）。已确保存在。"""
    cfg = load_config()
    shard = cfg.get("current_pdf_shard", 0)
    return _get_pdf_dir(cfg, shard)


def _get_pdf_dir(cfg: dict, shard: int | None = None) -> Path:
    """内部：根据分片号拼接 PDF 目录路径"""
    db = Path(cfg["db_path"])
    if shard is None:
        shard = cfg.get("current_pdf_shard", 0)
    if shard == 0:
        p = db / "pdfs"
    else:
        p = db / f"pdfs_{shard}"
    p.mkdir(parents=True, exist_ok=True)
    return p


def next_pdf_shard_if_needed() -> Path:
    """检查当前 PDF 目录是否已满，满则切换到下一分片并返回新目录"""
    cfg = load_config()
    shard = cfg.get("current_pdf_shard", 0)
    count = _count_files_in_dir(_get_pdf_dir(cfg, shard))

    if count >= cfg.get("pdf_shard_size", _DEFAULT_PDF_SHARD_SIZE):
        shard += 1
        logger.info("PDF 目录分片递增 | new_shard={}", shard)
        update_shard_state(shard, 0)
        return _get_pdf_dir(cfg, shard)

    # 更新计数（不影响分片号）
    update_shard_state(shard, count)
    return _get_pdf_dir(cfg, shard)


def resolve_absolute_pdf_path(saved_path: str) -> Path:
    """将数据库中的相对路径（如 user_data/pdfs/xxx.pdf）解析为绝对路径"""
    cfg = load_config()
    db_path = Path(cfg["db_path"])
    # saved_path 格式: "user_data/pdfs/xxx.pdf" 或 "user_data/pdfs_1/xxx.pdf"
    rel = saved_path
    if rel.startswith("user_data/"):
        rel = rel[len("user_data/"):]
    return db_path / rel


def validate_paths(db_path: str, log_path: str) -> tuple[bool, str | None]:
    """校验路径合法性。
    
    返回 (is_valid, error_message)。
    规则：
    1. db_path 与 log_path 不能为同一目录
    2. log_path 不能在 db_path/pdfs* 内
    3. 路径需可写（尝试创建目录）
    """
    try:
        dp = Path(db_path).resolve()
        lp = Path(log_path).resolve()
    except Exception as e:
        return False, f"路径解析失败: {e}"

    # 规则 1：不能完全相同
    if dp == lp:
        return False, "数据库路径和日志路径不能为同一目录"

    # 规则 2：log_path 不能在 pdfs 相关目录内
    try:
        dp_str = str(dp).rstrip(os.sep) + os.sep
        lp_str = str(lp).rstrip(os.sep) + os.sep
        # 检查 lp 是否在 db/pdfs 或 db/pdfs_N 内
        for candidate in (dp / "pdfs", dp):
            c_str = str(candidate.resolve()).rstrip(os.sep) + os.sep
            if lp_str.startswith(c_str):
                return False, f"日志路径不能位于数据目录或 PDF 目录内"
    except Exception:
        pass

    # 规则 3：可写性
    try:
        dp.mkdir(parents=True, exist_ok=True)
        lp.mkdir(parents=True, exist_ok=True)
    except PermissionError:
        return False, "路径不可写，请检查权限"
    except OSError as e:
        return False, f"路径无法创建: {e}"

    return True, None


def get_config_for_api() -> dict:
    """返回 API 用配置摘要（不含内部字段）"""
    cfg = load_config()
    pdf = get_pdf_dir()
    return {
        "db_path": cfg["db_path"],
        "log_path": cfg["log_path"],
        "pdf_path": str(pdf),
        "current_pdf_shard": cfg.get("current_pdf_shard", 0),
        "shard_file_count": cfg.get("shard_file_count", 0),
    }


def preview_directory_structure(db_path: str, log_path: str) -> dict:
    """预览指定路径下将自动创建的文件与文件夹结构。
    
    返回 { db_structure: [...], log_structure: [...] }，
    每一项为相对于 db_path/log_path 的路径字符串。
    纯预览，不实际创建任何文件。
    """
    db_preview = [
        "invoice_system.db",
        "invoice_system.db-wal",
        "invoice_system.db-shm",
        "pdfs/",
    ]
    log_preview = [
        "app.log",
    ]
    return {
        "db_path": db_path,
        "log_path": log_path,
        "pdf_path": f"{db_path}{os.sep}pdfs{os.sep}",
        "db_structure": db_preview,
        "log_structure": log_preview,
    }


def _prebuild_structure(db_path: str, log_path: str) -> None:
    """预建数据库和日志目录结构，确保文件夹已就绪可被用户看到。"""
    try:
        dp = Path(db_path)
        dp.mkdir(parents=True, exist_ok=True)
        (dp / "pdfs").mkdir(parents=True, exist_ok=True)
        # 写 .placeholder 让资源管理器显示非空文件夹
        (dp / ".placeholder").touch(exist_ok=True)
        (dp / "pdfs" / ".placeholder").touch(exist_ok=True)
    except Exception as e:
        logger.warning("预建数据库目录失败 | path={} error={}", db_path, e)

    try:
        lp = Path(log_path)
        lp.mkdir(parents=True, exist_ok=True)
        (lp / ".placeholder").touch(exist_ok=True)
    except Exception as e:
        logger.warning("预建日志目录失败 | path={} error={}", log_path, e)


# ── 内部工具 ──

def _save_raw(cfg: dict) -> None:
    """原子写入 config.json（确保 config/ 目录存在）"""
    _CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = _CONFIG_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(_CONFIG_PATH)


def _count_files_in_dir(directory: Path) -> int:
    """统计目录下文件数量（不含子目录）"""
    if not directory.exists():
        return 0
    return sum(1 for f in directory.iterdir() if f.is_file())
