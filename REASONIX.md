# REASONIX.md — 对公报销与发票管理系统

## 技术栈
- **前端:** Flutter (Dart 3.11, Material Design 3) — Windows 桌面应用
- **后端:** FastAPI 0.136 + Uvicorn 0.46 (Python 3)
- **ORM:** SQLAlchemy 2.0 + Session 依赖注入
- **校验:** Pydantic 2.13
- **日志:** Loguru 后端 + Flutter 批量 HTTP 上报 → `core_api/logs/app.log`
- **数据库:** SQLite → `core_api/user_data/invoice_system.db`

## 目录结构
- `app_ui/lib/` — Flutter 页面 + `config.dart`（后端地址）+ `logger.dart`（批量上报）
- `core_api/main.py` — FastAPI 入口 + `setup_loguru()` 初始化
- `core_api/app/logger_config.py` — Loguru 配置（enqueue/100MB 轮转/30天/zip/拦截 Uvicorn）
- `core_api/app/routers/` — `expenses` `invoices` `dashboard` `client_logs`
- `core_api/app/models.py` — `ExpenseRecord` / `InvoiceRecord`，主键 `uuuid`
- `core_api/app/crud.py` — CRUD + 五段状态机校验 + 聚合统计
- `core_api/user_data/` — SQLite DB + `pdfs/`（.gitignore）
- `core_api/logs/` — `app.log`（.gitignore）

## 常用命令
```bash
cd core_api && python main.py          # 后端 127.0.0.1:8000
cd app_ui && flutter run -d windows    # 前端桌面应用
```

## 编码规范
- **主键 `uuuid`** — 模型字段 + API 路径参数统一使用此拼写
- **API 前缀:** `/api/expenses` `/api/invoices` `/api/dashboard` `/api/client-logs`
- **中文优先:** 注释、docstring、API 标签、UI 文案均中文
- **日志:** `from loguru import logger` + `{}` 占位符；异常用 `logger.opt(exception=True).error()`
- **DB 会话:** `db: Session = Depends(get_db)`，异常需 `db.rollback()`
- **后端地址:** Flutter 通过 `AppConfig.baseUrl` 引用，禁止硬编码
- **状态流转:** 待开票→已开票→待报销→核销中→已完结，`VALID_TRANSITIONS` 校验，非法跳转 422
- **Flutter lint:** `package:flutter_lints/flutter.yaml`

## 注意事项
- **Flutter Conda 路径硬编码:** `C:/Users/ninpa/miniconda3/envs/Invoice-Management-System/python.exe` — 仅原开发者本机
- **Python 子进程启动:** `-X utf8 -u` + 环境变量 `PYTHONIOENCODING=utf-8` `PYTHONUTF8=1`
- **Dart 解码:** `utf8.decode(bytes, allowMalformed: true)` 兜底非 UTF-8 字节
- **Flutter 日志上报:** 缓冲 ≥50 条或 2 秒 `POST /api/client-logs/batch`，fire-and-forget，后端不可达静默丢弃
- **stdout 不重复上报:** 后端输出仅 debug 模式打印到 Flutter 控制台，防止 Uvicorn 访问日志循环
- **级联删除:** `delete_expense` 自动清理关联发票行 + 物理 PDF
- **CORS:** `allow_origins=["*"]`
- **`Base` 统一:** `database.py` 的 `Base`，建表用 `Base.metadata.create_all`
