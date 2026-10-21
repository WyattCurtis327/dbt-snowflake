"""Run the full Snowflake + dbt tutorial from this repo.

Usage (from the repo root, venv on):

    python snowflake/run.py setup      # warehouse, FBG_PREP, LANDING/BRONZE/SILVER/GOLD, roles
    python snowflake/run.py load       # PUT/COPY into LANDING, then dbt snapshot + build
    python snowflake/run.py teardown   # drop database / warehouse / roles (start over)
    python snowflake/run.py all        # setup + load; leaves objects built
    python snowflake/run.py sql snowflake/day1_setup.sql
    python snowflake/run.py debug     # dbt debug --target snowflake (key-pair)
    python snowflake/run.py replay-vip  # Day 1 + Day 2 snapshot so VIP-at-bet differs from now

Reads .env in the repo root, then fills missing Snowflake keys from ~/.dbt/profiles.yml.
Prefers ~/.snowflake/dbt_cloud_rsa_key.p8 over password. Does not print secrets.
See .env.example.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data"
DEFAULT_PRIVATE_KEY = Path.home() / ".snowflake" / "dbt_cloud_rsa_key.p8"

PUT_FILES = [
    "raw_customers.csv",
    "raw_customers_v1.csv",
    "raw_vip_tier_history.csv",
    "raw_bets.csv",
    "raw_payments.csv",
    "raw_payments_batch1.csv",
    "raw_kyc_events.csv",
    "raw_cx_tickets.csv",
    "raw_fraud_alerts.csv",
    "raw_promos.csv",
    "raw_promo_awards.csv",
    "state_tax_rates.csv",
]


def load_dotenv(path: Path) -> None:
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def ensure_private_key_env() -> Path | None:
    raw = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PATH", "").strip()
    path = Path(raw) if raw else DEFAULT_PRIVATE_KEY
    if path.is_file():
        os.environ.setdefault("SNOWFLAKE_PRIVATE_KEY_PATH", str(path))
        return path
    return None


def connect():
    import snowflake.connector

    account = os.environ.get("SNOWFLAKE_ACCOUNT", "").strip()
    user = os.environ.get("SNOWFLAKE_USER", "").strip()
    if not account or not user:
        sys.exit(
            "Set SNOWFLAKE_ACCOUNT and SNOWFLAKE_USER in .env (copy .env.example)."
        )

    kwargs = {
        "account": account,
        "user": user,
        "role": os.environ.get("SNOWFLAKE_ROLE") or "ACCOUNTADMIN",
    }
    warehouse = os.environ.get("SNOWFLAKE_WAREHOUSE")
    if warehouse:
        kwargs["warehouse"] = warehouse

    key_path = ensure_private_key_env()
    authenticator = os.environ.get("SNOWFLAKE_AUTHENTICATOR", "").strip()
    password = os.environ.get("SNOWFLAKE_PASSWORD", "").strip()
    if key_path:
        kwargs["private_key_file"] = str(key_path)
        passphrase = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE", "").strip()
        if passphrase:
            kwargs["private_key_file_pwd"] = passphrase
    elif authenticator:
        kwargs["authenticator"] = authenticator
    elif password:
        kwargs["password"] = password
    else:
        sys.exit(
            "Set SNOWFLAKE_PRIVATE_KEY_PATH (or place the key at "
            f"{DEFAULT_PRIVATE_KEY}), SNOWFLAKE_AUTHENTICATOR=externalbrowser, "
            "or SNOWFLAKE_PASSWORD in .env."
        )

    return snowflake.connector.connect(**kwargs)


def _code_prefix(line: str) -> str:
    """Return the line with a trailing -- comment removed, ignoring -- inside quotes."""
    in_single = False
    in_double = False
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif (
            ch == "-"
            and not in_single
            and not in_double
            and i + 1 < len(line)
            and line[i + 1] == "-"
        ):
            return line[:i]
        i += 1
    return line


def iter_statements(sql: str):
    buf: list[str] = []
    for line in sql.splitlines():
        buf.append(line)
        if not _code_prefix(line).rstrip().endswith(";"):
            continue
        stmt = "\n".join(buf).strip()
        buf = []
        code_lines = [
            ln
            for ln in stmt.splitlines()
            if _code_prefix(ln).strip()
        ]
        if code_lines:
            yield stmt


def bind_session_user(cur, sql: str) -> str:
    """GRANT TO USER IDENTIFIER($my_user) fails on this trial; bind CURRENT_USER()."""
    cur.execute("SELECT CURRENT_USER()")
    user_name = cur.fetchone()[0]
    safe = str(user_name).replace("'", "''")
    return sql.replace("IDENTIFIER($my_user)", f"IDENTIFIER('{safe}')")


def run_sql(cur, sql: str, *, continue_on_error: bool = False) -> None:
    sql = bind_session_user(cur, sql)
    for stmt in iter_statements(sql):
        preview = " ".join(stmt.split())[:100]
        print(f"-- {preview}")
        try:
            cur.execute(stmt)
            _print_result(cur)
        except Exception as exc:
            if continue_on_error:
                print(f"   skipped: {exc}")
                continue
            raise


def run_sql_file(cur, path: Path, *, continue_on_error: bool = False) -> None:
    print(f"-- {path.relative_to(ROOT)}")
    run_sql(
        cur,
        path.read_text(encoding="utf-8-sig"),
        continue_on_error=continue_on_error,
    )


def _print_result(cur) -> None:
    desc = cur.description
    if not desc:
        if cur.rowcount not in (-1, None):
            print(f"  ok ({cur.rowcount} rows)")
        return
    rows = cur.fetchmany(8)
    cols = [c[0] for c in desc]
    print("  " + " | ".join(cols))
    for row in rows:
        print("  " + " | ".join("" if v is None else str(v) for v in row))
    if cur.rowcount and cur.rowcount > len(rows):
        print(f"  ... {cur.rowcount} rows")


def apply_dbt_profile() -> None:
    """Fill SNOWFLAKE_* env from ~/.dbt/profiles.yml if .env did not set them. Never prints secrets."""
    path = Path.home() / ".dbt" / "profiles.yml"
    if not path.is_file():
        return
    try:
        import yaml
    except ImportError:
        return
    profile = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    dev = (profile.get("dbt_snowflake") or profile.get("sportsbook") or {}).get("outputs", {}).get("dev")
    if not isinstance(dev, dict):
        return
    mapping = {
        "SNOWFLAKE_ACCOUNT": "account",
        "SNOWFLAKE_USER": "user",
        "SNOWFLAKE_WAREHOUSE": "warehouse",
    }
    if not ensure_private_key_env():
        mapping["SNOWFLAKE_PASSWORD"] = "password"
        mapping["SNOWFLAKE_AUTHENTICATOR"] = "authenticator"
    for env_key, profile_key in mapping.items():
        value = dev.get(profile_key)
        if value:
            os.environ.setdefault(env_key, str(value))
    os.environ.setdefault("SNOWFLAKE_DATABASE", "FBG_PREP")
    os.environ.setdefault("SNOWFLAKE_DBT_ROLE", "TRANSFORMER")


def put_data(cur) -> None:
    if not DATA_DIR.is_dir():
        sys.exit(f"Missing {DATA_DIR}. Unzip the mock CSVs into data/ first.")
    cur.execute("USE ROLE TRANSFORMER")
    cur.execute("USE WAREHOUSE OPS_XS_WH")
    cur.execute("USE SCHEMA FBG_PREP.LANDING")
    print("-- REMOVE @FBG_PREP.LANDING.MOCK_STAGE")
    cur.execute("REMOVE @FBG_PREP.LANDING.MOCK_STAGE")
    _print_result(cur)
    for name in PUT_FILES:
        local = DATA_DIR / name
        if not local.is_file():
            print(f"skip (missing): {name}")
            continue
        uri = local.resolve().as_posix()
        if not uri.startswith("/"):
            uri = "/" + uri
        sql = (
            f"PUT 'file://{uri}' @FBG_PREP.LANDING.MOCK_STAGE "
            "AUTO_COMPRESS=TRUE OVERWRITE=TRUE"
        )
        print(f"-- PUT {name}")
        cur.execute(sql)
        _print_result(cur)


def load_landing(cur) -> None:
    load_sql = (SQL_DIR / "load_mock_data.sql").read_text(encoding="utf-8-sig")
    marker = "-- ---------- 3. Confirm the upload ----------"
    if marker not in load_sql:
        sys.exit("Could not find stage/COPY split marker in load_mock_data.sql")
    objects_sql, copy_sql = load_sql.split(marker, 1)
    print("-- create stage and landing tables")
    run_sql(cur, objects_sql)
    put_data(cur)
    print("-- COPY INTO + checks")
    run_sql(cur, marker + copy_sql)


def _dbt_cmd():
    sportsbook = ROOT / "sportsbook"
    scripts = Path(sys.executable).parent
    dbt = scripts / ("dbt.exe" if os.name == "nt" else "dbt")
    if not dbt.is_file():
        sys.exit(f"dbt not found next to {sys.executable}. Activate .venv first.")
    env = os.environ.copy()
    env["SNOWFLAKE_WAREHOUSE"] = "OPS_XS_WH"
    env["SNOWFLAKE_DBT_ROLE"] = "TRANSFORMER"
    env["SNOWFLAKE_DATABASE"] = "FBG_PREP"
    env.setdefault("DBT_PROFILES_DIR", str(sportsbook))
    key_path = ensure_private_key_env()
    if key_path:
        env["SNOWFLAKE_PRIVATE_KEY_PATH"] = str(key_path)
        env.pop("SNOWFLAKE_PASSWORD", None)
        env.pop("SNOWFLAKE_AUTHENTICATOR", None)
    flags = ["--profiles-dir", str(sportsbook), "--project-dir", str(sportsbook)]
    return dbt, sportsbook, env, flags


def run_dbt() -> None:
    """Build brz_/slv_/fct_/mart_/sem_ into FBG_PREP. Seeds are excluded: COPY already landed CSVs."""
    dbt, sportsbook, env, flags = _dbt_cmd()
    print("-- dbt snapshot --target snowflake")
    subprocess.run([str(dbt), "snapshot", "--target", "snowflake", *flags], cwd=sportsbook, env=env, check=True)
    print("-- dbt build --target snowflake --exclude resource_type:seed")
    subprocess.run(
        [str(dbt), "build", "--target", "snowflake", "--exclude", "resource_type:seed", *flags],
        cwd=sportsbook,
        env=env,
        check=True,
    )


def run_dbt_debug() -> None:
    dbt, sportsbook, env, flags = _dbt_cmd()
    print("-- dbt debug --target snowflake")
    subprocess.run([str(dbt), "debug", "--target", "snowflake", "--no-use-colors", *flags], cwd=sportsbook, env=env, check=True)


def _copy_customers(cur, filename: str) -> None:
    cur.execute("USE ROLE TRANSFORMER")
    cur.execute("USE WAREHOUSE OPS_XS_WH")
    cur.execute("USE SCHEMA FBG_PREP.LANDING")
    print(f"-- reload LANDING.RAW_CUSTOMERS from {filename}")
    cur.execute("TRUNCATE TABLE FBG_PREP.LANDING.RAW_CUSTOMERS")
    cur.execute(
        "COPY INTO FBG_PREP.LANDING.RAW_CUSTOMERS "
        "FROM @FBG_PREP.LANDING.MOCK_STAGE "
        f"PATTERN = '(.*/)?{filename}([.]gz)?' "
        "FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') "
        "FORCE = TRUE"
    )
    _print_result(cur)
    cur.execute("SELECT COUNT(*) FROM FBG_PREP.LANDING.RAW_CUSTOMERS")
    n = cur.fetchone()[0]
    print(f"   RAW_CUSTOMERS rows={n}")
    if n != 500:
        sys.exit(f"Expected 500 customers after {filename}, got {n}. Is the file on MOCK_STAGE?")


def cmd_replay_vip() -> None:
    """Day-1 customers -> snapshot, Day-2 customers -> snapshot, rebuild the VIP join."""
    conn = connect()
    try:
        cur = conn.cursor()
        _copy_customers(cur, "raw_customers_v1[.]csv")
        print("-- drop existing SNAP_CUSTOMER_VIP so Day 1 can start clean")
        cur.execute("USE ROLE TRANSFORMER")
        cur.execute("DROP TABLE IF EXISTS FBG_PREP.GOLD.SNAP_CUSTOMER_VIP")
    finally:
        conn.close()

    dbt, sportsbook, env, flags = _dbt_cmd()
    print("-- dbt snapshot --select snap_customer_vip (Day 1)")
    subprocess.run(
        [str(dbt), "snapshot", "--target", "snowflake", "--select", "snap_customer_vip", *flags],
        cwd=sportsbook,
        env=env,
        check=True,
    )

    conn = connect()
    try:
        cur = conn.cursor()
        _copy_customers(cur, "raw_customers[.]csv")
    finally:
        conn.close()

    print("-- dbt snapshot --select snap_customer_vip (Day 2 incremental)")
    subprocess.run(
        [str(dbt), "snapshot", "--target", "snowflake", "--select", "snap_customer_vip", *flags],
        cwd=sportsbook,
        env=env,
        check=True,
    )
    print("-- dbt run --select fct_bets_with_vip_tier")
    subprocess.run(
        [str(dbt), "run", "--target", "snowflake", "--select", "fct_bets_with_vip_tier", *flags],
        cwd=sportsbook,
        env=env,
        check=True,
    )

    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("USE ROLE TRANSFORMER")
        cur.execute("USE WAREHOUSE OPS_XS_WH")
        cur.execute(
            "select count(*) as changed_bets "
            "from fbg_prep.gold.fct_bets_with_vip_tier "
            "where vip_tier_at_bet <> vip_tier_now"
        )
        n = cur.fetchone()[0]
        print(f"vip_tier_at_bet <> vip_tier_now rows={n}")
        cur.execute(
            "select count(*) as customers_with_history "
            "from (select customer_id from fbg_prep.gold.snap_customer_vip "
            "group by 1 having count(*) > 1)"
        )
        print(f"customers with 2+ snapshot rows={cur.fetchone()[0]}")
    finally:
        conn.close()


def cmd_setup(cur) -> None:
    run_sql_file(cur, SQL_DIR / "day1_setup.sql")


def cmd_load(cur) -> None:
    load_landing(cur)
    conn = cur.connection
    conn.close()
    run_dbt()


def cmd_teardown(cur) -> None:
    run_sql_file(cur, SQL_DIR / "teardown.sql", continue_on_error=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("setup", help="warehouse, FBG_PREP, LANDING/BRONZE/SILVER/GOLD, roles")
    sub.add_parser("load", help="PUT/COPY into LANDING, then dbt snapshot + build")
    sub.add_parser("teardown", help="drop database, warehouse, roles (and all dbt objects)")
    sub.add_parser("all", help="setup + load; leaves the project built")
    sub.add_parser("debug", help="dbt debug --target snowflake using the local key pair")
    sub.add_parser(
        "replay-vip",
        help="Day 1 + Day 2 customer snapshot so vip_tier_at_bet <> vip_tier_now returns rows",
    )
    sql_p = sub.add_parser("sql", help="run any .sql file on this connection")
    sql_p.add_argument("path")
    args = parser.parse_args()

    load_dotenv(ROOT / ".env")
    apply_dbt_profile()
    ensure_private_key_env()

    if args.cmd == "debug":
        run_dbt_debug()
        print("done.")
        return

    if args.cmd == "replay-vip":
        cmd_replay_vip()
        print("done. Re-run the VIP inequality query in Snowsight.")
        return

    if args.cmd == "load":
        conn = connect()
        try:
            cmd_load(conn.cursor())
        except Exception:
            conn.close()
            raise
        print("done. FBG_PREP is built (landing + dbt medallion).")
        return

    if args.cmd == "all":
        conn = connect()
        try:
            cmd_setup(conn.cursor())
            cmd_load(conn.cursor())
        except Exception:
            conn.close()
            raise
        print("done. FBG_PREP is built (landing + dbt medallion).")
        return

    conn = connect()
    try:
        cur = conn.cursor()
        if args.cmd == "setup":
            cmd_setup(cur)
        elif args.cmd == "teardown":
            cmd_teardown(cur)
        elif args.cmd == "sql":
            run_sql_file(cur, Path(args.path).resolve())
        print("done.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
