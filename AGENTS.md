# 发票管理系统 — Invoice Management System

Windows 桌面应用，管理企业业务开销全生命周期（开票 → 报销 → 核销完结），Flutter 前端 + FastAPI 后端 Sidecar 架构。

## Project

- **前端**：Flutter 3.11+ / Dart，`app_ui/`，入口 `lib/main.dart`（窗口管理 + Sidecar 生命周期 + `backendReady` 信号）
- **后端**：FastAPI 0.136 / Uvicorn 0.46，`core_api/`，入口 `main.py`，端口自动扫描 18090–18109，写入 `config/port.txt`
- **数据库**：SQLite（WAL 模式），路径由 `config/config.json` 的 `db_path` 管理，`database.py` 通过 `init_database(db_dir)` 延迟初始化
- **ORM**：SQLAlchemy 2.0，`app/database.py` — 延迟初始化 engine + QueuePool + `Depends(get_db)` 依赖注入
- **配置**：`app/config_manager.py` — JSON 配置中心，管理 db_path/log_path、PDF 分片、路径校验、目录预览、预建目录
- **日志**：Loguru（后端 `setup_loguru(log_path)` 参数化）+ 自定义 `AppLogger`（前端缓冲队列 → HTTP 批量上报 `/api/client-logs/batch`）
- **打包**：Nuitka（后端 → `main.exe`）+ Flutter build（前端），`build_app.py` 5 步：编译 → 拼装 → zip → 完整性校验 `.exe`
- **本地持久化**：`shared_preferences` 存储表格列宽，拖拽调整后自动保存，重启/缩放不变

## Commands

```bash
# 安装依赖
cd core_api && pip install -r requirements.txt
cd app_ui && flutter pub get

# 开发运行（Sidecar 自动管理后端生命周期，推荐）
cd app_ui && flutter run -d windows

# 手动分离前后端（调试用）
cd core_api && python main.py          # 终端 1：后端（端口输出到控制台）
cd app_ui && flutter run -d windows    # 终端 2：前端

# 生产打包
python build_app.py
```

## Architecture

```
core_api/                        # Python 后端
├── main.py                      # FastAPI 入口：config → db → log → 建表 → routes → 端口扫描 → PID/port.txt
└── app/
    ├── database.py              # init_database(db_dir) 延迟初始化 + engine + SessionLocal + Base + WAL pragma
    ├── models.py                # ExpenseRecord + InvoiceRecord（uuuid 主键，saved_path 存相对路径）
    ├── schemas.py               # Pydantic v2 请求/响应模型 + SettingsPaths/Preview/Validate/Restart
    ├── crud.py                  # 业务逻辑：CRUD + 状态机 + block/unblock + PDF 物理删除（config_manager 解析路径）
    ├── config_manager.py        # 配置中心：load/save_config、validate_paths、PDF 分片、preview_directory_structure
    ├── logger_config.py         # setup_loguru(log_dir) 参数化 + 劫持 uvicorn/fastapi logging
    ├── routers/
    │   ├── expenses.py          # /api/expenses — CRUD + block/unblock
    │   ├── invoices.py          # /api/invoices — PDF 绑定/解绑 + pdfplumber 自动解析建档 + PDF 分片存储
    │   ├── dashboard.py         # /api/dashboard — summary/trend/distribution/heatmap/type-distribution
    │   ├── client_logs.py       # /api/client-logs/batch — 接收前端批量日志
    │   └── settings.py          # /api/settings — GET/PUT paths, validate, preview, restart
    └── utils/
        └── invoice_parser.py    # pdfplumber 解析发票 PDF（提取金额/日期/类型）

app_ui/                          # Flutter 前端
├── lib/
│   ├── main.dart                # 入口：WindowOptions + backendReady Completer + PID 清场 + Sidecar 生命周期
│   ├── config.dart              # AppConfig.baseUrl（非 const，启动时由 port.txt 动态更新）
│   ├── logger.dart              # AppLogger 单例：内存缓冲 50 条 / 2 秒 → POST /api/client-logs/batch
│   ├── services/
│   │   └── expense_service.dart # 全部 HTTP 请求（静态方法，含 Settings API：previewPaths/updateSettingsPaths/requestRestart）
│   ├── widgets/
│   │   ├── custom_title_bar.dart# 沉浸式标题栏 + 齿轮 ⚙ 设置入口
│   │   ├── settings_dialog.dart # 路径设置：只读浏览选择 + 结构树预览 + 400ms 防抖 + 重新连接按钮
│   │   └── glass_card.dart      # 毛玻璃容器组件
│   └── pages/dashboard/
│       ├── unified_dashboard_page.dart  # 编排页：await backendReady → _fetchAllData()（避免后端未就绪就请求）
│       └── widgets/
│           ├── kpi_summary_card.dart    # 2×2 KPI 指标卡（接收预计算值，隐私切换）
│           ├── heatmap_card.dart        # 90 天热力图（右对齐 + resize 自动滚动）
│           ├── dual_analysis_card.dart  # 项目进度条 + 类型环形图 + 时间范围联动
│           ├── expense_table_panel.dart # 明细表：搜索/筛选/分页/全选/拖拽列宽（SharedPreferences 持久化）
│           └── invoice_pdf_panel.dart   # PDF 预览 + 缩略图条 + 拖拽绑定
├── windows/                     # Win32 原生层（CMake + C++ runner）
└── pubspec.yaml                 # 依赖：http, window_manager, shared_preferences, desktop_drop, syncfusion_flutter_pdfviewer, fl_chart, file_picker

integrity_checker.py             # 完整性校验模板：MANIFEST_B64 占位符，构建时注入 SHA256 清单
build_app.py                     # 一键打包：清理 → Nuitka → Flutter build → 拼装 → zip → 编译 完整性校验.exe
```

**Sidecar 生命周期**：Flutter 启动 → `runApp()` → `_cleanGhostProcess()`（读 PID 文件精准杀，回退端口反查）→ `_startBackendEngine()` → 等 `port.txt` 写入 → 更新 `AppConfig.baseUrl` → 健康检查 → `_backendReadyCompleter.complete()` → Dashboard 收到信号后发起 API 请求。窗口关闭时 `onWindowClose()` 杀后端 + 删 PID 文件。

## Conventions

- **主键统一用 `uuuid`**（注意双写 u）：`uuid4()` 生成字符串，所有 API 路径参数和请求体统一使用
- **日志**：后端用 `loguru.logger`，前端用 `AppLogger.info/warning/error`（fire-and-forget，不抛异常）。禁止裸 `print()` 或 `logging.getLogger()`
- **数据库**：所有会话通过 `Depends(get_db)` 获取，用后自动 close。SQLite 必须启用 WAL 模式。engine 通过 `init_database(db_dir)` 延迟初始化，不可在模块导入时创建
- **配置**：`config/config.json` 管理 db/log 路径。`config_manager.py` 为唯一读写入口，禁止绕过直接读文件。变更路径需重启后端生效
- **状态机**：`VALID_TRANSITIONS` 定义在 `crud.py`，当前代码已解除流转限制；屏蔽态走 `blocked_from_status` 旁路，恢复时还原原状态
- **HTTP 响应解码**：Flutter 端统一用 `utf8.decode(resp.bodyBytes)`，不用 `resp.body`，避免 Windows GBK 乱码
- **REST 风格**：所有 API 前缀 `/api/`，GET 列表、POST 创建、PATCH 局部更新、DELETE 删除
- **文件组织**：业务逻辑集中在 `crud.py`（非 router 内嵌），router 只做参数解析 + 错误转换
- **批量操作**：优先用 `Future.wait` 并发发送 HTTP 请求，完成后单次 `setState` + 单次刷新，不逐条 await
- **KPI 预计算**：KpiSummaryCard 接收父级预计算的 4 个 double（monthTotal/pending/pendingReimburse/yearTotal），不在 build 内遍历 expenses
- **列宽持久化**：ExpenseTablePanel 用 `shared_preferences` 存储 `Map<int, double>`（JSON 编码），拖拽 `onPanEnd` 时保存，`initState` 时加载，已保存则跳过比例重算
- **明细表列序**（当前）：`发票 → 日期 → 事由 → 金额 → 状态 → 项目 → 类型 → 备注`
- **后端就绪信号**：Dashboard 的 `initState` 中 `await backendReady` 后才发起 API 请求，避免后端未就绪时连接拒绝
- **清场**：优先读 `config/backend.pid` 精准杀进程；PID 文件缺失时回退端口反查（兼容旧版）。决不遍历端口杀其他程序
- **PDF 路径**：`saved_path` 存入数据库时用相对路径格式 `pdfs/xxx.pdf` 或 `pdfs_N/xxx.pdf`，读取时通过 `config_manager.resolve_absolute_pdf_path()` 转为绝对路径
- **设置防抖**：路径输入框 `_onPathChanged` 用 400ms Timer 防抖，避免拖动时刷屏 API 请求
- **端口**：后端自动扫描 18090–18109 首个可用端口；前端从 `config/port.txt` 读取实际端口；禁止硬编码端口号
- **命名**：Python 用 snake_case，Dart 用 lowerCamelCase，SQLite 列名用 snake_case

## Notes

<!-- 待补充 -->
