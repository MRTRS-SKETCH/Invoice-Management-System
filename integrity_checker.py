"""
完整性校验工具 — 对安装目录所有程序文件进行 SHA256 校验。

运行方式：双击 exe，弹出 GUI 消息框展示结果。
排除范围：api_server/config/、配置中的数据库目录、日志目录。
"""
import hashlib
import json
import os
import sys
from base64 import b64decode
from pathlib import Path

# ── 清单（构建时注入）──
MANIFEST_B64 = "{{MANIFEST_B64}}"


def _norm(p: Path | str) -> str:
    """标准化路径：绝对化 + 反斜杠转正斜杠 + 末尾加分隔符"""
    s = os.path.abspath(str(p))
    return s.replace("\\", "/").rstrip("/") + "/"


def _find_root() -> Path | None:
    """定位安装根目录：exe 所在目录应包含 api_server/ 子目录。

    build_app.py 保证完整性校验.exe 与 api_server/ 同级输出。
    """
    # 候选目录列表：优先 sys.argv[0]（最可靠），其次 sys.executable
    candidates = []
    for src in (sys.argv[0], sys.executable):
        d = os.path.dirname(os.path.abspath(src))
        if d not in candidates:
            candidates.append(d)

    for exe_dir in candidates:
        p = Path(exe_dir)
        # 直接检查
        if (p / "api_server").is_dir():
            return p
        # 向上搜索（用户可能把 exe 放在了子目录）
        for parent in p.parents:
            if (parent / "api_server").is_dir():
                return parent
    return None


def _load_excluded_paths(root: Path) -> set[str]:
    """从 config.json 读取 db_path 和 log_path，构建排除路径集合"""
    excluded: set[str] = set()

    # 始终排除 config/ 目录
    excluded.add(_norm(root / "api_server" / "config"))

    # 也排除 user_data/ 和 logs/ 默认路径
    for sub in ("api_server/user_data", "api_server/logs"):
        excluded.add(_norm(root / sub))

    # 尝试读取 config.json，排除用户自定义的 db_path / log_path
    config_file = root / "api_server" / "config" / "config.json"
    if config_file.exists():
        try:
            cfg = json.loads(config_file.read_text(encoding="utf-8"))
            for key in ("db_path", "log_path"):
                p = cfg.get(key)
                if p:
                    if os.path.isabs(p):
                        excluded.add(_norm(p))
                    else:
                        excluded.add(_norm(root / p))
        except Exception:
            pass

    return excluded


def _is_excluded(abs_path: str, excluded: set[str]) -> bool:
    """判断文件路径是否在任一排除目录内"""
    path_str = _norm(abs_path)
    for exc in excluded:
        if path_str.startswith(exc):
            return True
    return False


def _compute_sha256(file_path: Path) -> str:
    """计算文件的 SHA256 十六进制摘要"""
    h = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def run() -> int:
    root = _find_root()
    if root is None:
        _msgbox("错误", "无法定位安装根目录，请将本程序放在安装目录内运行。", 0x10)
        return 1

    # 解析清单
    try:
        manifest = json.loads(b64decode(MANIFEST_B64))
    except Exception as e:
        _msgbox("错误", f"清单解析失败: {e}", 0x10)
        return 1

    expected_files: dict[str, str] = manifest.get("files", {})

    # 加载排除路径
    excluded = _load_excluded_paths(root)

    # 扫描安装目录
    actual: dict[str, str] = {}
    for fp in root.rglob("*"):
        if not fp.is_file():
            continue
        if _is_excluded(str(fp), excluded):
            continue
        rel = str(fp.relative_to(root)).replace("\\", "/")
        actual[rel] = _compute_sha256(fp)

    # 比对
    missing: list[str] = []
    mismatch: list[str] = []
    extra: list[str] = []

    for path, expected_hash in expected_files.items():
        if path not in actual:
            missing.append(path)
        elif actual[path] != expected_hash:
            mismatch.append(f"{path} (期望: {expected_hash[:12]}...  实际: {actual[path][:12]}...)")

    for path in actual:
        if path not in expected_files:
            extra.append(path)

    # 构建消息
    if not missing and not mismatch:
        _msgbox("✅ 完整性校验通过", "所有程序文件未被篡改，系统完整性正常。", 0x40)
        return 0
    else:
        lines = ["以下文件校验异常：", ""]
        if missing:
            lines.append(f"缺失文件 ({len(missing)}):")
            for m in missing[:20]:
                lines.append(f"  ✗ {m}")
            if len(missing) > 20:
                lines.append(f"  ... 及另外 {len(missing) - 20} 个文件")
            lines.append("")
        if mismatch:
            lines.append(f"哈希不匹配 ({len(mismatch)}):")
            for m in mismatch[:10]:
                lines.append(f"  ✗ {m}")
            if len(mismatch) > 10:
                lines.append(f"  ... 及另外 {len(mismatch) - 10} 个文件")
            lines.append("")
        if extra:
            lines.append(f"新增文件 ({len(extra)}):")
            for e in extra[:10]:
                lines.append(f"  + {e}")
            lines.append("")
        _msgbox("❌ 完整性校验失败", "\n".join(lines), 0x10)
        return 1


def _msgbox(title: str, text: str, icon: int) -> None:
    """Windows 原生 MessageBox"""
    try:
        import ctypes
        ctypes.windll.user32.MessageBoxW(0, text, title, icon)
    except Exception:
        # 非 Windows 环境回退到控制台
        print(f"[{title}] {text}")


if __name__ == "__main__":
    sys.exit(run())
