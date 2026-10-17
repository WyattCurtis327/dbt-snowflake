"""One-off: validate setup -> load -> teardown against Snowflake.

Reads account/user/password from ~/.dbt/profiles.yml (dbt_snowflake.dev).
Does not print secrets.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from snowflake.run import connect, load_dotenv, put_data, run_sql, run_sql_file, SQL_DIR  # noqa: E402


def apply_dbt_profile() -> None:
    path = Path.home() / ".dbt" / "profiles.yml"
    profile = yaml.safe_load(path.read_text(encoding="utf-8"))
    dev = profile["dbt_snowflake"]["outputs"]["dev"]
    os.environ.setdefault("SNOWFLAKE_ACCOUNT", str(dev["account"]))
    os.environ.setdefault("SNOWFLAKE_USER", str(dev["user"]))
    if dev.get("password"):
        os.environ.setdefault("SNOWFLAKE_PASSWORD", str(dev["password"]))
    os.environ.setdefault("SNOWFLAKE_ROLE", os.environ.get("SNOWFLAKE_ROLE") or "ACCOUNTADMIN")


def q(cur, sql: str):
    cur.execute(sql)
    return cur.fetchall()


def names(cur, sql: str) -> set[str]:
    cur.execute(sql)
    cols = [c[0].lower() for c in cur.description]
    idx = cols.index("name") if "name" in cols else 0
    return {str(r[idx]).upper() for r in cur.fetchall()}


def show_session(cur) -> None:
    cur.execute(
        "SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT(), CURRENT_REGION()"
    )
    print("session:", cur.fetchone())
    cur.execute("SELECT CURRENT_AVAILABLE_ROLES()")
    print("available_roles:", cur.fetchone()[0])


def assert_true(cond: bool, msg: str) -> None:
    if not cond:
        raise SystemExit(f"FAIL: {msg}")
    print(f"ok: {msg}")


def main() -> None:
    load_dotenv(ROOT / ".env")
    apply_dbt_profile()

    print("=== probe ===")
    # First connect with the profile's learning role to see what we have.
    os.environ["SNOWFLAKE_ROLE"] = "SNOWFLAKE_LEARNING_ROLE"
    conn = connect()
    cur = conn.cursor()
    show_session(cur)
    conn.close()

    os.environ["SNOWFLAKE_ROLE"] = "ACCOUNTADMIN"
    try:
        conn = connect()
        cur = conn.cursor()
        print("ACCOUNTADMIN: connected")
        show_session(cur)
    except Exception as exc:
        print("ACCOUNTADMIN connect failed:", exc)
        print("retrying SYSADMIN")
        os.environ["SNOWFLAKE_ROLE"] = "SYSADMIN"
        conn = connect()
        cur = conn.cursor()
        show_session(cur)

    try:
        print("\n=== setup ===")
        run_sql_file(cur, SQL_DIR / "day1_setup.sql")
        cur.execute("USE ROLE ACCOUNTADMIN")
        dbs = names(cur, "SHOW DATABASES LIKE 'FBG_PREP'")
        whs = names(cur, "SHOW WAREHOUSES LIKE 'OPS_XS_WH'")
        roles = names(cur, "SHOW ROLES LIKE 'TRANSFORMER'")
        roles |= names(cur, "SHOW ROLES LIKE 'OPS_ANALYST'")
        assert_true("FBG_PREP" in dbs, "database FBG_PREP exists")
        assert_true("OPS_XS_WH" in whs, "warehouse OPS_XS_WH exists")
        assert_true("TRANSFORMER" in roles, "role TRANSFORMER exists")
        assert_true("OPS_ANALYST" in roles, "role OPS_ANALYST exists")

        print("\n=== load ===")
        load_sql = (SQL_DIR / "load_mock_data.sql").read_text(encoding="utf-8-sig")
        marker = "-- ---------- 3. Confirm the upload ----------"
        objects_sql, copy_sql = load_sql.split(marker, 1)
        run_sql(cur, objects_sql)
        put_data(cur)
        run_sql(cur, marker + copy_sql)
        cur.execute("USE ROLE TRANSFORMER")
        cur.execute("USE SCHEMA FBG_PREP.LANDING")
        counts = {
            "RAW_CUSTOMERS": 500,
            "RAW_BETS": 11641,
            "RAW_PAYMENTS": 3140,
        }
        for table, expected in counts.items():
            actual = q(cur, f"SELECT COUNT(*) FROM {table}")[0][0]
            assert_true(actual == expected, f"{table} count {actual} == {expected}")

        print("\n=== teardown ===")
        run_sql_file(cur, SQL_DIR / "teardown.sql", continue_on_error=True)
        cur.execute("USE ROLE ACCOUNTADMIN")
        dbs = names(cur, "SHOW DATABASES LIKE 'FBG_PREP'")
        whs = names(cur, "SHOW WAREHOUSES LIKE 'OPS_XS_WH'")
        t_roles = names(cur, "SHOW ROLES LIKE 'TRANSFORMER'")
        a_roles = names(cur, "SHOW ROLES LIKE 'OPS_ANALYST'")
        assert_true("FBG_PREP" not in dbs, "database FBG_PREP dropped")
        assert_true("OPS_XS_WH" not in whs, "warehouse OPS_XS_WH dropped")
        assert_true("TRANSFORMER" not in t_roles, "role TRANSFORMER dropped")
        assert_true("OPS_ANALYST" not in a_roles, "role OPS_ANALYST dropped")
        print("\nALL CHECKS PASSED")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
