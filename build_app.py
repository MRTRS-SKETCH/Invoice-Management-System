import subprocess
import shutil
import sys
import hashlib
import json
from base64 import b64encode
from pathlib import Path
from datetime import datetime
import re
import platform

# 全局常量定义 (保持大写)
ROOT_DIR = Path(__file__).parent.resolve()
CORE_API_DIR = ROOT_DIR / "core_api"
APP_UI_DIR = ROOT_DIR / "app_ui"
RELEASES_DIR = ROOT_DIR / "Releases"


def get_app_version():
    """从 core_api/main.py 的 FastAPI 实例中提取版本号"""
    main_py = CORE_API_DIR / "main.py"
    if not main_py.exists():
        print(f"⚠️  找不到 {main_py}，使用默认版本号 0.0.0")
        return "0.0.0"
    content = main_py.read_text(encoding="utf-8")
    match = re.search(r'version="(\d+\.\d+\.\d+)"', content)
    if match:
        return match.group(1)
    print("⚠️  未能从 main.py 提取版本号，使用默认版本号 0.0.0")
    return "0.0.0"


def get_os_name():
    """动态获取当前操作系统名称（首字母大写）"""
    name = platform.system()
    return name.capitalize()


def run_command(command, cwd, step_name):
    """运行终端命令并实时打印输出，彻底解决批处理中断提示"""
    print(f"\n[{step_name}] 正在执行: {' '.join(command)}")
    print("-" * 60)

    try:
        process = subprocess.Popen(
            command,
            cwd=cwd,
            shell=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            text=True,
            encoding='utf-8',
            errors='replace'
        )

        for line in process.stdout:
            cleaned_line = line.strip()
            if cleaned_line:
                print(f"  [{step_name} 日志] {cleaned_line}")

        process.wait()
        print("-" * 60)

        if process.returncode == 0:
            print(f"✅ [{step_name}] 执行成功！")
        else:
            print(f"❌ [{step_name}] 严重失败！错误码: {process.returncode}")
            sys.exit(1)

    except FileNotFoundError as e:
        print(f"\n❌ [{step_name}] 找不到命令: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ [{step_name}] 发生未知异常: {e}")
        sys.exit(1)

def _generate_hash_manifest(target_dir):
    """遍历安装目录，生成所有程序文件的 SHA256 清单。
    
    排除: api_server/config/, api_server/user_data/, api_server/logs/
    返回 JSON 字符串。
    """
    print("  ├─ 正在扫描文件并计算 SHA256...")
    target = Path(target_dir)
    # 排除的目录（相对于 target_dir）
    exclude_dirs = {
        "api_server/config",
        "api_server/user_data", 
        "api_server/logs",
    }
    
    files_manifest = {}
    total = 0
    for fp in sorted(target.rglob("*")):
        if not fp.is_file():
            continue
        rel = str(fp.relative_to(target)).replace("\\", "/")
        # 跳过排除目录
        excluded = False
        for ed in exclude_dirs:
            if rel.startswith(ed + "/") or rel == ed:
                excluded = True
                break
        if excluded:
            continue
        
        # 计算 SHA256
        h = hashlib.sha256()
        with open(fp, "rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                h.update(chunk)
        files_manifest[rel] = h.hexdigest()
        total += 1
    
    manifest = {
        "files": files_manifest,
        "generated_at": datetime.now().isoformat(),
        "total_files": total,
    }
    print(f"  ├─ 已扫描 {total} 个程序文件")
    return json.dumps(manifest, ensure_ascii=False)


def _compile_integrity_checker(target_dir, manifest_json):
    """将 base64 编码的清单注入模板并用 Nuitka 编译为 完整性校验.exe"""
    template_path = ROOT_DIR / "integrity_checker.py"
    if not template_path.exists():
        print("\\n❌ 找不到模板文件: integrity_checker.py")
        sys.exit(1)
    
    # 读取模板
    template = template_path.read_text(encoding="utf-8")
    manifest_b64 = b64encode(manifest_json.encode("utf-8")).decode("ascii")
    
    # 注入清单
    injected = template.replace('"{{MANIFEST_B64}}"', f'"{manifest_b64}"')
    
    # 写入临时文件
    tmp_py = ROOT_DIR / "_integrity_checker_build.py"
    tmp_py.write_text(injected, encoding="utf-8")
    
    print("  ├─ 正在用 Nuitka 编译 完整性校验.exe（--onefile）...")
    cmd = [
        sys.executable, "-m", "nuitka",
        "--onefile",
        "--windows-console-mode=disable",
        "--output-dir=build_ic",
        "--remove-output",
        str(tmp_py)
    ]
    run_command(cmd, cwd=ROOT_DIR, step_name="Nuitka 编译完整性校验工具")
    
    # 拷贝产物
    src_exe = ROOT_DIR / "build_ic" / "_integrity_checker_build.exe"
    dest_exe = Path(target_dir) / "完整性校验.exe"
    shutil.copy2(src_exe, dest_exe)
    print(f"  ├─ ✅ 完整性校验工具已生成: 完整性校验.exe")
    
    # 清理
    tmp_py.unlink(missing_ok=True)
    shutil.rmtree(ROOT_DIR / "build_ic", ignore_errors=True)



def clean_caches():
    """清理上一次打包留下的所有中间缓存"""
    print("\n[0/4] 🧹 正在清理旧版本的中间缓存...")

    caches_to_clean = [
        CORE_API_DIR / "build_out",
        CORE_API_DIR / "main.build",
        CORE_API_DIR / "main.dist",
        ROOT_DIR / "build_ic",
        APP_UI_DIR / "build",
        APP_UI_DIR / ".dart_tool",
    ]

    for cache_path in caches_to_clean:
        if cache_path.exists():
            if cache_path.is_dir():
                print(f"  ├─ 🗑️ 删除目录: {cache_path.relative_to(ROOT_DIR)}")
                shutil.rmtree(cache_path, ignore_errors=True)
            else:
                print(f"  ├─ 🗑️ 删除文件: {cache_path.relative_to(ROOT_DIR)}")
                cache_path.unlink(missing_ok=True)

    print("  └─ ✅ 缓存清理完毕！")


def build_project():
    print("=" * 60)
    print("      🚀 发票管理系统 - 全自动构建引擎 🚀")
    print("=" * 60)

    # 0. 先行清理历史缓存
    clean_caches()

    # 1. 编译 Python 后端
    nuitka_cmd = [
        sys.executable, "-m", "nuitka",
        "--standalone",
        "--windows-console-mode=disable",
        "--lto=yes",  # 开启链路优化
        "--remove-output",  # 编译完成后清除缓存
        "--include-package=uvicorn",
        "--include-package=sqlalchemy",
        "--include-package=pydantic",
        "--include-package=fastapi",
        "--output-dir=build_out",
        "main.py"
    ]
    run_command(nuitka_cmd, cwd=CORE_API_DIR, step_name="1/4 编译后端独立引擎")

    # 2. 编译 Flutter 前端
    flutter_exe = shutil.which("flutter")
    if not flutter_exe:
        print("\n❌ 找不到 Flutter 环境，请确保已将 Flutter 添加到系统 PATH 中！")
        sys.exit(1)

    flutter_cmd = [flutter_exe, "build", "windows"]
    run_command(flutter_cmd, cwd=APP_UI_DIR, step_name="2/4 编译 Flutter 桌面端")

    # 3. 拼装终极产物
    print("\n[3/4] 📦 正在拼装终极完全体文件夹...")

    if not RELEASES_DIR.exists():
        RELEASES_DIR.mkdir()

    # 动态生成目录名
    version = get_app_version()
    os_name = get_os_name()
    release_folder_name = f"{ROOT_DIR.name}-v{version}-{os_name}"

    target_dir = RELEASES_DIR / release_folder_name

    if target_dir.exists():
        print(f"  ├─ 发现同名打包文件夹，正在覆写: {release_folder_name}...")
        shutil.rmtree(target_dir)
    target_dir.mkdir()

    flutter_build_dir = APP_UI_DIR / "build" / "windows" / "x64" / "runner" / "Release"
    nuitka_build_dir = CORE_API_DIR / "build_out" / "main.dist"
    api_server_dir = target_dir / "api_server"

    print("  ├─ 正在拷贝前端界面资产...")
    shutil.copytree(flutter_build_dir, target_dir, dirs_exist_ok=True)

    # 将 Flutter 构建产出的 exe 重命名为中文名
    old_exe = target_dir / "invoice_system.exe"
    new_exe = target_dir / "发票管理系统.exe"
    if old_exe.exists():
        old_exe.rename(new_exe)
        print(f"  ├─ 已重命名: invoice_system.exe → 发票管理系统.exe")

    print("  ├─ 正在拷贝并挂载隐形后端引擎...")
    shutil.copytree(nuitka_build_dir, api_server_dir)

    # 4. 生成 zip 压缩包
    print("\n[4/5] 📦 正在压缩为 .zip 归档...")
    zip_base = str(target_dir)
    shutil.make_archive(zip_base, "zip", RELEASES_DIR, release_folder_name)
    zip_path = f"{zip_base}.zip"
    print(f"  ├─ ✅ 已生成: {zip_path}")

    # 5. 生成完整性校验工具
    print("\\n[5/5] 🔐 正在生成完整性校验工具...")
    print("=" * 60)
    manifest_json = _generate_hash_manifest(target_dir)
    _compile_integrity_checker(target_dir, manifest_json)

    print("=" * 60)
    print(f"🎉 恭喜！自动化打包圆满成功！")
    print(f"📂 你的软件已生成在: {target_dir}")
    print(f"📦 压缩包已生成在: {zip_path}")
    print(f"🔐 完整性校验工具: {target_dir}{chr(92)}完整性校验.exe")
    print("=" * 60)


if __name__ == "__main__":
    build_project()