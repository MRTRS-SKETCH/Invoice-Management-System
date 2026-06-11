# 发票管理系统

Windows 桌面应用 — 管理企业业务开销的全生命周期：开票 → 报销 → 核销完结，支持发票 PDF 拖拽绑定与在线预览。

## 架构

```
┌──────────────────────────────────────────────┐
│                  app_ui (Flutter)             │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │ 驾驶舱    │  │ 流水明细  │  │ PDF 预览    │  │
│  │ KPI/图表  │  │ 批量操作  │  │ 拖拽绑定    │  │
│  └──────────┘  └──────────┘  └────────────┘  │
│         │  HTTP :{auto_port}    │            │
│         ▼                       ▼            │
│  ┌───────────────────────────────────────┐    │
│  │        core_api (FastAPI)              │    │
│  │  routers → crud → SQLAlchemy → SQLite  │    │
│  │  端口自动扫描 (18090–18109)                   │    │
│  │  config/config.json 管理路径             │    │
│  └───────────────────────────────────────┘    │
│                                               │
│  Sidecar: Flutter 拉起后端 → 写 PID/port.txt  │
│  窗口关闭 → 强杀后端 → 清理 PID 文件            │
└──────────────────────────────────────────────┘
```

## 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| 前端 | Flutter 3.11+ · Dart | Windows 桌面，自定义标题栏，`window_manager` 窗口控制 |
| 后端 | FastAPI 0.136 · Uvicorn 0.46 | REST API，端口自动扫描 18090–18109，PID 文件管理 |
| ORM | SQLAlchemy 2.0 | 延迟初始化 + 连接池 + `Depends(get_db)` 依赖注入 |
| 校验 | Pydantic 2.13 | 请求/响应模型校验 |
| 数据库 | SQLite | WAL 模式，路径由 `config/config.json` 管理，用户可自定义 |
| 配置 | `config_manager.py` | JSON 配置中心，管理 db/log 路径、PDF 分片 |
| 日志 | Loguru（后端）+ `AppLogger`（前端） | 前端缓冲队列 → HTTP 批量上报后端统一落盘，路径可自定义 |
| 图表 | fl_chart | 热力图、环形图、进度条 |
| PDF | syncfusion_flutter_pdfviewer | 内嵌预览 + 拖拽绑定 |
| 发票解析 | pdfplumber（Python） | PDF 智能解析 → 自动提取金额/日期/类型并建档 |
| 拖拽 | desktop_drop | PDF 文件拖拽绑定 |
| 本地持久化 | ConfigStorage | 本地 JSON 持久化（`config/preferences.json`），100ms 防抖写入，存储表格列宽等 UI 状态 |
| 文件选择 | file_picker | 设置面板中浏览选择 db/log 存放目录 |

## 功能概览

| 功能 | 说明 |
|---|---|
| **统一驾驶舱** | 单页融合看板，5 组件并行：KPI 指标卡 · 业务热力图 · 多维度分析（项目进度 + 费用类型环形）· 流水明细表 · 发票 PDF 面板 |
| **状态流转** | `待开票 → 已开票 → 待报销 → 核销中 → 已完结`，支持自由切换；独立屏蔽旁路，可恢复原状态 |
| **批量操作** | 全选复选框 + 多选条目 → `Future.wait` 并发批量状态流转 / 屏蔽 / 恢复 / 删除，含二次确认 |
| **发票管理** | PDF 拖拽绑定到开销记录 · 智能解析自动建档（提取金额/日期/发票类型）· 内嵌预览 · 解绑自动清理物理 PDF 文件 |
| **PDF 分片存储** | 单目录 PDF 文件数达上限（默认 1000）时自动创建 `pdfs_1/`、`pdfs_2/` … 新分片 |
| **路径自定义** | 标题栏齿轮 ⚙ → 浏览选择数据库/日志存放目录 → 实时预览目录结构 → 保存后重启后端即生效 |
| **列宽定制** | 拖拽调整列宽 → 自动保存到本地，重启应用或缩放窗口均保持，不重置 |
| **隐私模式** | 一键切换金额明文 / `****`，KPI 卡片同步遮蔽 |
| **Sidecar 生命周期** | 启动：PID 文件清场 → 拉起后端 → 读 `port.txt` 获取实际端口 → 健康检查就绪后 UI 才发起请求；关闭：终止后端 + 删除 PID 文件 |
| **端口自适应** | 后端启动时自动扫描 18090–18109 首个可用端口，不抢其他程序占用的端口 |
| **沉浸式标题栏** | `TitleBarStyle.hidden` + 自绘标题栏，支持拖拽移动、最小化/最大化/关闭 |
| **完整性校验** | 打包后自动生成 `完整性校验.exe`，用户双击弹出 GUI 消息框，SHA256 逐文件比对 |

## 快速启动

### 环境要求

- **Flutter** SDK ≥ 3.11，Windows 桌面开发环境（Visual Studio 2022 + CMake）
- **Python** ≥ 3.10（开发模式需 conda 环境 `Invoice-Management-System`）

### 安装依赖

```bash
cd core_api && pip install -r requirements.txt uvicorn
cd app_ui && flutter pub get
```

### 开发模式

```bash
# 方式一：Sidecar 自动管理（推荐）
cd app_ui && flutter run -d windows
# Flutter 自动清场旧进程 → 拉起后端 → 读取端口 → UI 就绪

# 方式二：手动分离前后端
cd core_api && python main.py          # 终端 1：后端启动
cd app_ui && flutter run -d windows    # 终端 2：前端
```

> 开发模式下 Sidecar 自动选择 conda `python.exe`；生产模式使用 Nuitka 编译的 `main.exe`。

## 配置文件

首次运行自动在 `config/` 下生成 `config.json`（开发模式位于 `core_api/config/`，生产模式位于 `api_server/config/`）：

```json
{
  "db_path": "D:\\App\\api_server\\user_data",
  "log_path": "D:\\App\\api_server\\logs",
  "pdf_shard_size": 1000,
  "current_pdf_shard": 0,
  "shard_file_count": 0
}
```

- `db_path` — 数据库 `invoice_system.db` 存放目录
- `log_path` — 日志 `app.log` 存放目录
- `pdf_shard_size` — 单目录 PDF 文件数上限，超出自动分片

> 路径可通过标题栏齿轮 ⚙ → 路径设置面板修改。保存后目录结构立即创建；点击「重新连接」热重启后端即可生效。

## 项目结构

```
├── app_ui/                           # Flutter 前端
│   ├── lib/
│   │   ├── main.dart                 # 入口：窗口管理 + Sidecar 生命周期 + backendReady 信号
│   │   ├── config.dart               # AppConfig.baseUrl（启动时由 port.txt 动态更新）
│   │   ├── logger.dart               # 缓冲队列 → HTTP 批量日志上报
│   │   ├── services/
│   │   │   ├── expense_service.dart  # 全部 HTTP 请求 + Settings API
│   │   │   └── config_storage.dart   # 本地 JSON 持久化（config/preferences.json）
│   │   ├── widgets/
│   │   │   ├── custom_title_bar.dart    # 沉浸式标题栏 + 齿轮 ⚙ 设置入口
│   │   │   ├── settings_dialog.dart     # 路径设置：浏览选择 + 结构树预览 + 重新连接
│   │   │   └── glass_card.dart          # 毛玻璃容器组件
│   │   └── pages/dashboard/
│   │       ├── unified_dashboard_page.dart  # 驾驶舱编排页（等待 backendReady 后加载）
│   │       └── widgets/
│   │           ├── kpi_summary_card.dart    # 2×2 KPI 指标卡（隐私切换）
│   │           ├── heatmap_card.dart        # 近 90 天业务频次热力图
│   │           ├── dual_analysis_card.dart  # 项目进度条 + 类型环形图
│   │           ├── expense_table_panel.dart # 明细表：搜索/筛选/分页/全选/列宽拖拽持久化
│   │           ├── invoice_pdf_panel.dart   # PDF 预览 + 缩略图条 + 拖拽绑定
│   │           ├── add_expense_dialog.dart  # 新增开销对话框
│   │           ├── batch_upload_dialog.dart # 批量上传进度遮罩
│   │           └── column_width_manager.dart# 列宽持久化 mixin
│   ├── windows/                      # Windows 原生层 (C++/CMake)
│   └── pubspec.yaml                  # http, window_manager, desktop_drop, fl_chart,
│                                     #   syncfusion_flutter_pdfviewer, file_picker（shared_preferences
│                                     #   声明但实际未使用，已被 ConfigStorage 替代）
├── core_api/                         # Python 后端
│   ├── main.py                       # FastAPI 入口 · 端口扫描 · PID/port.txt · 自动建表
│   ├── requirements.txt
│   ├── pytest.ini                    # pytest 配置（unit/integration/slow 标记）
│   ├── tests/                        # pytest 测试套件
│   │   ├── conftest.py               # 全局 fixture（隔离环境 + 内存 SQLite）
│   │   ├── fixtures/                 # 共享测试数据夹具
│   │   ├── unit/                     # 单元测试（纯逻辑，无 IO）
│   │   └── integration/              # 集成测试（FastAPI TestClient）
│   └── app/
│       ├── database.py               # 延迟初始化 engine + 连接池 + WAL pragma
│       ├── models.py                 # ORM 表结构（uuuid 主键）
│       ├── schemas.py                # Pydantic v2 模型（含 Settings 系列）
│       ├── crud.py                   # 业务逻辑：CRUD + 状态机 + block/unblock + PDF 删除
│       ├── config_manager.py         # 配置中心：load/save、路径校验、PDF 分片、目录预览
│       ├── logger_config.py          # Loguru 初始化（参数化 log_path）
│       ├── routers/
│       │   ├── expenses.py           # /api/expenses
│       │   ├── invoices.py           # /api/invoices（PDF 分片）
│       │   ├── dashboard.py          # /api/dashboard
│       │   ├── client_logs.py        # /api/client-logs/batch
│       │   └── settings.py           # /api/settings — GET/PUT paths, validate, preview, restart
│       └── utils/
│           └── invoice_parser.py     # pdfplumber 解析发票 PDF
├── build_app.py                      # 一键生产打包（5 步：编译 + 拼装 + zip + 完整性校验）
├── integrity_checker.py              # 完整性校验模板（MANIFEST_B64 占位符，构建时注入）
├── AGENTS.md
└── LICENSE
```

## 生产打包

```bash
python build_app.py
```

打包流程：

1. **清理缓存** — 删除历史 `build_out/`、`main.dist/`、`build_ic/`、`app_ui/build/`
2. **编译后端** — Nuitka `--standalone` 将 `main.py` 编译为独立 `main.exe`
3. **编译前端** — `flutter build windows` 产出 `invoice_system.exe`
4. **拼装产物** — 合并至 `Releases/{项目名}-v{版本号}-{OS}/`，重命名为 `发票管理系统.exe`，生成 `.zip`
5. **完整性校验** — 扫描所有程序文件生成 SHA256 清单 → 注入模板 → Nuitka 编译 `完整性校验.exe`

打包产物示例：

```
Releases/Invoice-Management-System-v1.3.1-Windows/
├── 发票管理系统.exe
├── 完整性校验.exe
├── api_server/
│   ├── main.exe
│   └── config/               ← 运行时创建（含 config.json, backend.pid, port.txt）
├── …（dll, data 等）
└── Invoice-Management-System-v1.3.1-Windows.zip
```

> 分发时只需提供 `.zip` 文件或整个文件夹。用户解压后双击 `发票管理系统.exe` 即可运行，双击 `完整性校验.exe` 可验证文件是否被篡改。

## 版权

[PolyForm Noncommercial](./LICENSE)
