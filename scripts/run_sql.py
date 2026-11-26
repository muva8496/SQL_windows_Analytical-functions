import argparse
from pathlib import Path
import pandas as pd
from sqlalchemy import text
from config.db import get_pg_engine


def main():
    parser = argparse.ArgumentParser(description="Execute a .sql file against PostgreSQL.")
    parser.add_argument("sql_file", help="Path to the .sql file (e.g., sql/01_top_skus_by_branch.sql)")
    parser.add_argument("--save-csv", help="Optional filename inside outputs/ to save results")
    parser.add_argument("--rows", type=int, default=25, help="Max rows to print in terminal")
    args = parser.parse_args()

    sql_path = Path(args.sql_file)
    if not sql_path.exists():
        raise FileNotFoundError(f"SQL file not found: {sql_path}")

    query_text = sql_path.read_text(encoding="utf-8").strip()
    engine = get_pg_engine()

    with engine.connect() as conn:
        result = conn.execute(text(query_text))
        if result.returns_rows:
            df = pd.DataFrame(result.fetchall(), columns=result.keys())
            print(f"Rows returned: {len(df)}")
            print(df.head(args.rows).to_string(index=False))

            if args.save_csv:
                out_dir = Path("outputs")
                out_dir.mkdir(exist_ok=True)
                out_path = out_dir / args.save_csv
                df.to_csv(out_path, index=False)
                print(f"Saved to: {out_path}")
        else:
            conn.commit()
            print("Statement executed successfully (no rows returned).")


if __name__ == "__main__":
    main()