import sqlite3
import uuid
import os

# 数据库文件路径（本地嵌入式存储）
DB_PATH = "invoice_system.db"

def generate_uid() -> str:
    """
    UID 生成策略：
    使用 UUID v4 生成随机且全局唯一的字符串作为主键。
    将其转换为字符串，以适应 SQLite 的 TEXT 类型。
    """
    return str(uuid.uuid4())

def init_db():
    """初始化数据库，执行基础 DDL 建表语句"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # 1. 创建开销表 (Expenses)
    # 包含了状态机流转所需的基础字段
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS expenses (
            uid TEXT PRIMARY KEY,
            title TEXT NOT NULL,          -- 开销事由 (如: 购买服务器)
            amount REAL NOT NULL,         -- 开销金额
            status TEXT NOT NULL DEFAULT '待开票', -- 状态机: 待开票/已开票、待报销/核销中/已完结
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # 2. 创建发票表 (Invoices)
    # 包含 PDF 文件的相对路径，并通过 expense_uid 与开销表关联
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS invoices (
            uid TEXT PRIMARY KEY,
            expense_uid TEXT,             -- 关联的开销记录 UID (允许为空，支持先传发票后绑定)
            invoice_number TEXT,          -- 发票号码
            pdf_path TEXT,                -- 本地 PDF 文件的存储路径
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (expense_uid) REFERENCES expenses (uid)
        )
    ''')

    conn.commit()
    conn.close()
    print("[OK] SQLite 数据库初始化完成，Expenses 和 Invoices 表已就绪！")

# 允许直接运行此文件进行数据库测试
if __name__ == "__main__":
    init_db()