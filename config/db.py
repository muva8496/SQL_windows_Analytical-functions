import os
from dotenv import load_dotenv
from sqlalchemy import create_engine

load_dotenv()

def get_pg_engine():
    host = os.getenv("PG_HOST", "localhost")
    port = os.getenv("PG_PORT", "5432")
    db = os.getenv("PG_DB", "postgres")
    user = os.getenv("PG_USER", "postgres")
    password = os.getenv("PG_PASSWORD", "")

    url = f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{db}"
    return create_engine(url, future=True)