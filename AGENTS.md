# Repository Guidelines

## Project Structure & Module Organization

```
├── app_ui/                  # Flutter 桌面前端 (Dart)
│   ├── lib/
│   │   ├── main.dart        # 入口：窗口管理、Sidecar 生命周期
│   │   ├── config.dart      # AppConfig.baseUrl 等全局配置
│   │   ├── logger.dart      # 缓冲队列 → HTTP 批量日志上报
│   │   ├── services/        # HTTP 请求封装 (静态方法)
│   │   ├── widgets/         # 通用 UI 组件 (自定义标题栏、毛玻璃容器)
│   │   └── pages/           # 页面编排
│   └── pubspec.yaml
├── core_api/                # Python 后端 (FastAPI)
│   ├── main.py              # 应用入口 · 自动建表 · 路由挂载
│   ├── requirements.txt
│   └── app/
│       ├── database.py      # SQLAlchemy 连接池 + Base 声明
│       ├── models.py        # ORM 表结构 (uuuid 主键)
│       ├── schemas.py       # Pydantic 请求/响应模型
│       ├── crud.py          # 业务逻辑 + 状态机 + PDF 物理删除
│       ├── logger_config.py # Loguru 初始化
│       └── routers/         # /api/expenses · /api/invoices · /api/dashboard · /api/client-logs
├── build_app.py             # 一键生产打包 (Nuitka + Flutter build)
└── Releases/                # 打包产物
```

- **前端**通过 HTTP 访问 `127.0.0.1:18090` 与后端通信。
- **后端**使用 SQLite（文件位于 `core_api/user_data/invoice_system.db`），无外部数据库依赖。
- Sidecar 模式：Flutter 启动时自动拉起 Python 后端进程，窗口关闭时强杀。

## Build, Test, and Development Commands

| 命令 | 说明 |
|---|---|
| `cd core_api && pip install -r requirements.txt` | 安装 Python 后端依赖 |
| `cd app_ui && flutter pub get` | 安装 Flutter 前端依赖 |
| `cd app_ui && flutter run -d windows` | **开发模式（推荐）** — Sidecar 自动清场旧进程并拉起后端 |
| `cd core_api && python main.py` | 单独启动后端 (监听 `:18090`)，用于分离调试 |
| `python build_app.py` | **生产打包** — 依次执行 Nuitka 编译后端 → Flutter build windows → 合并产物至 `Releases/` |
| `cd app_ui && flutter test` | 运行 Flutter 单元测试 |

> 开发模式需要 conda 环境 `Invoice-Management-System` (Python ≥ 3.10)，生产模式使用 Nuitka 编译的 `main.exe`。

## Coding Style & Naming Conventions

### Python (core_api/)
- **缩进**：4 空格，无制表符。
- **命名**：`snake_case` 用于变量、函数、模块；`PascalCase` 用于类名；`UPPER_CASE` 用于模块级常量。
- **类型注解**：所有函数必须标注参数和返回类型；使用 `str | None` 替代 `Optional[str]`。
- **注释**：模块顶部使用 `# ── 分隔注释 ──` 风格划分逻辑区块。docstring 使用 `"""描述"""` 格式。
- **日志**：统一使用 `loguru.logger`，格式为 `logger.info("描述 | key={} value={}", ...)`。

### Dart/Flutter (app_ui/)
- **缩进**：2 空格（Flutter 标准）。
- **命名**：`camelCase` 用于变量、函数；`PascalCase` 用于类名和文件名对应的大类。
- **Lint**：使用 `flutter_lints` 包，配置文件为 `app_ui/analysis_options.yaml`。
- **日志**：使用自定义 `AppLogger`（位于 `lib/logger.dart`），前端日志通过 HTTP 批量上报到后端统一落盘。

## Testing Guidelines

- **Flutter**：测试文件放在 `app_ui/test/` 下，使用 `flutter_test` SDK 包，运行 `flutter test`。
- **Python**：当前无独立测试套件，后端通过 FastAPI 自带的 `/docs` Swagger UI 进行手动接口验证。
- 新增功能请补充对应测试，优先覆盖 CRUD 和状态流转逻辑。

## Commit & Pull Request Guidelines

- **提交信息**使用简体中文，简洁描述变更内容。参考历史记录：
  - `v1.1.1桌面级发票管理系统` — 版本发布
  - `重构启动项并本地化应用程序名称` — 重构描述
  - `添加统一的仪表盘用户界面和配套小部件` — 功能添加
- **PR 要求**：
  - 描述清楚改动目的和影响范围。
  - 涉及状态机流转或数据库 schema 变更时，必须附测试截图或 Swagger 验证结果。
  - 前端 UI 变更需附带运行截图。

## Architecture Overview

- **五段状态机**：`待开票 → 已开票 → 待报销 → 核销中 → 已完结`，`已屏蔽` 为独立旁路状态。
- **发票绑定**：PDF 文件拖拽绑定到开销记录，物理存储于 `core_api/user_data/pdfs/`，解绑时自动清理物理文件。
- **端口管理**：后端固定监听 `127.0.0.1:18090`，启动前通过 `netstat` 反查 PID 强杀残留进程。

## Security & Configuration

- 桌面本地应用，无 CORS 配置需求（CORS 中间件已移除）。
- 后端仅监听 `127.0.0.1`，不接受外部网络连接。
- 生产打包使用 Nuitka `--standalone` 模式，Python 源码不对外暴露。
- 前端日志上报不包含敏感个人信息。
