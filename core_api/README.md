# core_api 结构

``` text
core_api/
├── main.py              # 🏁 【入口】只负责启动服务和挂载路由
├── data/                # 📂 【仓库】存放 .db 文件和未来的 PDF 发票（不提交到 Git）
│   └── invoice_system.db 
├── .gitignore           # 🛡️ 【版本控制黑名单】用来屏蔽 venv、__pycache__ 和 data 文件夹
├── requirements.txt     # 📦 【依赖】Python 依赖清单
└── app/                 # ⚙️ 【黑盒】业务逻辑包
    ├── __init__.py      
    ├── database.py      # 数据库连接池
    ├── models.py        # SQLAlchemy 表结构
    ├── schemas.py       # Pydantic 校验
    ├── crud.py          # 数据库增删改查逻辑
    └── routers/         # 业务分发中心
        ├── __init__.py
        └── expenses.py  # 路由接口
```
