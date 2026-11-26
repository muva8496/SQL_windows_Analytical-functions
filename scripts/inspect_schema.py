import os
from dotenv import load_dotenv
from sqlalchemy import text
from config.db import get_pg_engine

load_dotenv()
schema = os.getenv("PG_SCHEMA", "public")

engine = get_pg_engine()

with engine.connect() as conn:
    tables = conn.execute(
        text("""
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = :schema
            ORDER BY table_name;
        """),
        {"schema": schema},
    ).fetchall()
    print("Tables in schema:", [t[0] for t in tables])

    columns = conn.execute(
        text("""
            SELECT table_name, column_name, data_type
            FROM information_schema.columns
            WHERE table_schema = :schema
            ORDER BY table_name, ordinal_position;
        """),
        {"schema": schema},
    ).fetchall()
    for tbl, col, dtype in columns:
        print(f"  {tbl}.{col} -> {dtype}")