# REASONIX.md — 发票管理系统

## Stack
- **前端:** Flutter 3.11+ (Dart) — `window_manager` `fl_chart` `syncfusion_flutter_pdfviewer` `desktop_drop`
- **后端:** FastAPI 0.136 + Uvicorn 0.46 (Python 3) + Loguru
- **数据:** SQLAlchemy 2.0 + Pydantic 2.13 + SQLite (WAL)
- **日志:** Loguru `{}` 占位符 + Flutter `AppLogger` HTTP 批量上报

## Layout
- `app_ui/lib/main.dart` — Sidecar 生命周期 + 窗口管理 + 驾驶舱入口
- `app_ui/lib/pages/dashboard/` — `unified_dashboard_page.dart`（编排）+ `widgets/`（5 组件）
- `app_ui/lib/services/expense_service.dart` — 全部 HTTP 请求（静态方法）
- `app_ui/lib/widgets/` — `glass_card.dart` `custom_title_bar.dart`
- `app_ui/windows/runner/` — 原生 Win32 层（`main.cpp` `flutter_window.cpp` `win32_window.cpp`）
- `app_ui/windows/CMakeLists.txt` — `BINARY_NAME = invoice_system`（打包时重命名为 `发票管理系统.exe`）
- `core_api/main.py` — FastAPI 入口 + 自动建表，监听 `127.0.0.1:18090`
- `core_api/app/` — `routers/` `models.py` `schemas.py` `crud.py` `database.py` `logger_config.py`
- `build_app.py` — 一键生产打包（Nuitka + Flutter build）

## Commands
```bash
cd core_api && python main.py       # 后端 → 127.0.0.1:18090
cd app_ui && flutter run -d windows # Flutter 桌面
python build_app.py                 # 生产打包
```

## Conventions
- **主键拼写 `uuuid`** — 模型/API/Flutter 统一，不用 `uuid`
- **API 前缀** `/api/expenses` `/api/invoices` `/api/dashboard` `/api/client-logs`
- **五段状态机** — 待开票→已开票→待报销→核销中→已完结（`VALID_TRANSITIONS` 白名单）
- **中文优先** — 注释、docstring、API tags、UI 文案均用中文
- **日志** — `from loguru import logger`；异常用 `logger.opt(exception=True).error()`；Flutter 用 `AppLogger`
- **DB 异常** — `db.rollback()` 必须在 `raise` 之前
- **Flutter** — `AppConfig.baseUrl` 禁止硬编码；lint: `flutter_lints/flutter.yaml`；相对路径导入
- **`Base`** — 统一从 `database.py` 导入

## Watch out for
- **Sidecar** — 启动自动拉起 Python（dev: conda / prod: Nuitka `main.exe`）；`_cleanGhostProcess()` 端口 `:18090` 强杀残留；窗口关闭终止后端
- **窗口** — `flutter_window.cpp` 的 `Show()` 已禁用，`window_manager.waitUntilReadyToShow` 统一控显；`win32_window.cpp` 画刷 `RGB(226,232,240)`
- **C++ 编码** — `/WX` 警告即错误，`.cpp` 禁止非 ASCII（C4819→C2220）
- **打包** — CMake 产 `invoice_system.exe`，`build_app.py` 重命名为 `发票管理系统.exe`
- **级联删除** — `delete_expense` 清理关联发票行 + 物理 PDF
- **PDF 路径** — `Path(__file__).resolve().parent.parent` 拼绝对路径；`saved_path` 存相对路径
- **标题栏** — `DragToMoveArea` 仅包标题文字，窗口按钮在拖拽区外
