import subprocess
import shutil
import sys
from pathlib import Path
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
    print("      🚀 发票管理系统 - 全自动构建引擎 🚀")
    print("=" * 60)

    # 0. 先行清理历史缓存
    clean_caches()

    # 1. 编译 Python 后端
    nuitka_cmd = [
        sys.executable, "-m", "nuitka",
        "--standalone",
        "--windows-console-mode=disable",
        "--show-progress",
        # "--show-scons",  # 实时日志打印
        "--lto=yes",                         # 开启链路优化
        "--remove-output",                   # 编译完成后清除缓存
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

    # 动态生成目录名: Invoice-Management-System-v1.2.1-Windows
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
    print("\n[4/4] 📦 正在压缩为 .zip 归档...")
    zip_base = str(target_dir)
    shutil.make_archive(zip_base, "zip", RELEASES_DIR, release_folder_name)
    zip_path = f"{zip_base}.zip"
    print(f"  ├─ ✅ 已生成: {zip_path}")

    print("=" * 60)
    print(f"🎉 恭喜！自动化打包圆满成功！")
    print(f"📂 你的软件已生成在: {target_dir}")
    print(f"📦 压缩包已生成在: {zip_path}")
    print("=" * 60)


if __name__ == "__main__":
    build_project()