# REASONIX.md — 对公报销与发票管理系统

## 技术栈
- **前端:** Flutter 3.11 (Dart) + Material Design 3 — Windows 桌面应用
- **后端:** FastAPI 0.136 + Uvicorn 0.46 (Python 3)
- **ORM:** SQLAlchemy 2.0 + `Depends(get_db)` 依赖注入
- **校验:** Pydantic 2.13 | **日志:** Loguru (后端) + Flutter 批量 HTTP 上报
- **数据库:** SQLite → `core_api/user_data/invoice_system.db`

## 目录结构
- `app_ui/lib/` — Flutter 页面、`config.dart`、`unified_dashboard_page.dart`、`widgets/`
- `core_api/main.py` — FastAPI 入口 + Loguru + `Base.metadata.create_all` 建表，监听 `127.0.0.1:18090`
- `core_api/app/routers/` — `expenses` `invoices` `dashboard` `client_logs`
- `core_api/app/models.py` — `ExpenseRecord`（含 `project_name`/`expense_type`）/ `InvoiceRecord`，主键 `uuuid`
- `core_api/app/crud.py` — CRUD + 五段状态机 + 聚合统计 (heatmap/type-distribution/summary/trend)
- `core_api/app/database.py` — SQLite 引擎 + `Base` + `get_db`

## 常用命令
```bash
cd core_api && python main.py          # 后端 → 127.0.0.1:18090
cd app_ui && flutter run -d windows    # Flutter 桌面应用
```

## 编码规范
- **主键拼写 `uuuid`** — 模型/API 路径/Dart 变量统一使用
- **API 前缀** `/api/expenses` `/api/invoices` `/api/dashboard` `/api/client-logs`
- **状态流转 (5段):** 待开票→已开票→待报销→核销中→已完结，`VALID_TRANSITIONS` 白名单校验
- **中文优先:** 注释、docstring、API tags、UI 文案
- **日志:** `from loguru import logger` + `{}` 占位符；异常用 `logger.opt(exception=True).error()`
- **DB 会话:** `db: Session = Depends(get_db)`，异常分支需 `db.rollback()`
- **Flutter lint:** `package:flutter_lints/flutter.yaml`

## Sidecar 架构
- Flutter 启动 spawn Python 后端：开发用 conda `python.exe main.py`，生产用 Nuitka `main.exe`
- 启动前 `_cleanGhostProcess()` 通过 `:18090` 强杀残留进程；窗口关闭自动 kill 后端

## 前端（已重构为单页驾驶舱）
- `unified_dashboard_page.dart` 替代原 NavigationRail 三页签
- 顶部：KPI(2.5) + 热力图(4.0) + 双维分析(3.5)；下方：DataTable(6.5) + PDF预览(3.5)
- 毛玻璃卡片：`BackdropFilter` + `white.withValues(alpha:0.75)` + `shadow alpha:0.03`
- 金额隐私切换、5 段状态按钮、`Autocomplete` 下拉可输入项目/类型

## 注意事项
- **`Base` 统一来源:** 建表用 `database.py` 的 `Base`，`models.py` 从 `database` 导入
- **`expense_type` 是新字段:** 旧 DB 需 `ALTER TABLE expenses ADD COLUMN expense_type TEXT;`
- **级联删除:** `delete_expense` 自动清理关联发票行 + 物理 PDF
- **PDF 路径:** `saved_path` 相对路径，crud.py 用 `Path(__file__).resolve().parent.parent` 拼绝对路径
- **自定义标题栏:** `DragToMoveArea` 仅包裹左侧标题，右侧按钮脱离拖拽区避免手势竞技
- **旧页面保留未删:** `dashboard_page.dart` / `expense_flow_page.dart` / `invoice_manager_page.dart`
