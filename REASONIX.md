# REASONIX.md — 对公报销与发票管理系统

## Stack
- **前端:** Flutter 3.11+ (Dart), Windows 桌面 — `window_manager`, `fl_chart`, `syncfusion_flutter_pdfviewer`
- **后端:** FastAPI 0.136 + Uvicorn 0.46 (Python 3)
- **ORM:** SQLAlchemy 2.0 + `Depends(get_db)` / **校验:** Pydantic 2.13
- **日志:** Loguru（后端 `{}` 占位符）+ Flutter `logger.dart` HTTP 批量上报
- **数据库:** SQLite → `core_api/user_data/invoice_system.db`

## Layout
- `app_ui/lib/main.dart` — Sidecar 启动器 + `CustomTitleBar` + `UnifiedDashboardPage`
- `app_ui/lib/pages/dashboard/` — `unified_dashboard_page.dart`（编排）+ `widgets/`（5 组件）
- `app_ui/lib/services/expense_service.dart` — 全部 HTTP 请求（静态方法）
- `app_ui/lib/widgets/` — `glass_card.dart`（毛玻璃）、`custom_title_bar.dart`
- `core_api/main.py` — FastAPI 入口 + `Base.metadata.create_all`，监听 `127.0.0.1:18090`
- `core_api/app/` — `routers/`, `models.py`, `schemas.py`, `crud.py`, `database.py`
- `build_app.py` — Nuitka 打包脚本

## Commands
```bash
cd core_api && python main.py           # 后端 → 127.0.0.1:18090
cd app_ui && flutter run -d windows     # Flutter 桌面应用
python build_app.py                     # Nuitka 生产打包
```

## Conventions
- **主键拼写 `uuuid`** — 模型/API/Flutter 变量统一，不用 `uuid`
- **API 前缀** `/api/expenses` `/api/invoices` `/api/dashboard` `/api/client-logs`
- **五段状态机:** 待开票→已开票→待报销→核销中→已完结（`VALID_TRANSITIONS` 白名单）
- **中文优先:** 注释、docstring、API tags、UI 文案均用中文
- **日志:** `from loguru import logger`；异常用 `logger.opt(exception=True).error()`
- **DB 异常处理:** `db.rollback()` 必须在 `raise` 之前调用
- **Flutter 后端地址:** `AppConfig.baseUrl`（`config.dart`），禁止硬编码
- **Flutter lint:** `flutter_lints/flutter.yaml`；导入用相对路径（`../../services/`）
- **`Base` 统一来源:** `database.py` 导出，其余模块从 `database` 导入

## Watch out for
- **Sidecar 生命周期:** Flutter 启动自动拉起 Python（conda `python.exe` / Nuitka `main.exe`）；`_cleanGhostProcess()` 端口 `:18090` 强杀残留；窗口关闭自动终止后端
- **`expense_type` 迁移:** 旧库需 `ALTER TABLE expenses ADD COLUMN expense_type TEXT;`
- **级联删除:** `delete_expense` 自动清理关联发票行 + 物理 PDF 文件
- **PDF 路径:** `crud.py` 通过 `Path(__file__).resolve().parent.parent` 拼绝对路径；`saved_path` 存相对路径 `user_data/pdfs/xxx.pdf`
- **标题栏手势:** `DragToMoveArea` 仅包标题文字，窗口按钮（最小化/关闭）在拖拽区外避免竞技
