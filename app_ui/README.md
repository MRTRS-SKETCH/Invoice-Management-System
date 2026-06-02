lib/
├── main.dart                        # 应用入口及本地 Python 进程/窗口管理
├── config.dart                      # 全局环境配置 (AppConfig.baseUrl)
├── logger.dart                      # 网络日志批量上报框架
├── services/                        # 【新增：数据层】纯粹的网络请求与API交互
│   └── expense_service.dart         # 封装所有 dashboard、expenses、invoices 的 HTTP 请求
├── widgets/                         # 【通用组件库】跨页面可复用的原子组件
│   ├── custom_title_bar.dart        # 沉浸式自定义标题栏
│   └── glass_card.dart              # 毛玻璃核心通透容器组件
└── pages/                           # 【业务页面层】
    └── dashboard/                   # 财务驾驶舱高内聚领域包
        ├── unified_dashboard_page.dart # 主控中心骨架（负责组织生命周期与集中式状态管理）
        └── widgets/                 # 仅限驾驶舱内部消费的局部高阶组件
            ├── kpi_summary_card.dart    # 1. 左上：核心财务KPI指标卡
            ├── heatmap_card.dart        # 2. 中上：业务发生频次热力图
            ├── dual_analysis_card.dart  # 3. 右上：多维分析（项目进度+类型环形）
            ├── expense_table_panel.dart # 4. 下左：流水明细主数据表格（含多选、搜索、状态流转）
            └── invoice_pdf_panel.dart   # 5. 下右：发票 PDF 拖拽绑定与 Sf 预览面板