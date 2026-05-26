import subprocess
import shutil
import sys
from pathlib import Path
from datetime import datetime

# 全局常量定义 (保持大写)
ROOT_DIR = Path(__file__).parent.resolve()
CORE_API_DIR = ROOT_DIR / "core_api"
APP_UI_DIR = ROOT_DIR / "app_ui"
RELEASES_DIR = ROOT_DIR / "Releases"


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


def clean_caches():
    """清理上一次打包留下的所有中间缓存"""
    print("\n[0/3] 🧹 正在清理旧版本的中间缓存...")

    caches_to_clean = [
        CORE_API_DIR / "build_out",
        CORE_API_DIR / "main.build",
        CORE_API_DIR / "main.dist",
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
    print("      🚀 财务发票管理系统 - 全自动构建引擎 🚀")
    print("=" * 60)

    # 0. 先行清理历史缓存
    clean_caches()

    # 1. 编译 Python 后端
    nuitka_cmd = [
        sys.executable, "-m", "nuitka",
        "--standalone",
        "--windows-console-mode=disable",
        "--include-package=uvicorn",
        "--include-package=sqlalchemy",
        "--include-package=pydantic",
        "--include-package=fastapi",
        "--output-dir=build_out",
        "main.py"
    ]
    run_command(nuitka_cmd, cwd=CORE_API_DIR, step_name="1/3 编译后端独立引擎")

    # 2. 编译 Flutter 前端
    flutter_exe = shutil.which("flutter")
    if not flutter_exe:
        print("\n❌ 找不到 Flutter 环境，请确保已将 Flutter 添加到系统 PATH 中！")
        sys.exit(1)

    flutter_cmd = [flutter_exe, "build", "windows"]
    run_command(flutter_cmd, cwd=APP_UI_DIR, step_name="2/3 编译 Flutter 桌面端")

    # 3. 拼装终极产物
    print("\n[3/3] 📦 正在拼装终极完全体文件夹...")

    if not RELEASES_DIR.exists():
        RELEASES_DIR.mkdir()

    date_str = datetime.now().strftime("%Y%m%d")
    release_folder_name = f"{date_str}_财务发票管理系统"

    # 【已修正】函数内部的局部变量采用小写加下划线命名规范
    target_dir = RELEASES_DIR / release_folder_name

    if target_dir.exists():
        print(f"  ├─ 发现今日已有同名打包文件夹，正在覆写: {release_folder_name}...")
        shutil.rmtree(target_dir)
    target_dir.mkdir()

    flutter_build_dir = APP_UI_DIR / "build" / "windows" / "x64" / "runner" / "Release"
    nuitka_build_dir = CORE_API_DIR / "build_out" / "main.dist"
    api_server_dir = target_dir / "api_server"

    print("  ├─ 正在拷贝前端界面资产...")
    shutil.copytree(flutter_build_dir, target_dir, dirs_exist_ok=True)

    print("  ├─ 正在拷贝并挂载隐形后端引擎...")
    shutil.copytree(nuitka_build_dir, api_server_dir)

    print("=" * 60)
    print(f"🎉 恭喜！自动化打包圆满成功！")
    print(f"📂 你的软件已生成在: {target_dir}")
    print("=" * 60)


if __name__ == "__main__":
    build_project()