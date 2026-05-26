# REASONIX.md — 对公报销与发票管理系统

## 技术栈
- **前端:** Flutter 3.11 (Dart) + Material Design 3 — Windows 桌面应用
- **后端:** FastAPI 0.136 + Uvicorn 0.46 (Python 3)
- **ORM:** SQLAlchemy 2.0 + `Depends(get_db)` 依赖注入
- **校验:** Pydantic 2.13
- **日志:** Loguru (后端) + Flutter 批量 HTTP 上报
- **数据库:** SQLite → `core_api/user_data/invoice_system.db`
- **关键 Flutter 依赖:** `window_manager`, `desktop_drop`, `syncfusion_flutter_pdfviewer`, `fl_chart`

## 目录结构
- `app_ui/lib/` — Flutter 页面、`config.dart`(后端地址)、`logger.dart`(日志上报)、`widgets/`(自定义标题栏等)
- `core_api/main.py` — FastAPI 入口 + Loguru 初始化 + `Base.metadata.create_all` 建表
- `core_api/app/routers/` — `expenses` `invoices` `dashboard` `client_logs`
- `core_api/app/models.py` — `ExpenseRecord` / `InvoiceRecord`，主键 `uuuid`
- `core_api/app/crud.py` — CRUD + 五段状态机校验 (`VALID_TRANSITIONS`) + 聚合统计
- `core_api/app/database.py` — SQLite 引擎 + `Base` + `get_db` 依赖注入
- `core_api/user_data/` — SQLite DB + `pdfs/`（gitignored）
- `core_api/logs/` — `app.log`（gitignored）

## 常用命令
```bash
cd core_api && python main.py          # 后端 → 127.0.0.1:8000
cd app_ui && flutter run -d windows    # Flutter 桌面应用
```

## 编码规范
- **主键拼写 `uuuid`** — 模型字段、API 路径参数、Dart 变量统一使用
- **API 前缀** `/api/expenses` `/api/invoices` `/api/dashboard` `/api/client-logs`
- **状态流转:** 待开票→已开票→待报销→核销中→已完结，`VALID_TRANSITIONS` 白名单校验，非法跳转 422
- **中文优先:** 注释、docstring、API tags、UI 文案
- **日志:** `from loguru import logger` + `{}` 占位符；异常用 `logger.opt(exception=True).error()`
- **DB 会话:** `db: Session = Depends(get_db)`，异常分支需 `db.rollback()`
- **Flutter 后端地址:** 通过 `AppConfig.baseUrl` 引用，禁止硬编码
- **Flutter lint:** `package:flutter_lints/flutter.yaml`

## 注意事项
- **`Base` 统一来源:** 建表用 `database.py` 的 `Base`，`models.py` 从 `database` 导入
- **CORS 已移除:** 本地桌面端无需跨域
- **级联删除:** `delete_expense` 自动清理关联发票行 + 物理 PDF
- **Flutter 日志上报:** 缓冲 ≥50 条或 2 秒，fire-and-forget，后端不可达静默丢弃
- **stdout 不重复上报:** 后端输出仅 debug 模式打印到 Flutter 控制台
- **自定义标题栏:** `DragToMoveArea` 仅包裹左侧标题，右侧窗口按钮脱离拖拽区避免手势竞技
- **发票页局部刷新:** `ValueNotifier` + `ValueListenableBuilder` 隔离 PDF 预览，左侧选中不触发整页重建
