# 发票管理系统 — Invoice Management System

Windows 桌面应用，管理企业业务开销全生命周期（开票 → 报销 → 核销完结），Flutter 前端 + FastAPI 后端 Sidecar 架构。

## Project

- **前端**：Flutter 3.11+ / Dart，`app_ui/`，入口 `lib/main.dart`（窗口管理 + Sidecar 生命周期）
- **后端**：FastAPI 0.136 / Uvicorn 0.46，`core_api/`，入口 `main.py`，监听 `127.0.0.1:18090`
- **数据库**：SQLite（WAL 模式），文件 `core_api/user_data/invoice_system.db`
- **ORM**：SQLAlchemy 2.0，`app/database.py` — QueuePool 连接池 + `Depends(get_db)` 依赖注入
- **日志**：Loguru（后端）+ 自定义 `AppLogger`（前端缓冲队列 → HTTP 批量上报 `/api/client-logs/batch`）
- **打包**：Nuitka（后端 → `main.exe`）+ Flutter build（前端），`build_app.py` 一键拼装至 `Releases/`
- **本地持久化**：`shared_preferences` 存储表格列宽，拖拽调整后自动保存，重启/缩放不变

## Commands

```bash
# 安装依赖
cd core_api && pip install -r requirements.txt
cd app_ui && flutter pub get

# 开发运行（Sidecar 自动管理后端生命周期，推荐）
cd app_ui && flutter run -d windows

# 手动分离前后端（调试用）
cd core_api && python main.py          # 终端 1：后端 :18090
cd app_ui && flutter run -d windows    # 终端 2：前端

# 生产打包
python build_app.py
```

## Architecture

```
core_api/                        # Python 后端
├── main.py                      # FastAPI 入口 + 自动建表 + uvicorn.run
└── app/
    ├── database.py              # engine + SessionLocal + Base + get_db + WAL pragma
    ├── models.py                # ExpenseRecord + InvoiceRecord（uuuid 主键）
    ├── schemas.py               # Pydantic v2 请求/响应模型
    ├── crud.py                  # 业务逻辑：CRUD + 状态机 + block/unblock + PDF 物理删除
    ├── logger_config.py         # Loguru 初始化 + 劫持 uvicorn/fastapi logging
    ├── routers/
    │   ├── expenses.py          # /api/expenses — CRUD + block/unblock
    │   ├── invoices.py          # /api/invoices — PDF 绑定/解绑 + pdfplumber 自动解析建档
    │   ├── dashboard.py         # /api/dashboard — summary/trend/distribution/heatmap/type-distribution
    │   └── client_logs.py       # /api/client-logs/batch — 接收前端批量日志
    └── utils/
        └── invoice_parser.py    # pdfplumber 解析发票 PDF（提取金额/日期/类型）

app_ui/                          # Flutter 前端
├── lib/
│   ├── main.dart                # 入口：WindowOptions + Sidecar _startBackendEngine + _cleanGhostProcess
│   ├── config.dart              # AppConfig.baseUrl = http://127.0.0.1:18090
│   ├── logger.dart              # AppLogger 单例：内存缓冲 50 条 / 2 秒 → POST /api/client-logs/batch
│   ├── services/
│   │   └── expense_service.dart # 全部 HTTP 请求（静态方法，utf8.decode 解码，Future.wait 并发批量）
│   ├── widgets/
│   │   ├── custom_title_bar.dart# 沉浸式自绘标题栏
│   │   └── glass_card.dart      # 毛玻璃容器组件
│   └── pages/dashboard/
│       ├── unified_dashboard_page.dart  # 编排页：持有状态 + _kpi getter 预计算 + 回调分发
│       └── widgets/
│           ├── kpi_summary_card.dart    # 2×2 KPI 指标卡（接收预计算值，隐私切换）
│           ├── heatmap_card.dart        # 90 天热力图（右对齐 + resize 自动滚动）
│           ├── dual_analysis_card.dart  # 项目进度条 + 类型环形图 + 时间范围联动
│           ├── expense_table_panel.dart # 明细表：搜索/筛选/分页/全选/拖拽列宽（SharedPreferences 持久化）
│           └── invoice_pdf_panel.dart   # PDF 预览 + 缩略图条 + 拖拽绑定
├── windows/                     # Win32 原生层（CMake + C++ runner）
└── pubspec.yaml                 # 依赖：http, window_manager, shared_preferences, desktop_drop, syncfusion_flutter_pdfviewer, fl_chart
```

**Sidecar 生命周期**：Flutter 启动 → `_cleanGhostProcess()`（端口 18090 反查强杀旧进程）→ `_startBackendEngine()` 拉起 Python → 窗口关闭时 `_WindowCloseListener.onWindowClose()` 强杀后端 + 销毁窗口。

## Conventions

- **主键统一用 `uuuid`**（注意双写 u）：`uuid4()` 生成字符串，所有 API 路径参数和请求体统一使用
- **日志**：后端用 `loguru.logger`，前端用 `AppLogger.info/warning/error`（fire-and-forget，不抛异常）。禁止裸 `print()` 或 `logging.getLogger()`
- **数据库**：所有会话通过 `Depends(get_db)` 获取，用后自动 close。SQLite 必须启用 WAL 模式
- **状态机**：`VALID_TRANSITIONS` 定义在 `crud.py`，当前代码已解除流转限制；屏蔽态走 `blocked_from_status` 旁路，恢复时还原原状态
- **HTTP 响应解码**：Flutter 端统一用 `utf8.decode(resp.bodyBytes)`，不用 `resp.body`，避免 Windows GBK 乱码
- **REST 风格**：所有 API 前缀 `/api/`，GET 列表、POST 创建、PATCH 局部更新、DELETE 删除
- **文件组织**：业务逻辑集中在 `crud.py`（非 router 内嵌），router 只做参数解析 + 错误转换
- **批量操作**：优先用 `Future.wait` 并发发送 HTTP 请求，完成后单次 `setState` + 单次刷新，不逐条 await
- **KPI 预计算**：KpiSummaryCard 接收父级预计算的 4 个 double（monthTotal/pending/pendingReimburse/yearTotal），不在 build 内遍历 expenses
- **列宽持久化**：ExpenseTablePanel 用 `shared_preferences` 存储 `Map<int, double>`（JSON 编码），拖拽 `onPanEnd` 时保存，`initState` 时加载，已保存则跳过比例重算
- **明细表列序**（当前）：`发票 → 日期 → 事由 → 金额 → 状态 → 项目 → 类型 → 备注`
- **命名**：Python 用 snake_case，Dart 用 lowerCamelCase，SQLite 列名用 snake_case

## Notes

<!-- 待补充 -->
