# 发票管理系统

Windows 桌面应用 — 管理企业业务开销的全生命周期：开票 → 报销 → 核销完结，支持发票 PDF 拖拽绑定与在线预览。

## 架构

```
┌─────────────────────────────────────────────┐
│                  app_ui (Flutter)            │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │ 驾驶舱    │  │ 流水明细  │  │ PDF 预览   │  │
│  │ KPI/图表  │  │ 批量操作  │  │ 拖拽绑定   │  │
│  └──────────┘  └──────────┘  └───────────┘  │
│         │  HTTP :18090         │            │
│         ▼                      ▼            │
│  ┌──────────────────────────────────────┐    │
│  │        core_api (FastAPI)             │    │
│  │  routers → crud → SQLAlchemy → SQLite │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  Sidecar: Flutter 启动自动拉起 Python 后端    │
│  窗口关闭 → 强杀后端进程 → 端口 18090 无残留  │
└─────────────────────────────────────────────┘
```

## 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| 前端 | Flutter 3.11+ · Dart | Windows 桌面，自定义标题栏，`window_manager` 窗口控制 |
| 后端 | FastAPI 0.136 · Uvicorn 0.46 | REST API，监听 `127.0.0.1:18090` |
| ORM | SQLAlchemy 2.0 | 连接池 + `Depends(get_db)` 依赖注入 |
| 校验 | Pydantic 2.13 | 请求/响应模型校验 |
| 数据库 | SQLite | `core_api/user_data/invoice_system.db`，WAL 模式 |
| 日志 | Loguru（后端）+ 自定义 `AppLogger`（前端） | 前端缓冲队列 → HTTP 批量上报后端统一落盘 |
| 图表 | fl_chart | 热力图、环形图、进度条 |
| PDF | syncfusion_flutter_pdfviewer | 内嵌预览 + 拖拽绑定 |
| 发票解析 | pdfplumber（Python） | PDF 智能解析 → 自动提取金额/日期/类型并建档 |
| 拖拽 | desktop_drop | PDF 文件拖拽绑定 |
| 本地持久化 | shared_preferences | 表格列宽记忆，重启/缩放不变 |

## 功能概览

| 功能 | 说明 |
|---|---|
| **统一驾驶舱** | 单页融合看板，5 组件并行：KPI 指标卡 · 业务热力图 · 多维度分析（项目进度 + 费用类型环形）· 流水明细表 · 发票 PDF 面板 |
| **状态流转** | `待开票 → 已开票 → 待报销 → 核销中 → 已完结`，支持自由切换；独立屏蔽旁路，可恢复原状态 |
| **批量操作** | 全选复选框 + 多选条目 → `Future.wait` 并发批量状态流转 / 屏蔽 / 恢复 / 删除，含二次确认 |
| **发票管理** | PDF 拖拽绑定到开销记录 · 智能解析自动建档（提取金额/日期/发票类型）· 内嵌预览 · 解绑自动清理物理 PDF 文件 |
| **列宽定制** | 拖拽调整列宽 → 自动保存到本地，重启应用或缩放窗口均保持，不重置 |
| **隐私模式** | 一键切换金额明文 / `****`，KPI 卡片同步遮蔽 |
| **Sidecar 生命周期** | Flutter 启动 → 自动清场旧进程（端口反查强杀）→ 拉起 Python 后端；窗口关闭 → 终止后端 → 销毁窗口，零残留 |
| **沉浸式标题栏** | `TitleBarStyle.hidden` + 自绘标题栏，支持拖拽移动、最小化/最大化/关闭，无手势竞技延迟 |
| **零白屏启动** | 原生 Win32 窗口创建后保持隐藏，由 `window_manager` 在首帧渲染后统一居中显示，背景画刷匹配主题色 |

## 快速启动

### 环境要求

- **Flutter** SDK ≥ 3.11，Windows 桌面开发环境（Visual Studio 2022 + CMake）
- **Python** ≥ 3.10（开发模式需 conda 环境 `Invoice-Management-System`）

### 安装依赖

```bash
cd core_api && pip install -r requirements.txt
cd app_ui && flutter pub get
```

### 开发模式

```bash
# 方式一：Sidecar 自动管理（推荐）
cd app_ui && flutter run -d windows
# Flutter 自动清场旧进程 → 拉起后端 → 窗口就绪后显示

# 方式二：手动分离前后端
cd core_api && python main.py          # 终端 1：后端 → :18090
cd app_ui && flutter run -d windows    # 终端 2：前端
```

> 开发模式下 Sidecar 自动选择 conda `python.exe`；生产模式使用 Nuitka 编译的 `main.exe`。

## 项目结构

```
├── app_ui/                        # Flutter 前端
│   ├── lib/
│   │   ├── main.dart              # 入口：窗口管理 + Sidecar 生命周期
│   │   ├── config.dart            # AppConfig.baseUrl
│   │   ├── logger.dart            # 缓冲队列 → HTTP 批量日志上报
│   │   ├── services/
│   │   │   └── expense_service.dart  # 全部 HTTP 请求（静态方法，Future.wait 并发）
│   │   ├── widgets/
│   │   │   ├── custom_title_bar.dart # 沉浸式自定义标题栏
│   │   │   └── glass_card.dart       # 毛玻璃容器组件
│   │   └── pages/dashboard/
│   │       ├── unified_dashboard_page.dart  # 驾驶舱编排页（状态持有 + KPI 预计算）
│   │       └── widgets/
│   │           ├── kpi_summary_card.dart    # 2×2 KPI 指标卡（隐私切换）
│   │           ├── heatmap_card.dart        # 近 90 天业务频次热力图（右对齐）
│   │           ├── dual_analysis_card.dart  # 项目进度条 + 类型环形图
│   │           ├── expense_table_panel.dart # 明细表：搜索/筛选/分页/全选/列宽拖拽持久化
│   │           └── invoice_pdf_panel.dart   # PDF 预览 + 缩略图条 + 拖拽绑定
│   ├── windows/                   # Windows 原生层 (C++/CMake)
│   │   ├── CMakeLists.txt         # BINARY_NAME = invoice_system
│   │   └── runner/
│   │       ├── main.cpp           # Win32 入口
│   │       ├── flutter_window.cpp # 首帧回调（Show 已禁用，交由 window_manager）
│   │       └── win32_window.cpp   # 窗口类注册 + 主题背景画刷
│   └── pubspec.yaml               # http, window_manager, shared_preferences, desktop_drop, fl_chart, syncfusion_flutter_pdfviewer
├── core_api/                      # Python 后端
│   ├── main.py                    # FastAPI 入口 · 自动建表
│   ├── requirements.txt
│   └── app/
│       ├── database.py            # 连接池 + Base 声明 + WAL pragma
│       ├── models.py              # ORM 表结构（uuuid 主键，ExpenseRecord + InvoiceRecord）
│       ├── schemas.py             # Pydantic v2 请求/响应模型
│       ├── crud.py                # 业务逻辑：CRUD + 状态机 + block/unblock + PDF 物理删除
│       ├── logger_config.py       # Loguru 初始化 + 劫持 uvicorn/fastapi logging
│       ├── routers/               # /api/expenses · /api/invoices · /api/dashboard · /api/client-logs
│       └── utils/
│           └── invoice_parser.py  # pdfplumber 解析发票 PDF（金额/日期/类型/备注）
├── build_app.py                   # 一键生产打包（Nuitka + Flutter build）
├── AGENTS.md                      # 开发者上下文备忘
└── LICENSE
```

## 生产打包

```bash
python build_app.py
```

打包流程：

1. **清理缓存** — 删除历史 `build_out/`、`main.dist/`、`app_ui/build/`
2. **编译后端** — Nuitka `--standalone` 将 `main.py` 编译为独立 `main.exe`
3. **编译前端** — `flutter build windows` 产出 `invoice_system.exe`
4. **拼装产物** — 合并至 `Releases/{日期}_发票管理系统/`，自动重命名为 `发票管理系统.exe`

> 分发时只需将 `Releases/{日期}_发票管理系统/` 文件夹打包为 zip，用户解压后双击 `发票管理系统.exe` 即可运行。

## 版权

[PolyForm Noncommercial](./LICENSE)
