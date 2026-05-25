import subprocess
import shutil
from pathlib import Path
from datetime import datetime

# 获取项目根目录绝对路径
ROOT_DIR = Path(__file__).parent.resolve()
CORE_API_DIR = ROOT_DIR / "core_api"
APP_UI_DIR = ROOT_DIR / "app_ui"
RELEASES_DIR = ROOT_DIR / "Releases"


def run_command(command, cwd, step_name):
    """运行终端命令并实时打印输出"""
    print(f"\n[{step_name}] 正在执行: {' '.join(command)}")
    try:
        subprocess.run(command, cwd=cwd, check=True, shell=True)
        print(f"✅ [{step_name}] 执行成功！")
    except subprocess.CalledProcessError as e:
        print(f"\n❌ [{step_name}] 严重失败！错误码: {e.returncode}")
        exit(1)


def build_project():
    print("=" * 60)
    print("      🚀 财务发票管理系统 - 全自动构建引擎 🚀")
    print("=" * 60)

    # 1. 编译 Python 后端
    nuitka_cmd = [
        "nuitka",
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
    flutter_cmd = ["flutter", "build", "windows"]
    run_command(flutter_cmd, cwd=APP_UI_DIR, step_name="2/3 编译 Flutter 桌面端")

    # 3. 拼装终极产物
    print("\n[3/3] 正在拼装终极完全体文件夹...")

    # 如果 Releases 根目录不存在，则创建它
    if not RELEASES_DIR.exists():
        RELEASES_DIR.mkdir()

    # 🌟 动态生成带日期的文件夹名称 (例如: 20260525_财务发票管理系统)
    date_str = datetime.now().strftime("%Y%m%d")
    release_folder_name = f"{date_str}_财务发票管理系统"
    TARGET_DIR = RELEASES_DIR / release_folder_name

    # 如果今天已经打过包了，先清理掉旧的同名文件夹，保持干净
    if TARGET_DIR.exists():
        shutil.rmtree(TARGET_DIR)
    TARGET_DIR.mkdir()

    # 定义源路径
    flutter_build_dir = APP_UI_DIR / "build" / "windows" / "x64" / "runner" / "Release"
    nuitka_build_dir = CORE_API_DIR / "build_out" / "main.dist"
    api_server_dir = TARGET_DIR / "api_server"

    print("  ├─ 正在拷贝前端界面资产...")
    shutil.copytree(flutter_build_dir, TARGET_DIR, dirs_exist_ok=True)

    print("  ├─ 正在拷贝并挂载隐形后端引擎...")
    shutil.copytree(nuitka_build_dir, api_server_dir)

    print("=" * 60)
    print(f"🎉 恭喜！自动化打包圆满成功！")
    print(f"📂 你的软件已生成在: {TARGET_DIR}")
    print("=" * 60)


if __name__ == "__main__":
    build_project()