"""
cloudsql_db.py  (put it in ai-services/ai_services/)

One place that connects to Google Cloud SQL (PostgreSQL). Replaces the
Supabase connection. nutrition_repo.py should import `run_query` from here.

Install once:
    pip install "cloud-sql-python-connector[pg8000]" sqlalchemy

Settings (backend/.env):
    # --- Option A: Cloud SQL Python Connector (recommended; works locally and on Cloud Run)
    CLOUDSQL_INSTANCE=your-project:asia-southeast1:your-instance
    DB_NAME=nutriwise
    DB_USER=postgres
    DB_PASSWORD=your-password
    # CLOUDSQL_IP_TYPE=PUBLIC        (use PRIVATE if the instance only has a private IP)

    # --- Option B: Cloud SQL Auth Proxy running on your computer
    # DB_HOST=127.0.0.1
    # DB_PORT=5432
    # DB_NAME=...  DB_USER=...  DB_PASSWORD=...

The connection is created on FIRST USE, not at import time, so a missing
setting gives a clear error when you query instead of crashing the import.

Usage:
    from .cloudsql_db import run_query
    rows = run_query("SELECT id, name FROM foods WHERE name ILIKE :q LIMIT 5",
                     {"q": "%chicken%"})
    # rows is a list of dicts: [{"id": 1, "name": "..."}, ...]
"""
import os
from pathlib import Path
from typing import Any, Optional

_engine = None
_connector = None

ENV_FILES_LOADED: list[str] = []


def _load_env_files() -> None:
    """Loads backend/.env (the same file gemini_client.py loads) so this module
    works on its own, even when run directly. Settings already set in the
    terminal are never overwritten. No python-dotenv needed."""
    here = Path(__file__).resolve().parent                      # .../ai-services/ai_services
    candidates = [
        here.parent.parent / "backend" / ".env",                # .../nutriwise-ai/backend/.env
        here.parent / ".env",                                   # .../ai-services/.env
        Path.cwd() / ".env",
    ]
    for f in candidates:
        try:
            if not f.is_file() or str(f) in ENV_FILES_LOADED:
                continue
            for line in f.read_text(encoding="utf-8-sig").splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                if line.lower().startswith("export "):
                    line = line[7:]
                key, _, value = line.partition("=")
                value = value.strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                    value = value[1:-1]
                os.environ.setdefault(key.strip(), value)
            ENV_FILES_LOADED.append(str(f))
        except Exception as e:
            print(f"[cloudsql_db] could not read {f}: {e}")


_load_env_files()


def _setting(name: str, required: bool = True) -> Optional[str]:
    value = os.environ.get(name)
    if required and not value:
        where = ", ".join(ENV_FILES_LOADED) if ENV_FILES_LOADED else "no .env file was found"
        raise RuntimeError(
            f"Cloud SQL setting {name} is missing. Add a line  {name}=...  to "
            f"backend/.env (see the top of cloudsql_db.py). Files read: {where}"
        )
    return value


def get_engine():
    """Creates the database engine once, then reuses it."""
    global _engine, _connector
    if _engine is not None:
        return _engine

    import sqlalchemy

    name = _setting("DB_NAME")
    user = _setting("DB_USER")
    password = _setting("DB_PASSWORD")

    host = os.environ.get("DB_HOST")
    if host:
        # Option B: Cloud SQL Auth Proxy (or any reachable PostgreSQL host)
        url = sqlalchemy.engine.URL.create(
            "postgresql+pg8000",
            username=user, password=password, host=host,
            port=int(os.environ.get("DB_PORT", "5432")), database=name,
        )
        _engine = sqlalchemy.create_engine(url, pool_size=5, max_overflow=2,
                                           pool_pre_ping=True, pool_recycle=1800)
        return _engine

    # Option A: Cloud SQL Python Connector (uses your Google sign-in / service account)
    from google.cloud.sql.connector import Connector, IPTypes

    instance = _setting("CLOUDSQL_INSTANCE")
    ip_type = IPTypes.PRIVATE if os.environ.get("CLOUDSQL_IP_TYPE", "PUBLIC").upper() == "PRIVATE" \
        else IPTypes.PUBLIC
    _connector = Connector(refresh_strategy="lazy")  # "lazy" is the right mode for Cloud Run

    def _connect():
        return _connector.connect(instance, "pg8000", user=user, password=password,
                                  db=name, ip_type=ip_type)

    _engine = sqlalchemy.create_engine("postgresql+pg8000://", creator=_connect,
                                       pool_size=5, max_overflow=2,
                                       pool_pre_ping=True, pool_recycle=1800)
    return _engine


def _plain(value):
    """PostgreSQL NUMERIC comes back as Decimal, which cannot be multiplied by a
    float (calories * weight). Convert to float, like the old Supabase client did."""
    from decimal import Decimal
    return float(value) if isinstance(value, Decimal) else value


def run_query(sql: str, params: Optional[dict[str, Any]] = None) -> list[dict]:
    """Runs a SELECT and returns a list of dicts. Use :name placeholders in the SQL."""
    import sqlalchemy
    with get_engine().connect() as conn:
        result = conn.execute(sqlalchemy.text(sql), params or {})
        return [{k: _plain(v) for k, v in row._mapping.items()} for row in result]


def run_write(sql: str, params: Optional[dict[str, Any]] = None) -> int:
    """Runs an INSERT/UPDATE/DELETE and commits. Returns the number of rows changed."""
    import sqlalchemy
    with get_engine().begin() as conn:
        return conn.execute(sqlalchemy.text(sql), params or {}).rowcount


def vector_literal(embedding: list[float]) -> str:
    """Turns an embedding into the text pgvector accepts, e.g. '[0.1,0.2]'.
    Use it with a cast:  ORDER BY embedding <=> CAST(:v AS vector)"""
    return "[" + ",".join(f"{x:.8f}" for x in embedding) + "]"


def close_connection() -> None:
    """Closes the pool and the connector cleanly (avoids 'Unclosed client session'
    warnings when a script ends)."""
    global _engine, _connector
    if _engine is not None:
        _engine.dispose()
        _engine = None
    if _connector is not None:
        _connector.close()
        _connector = None


def check_connection() -> None:
    """Run this file directly to test the connection:  python -m ai_services.cloudsql_db"""
    print("Files read:", ENV_FILES_LOADED or "none found")
    for key in ("CLOUDSQL_INSTANCE", "DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD"):
        print(f"  {key:<18}{'set' if os.environ.get(key) else 'NOT SET'}")
    rows = run_query("SELECT current_database() AS db, version() AS version")
    print("Connected:", rows[0])
    ext = run_query("SELECT extname FROM pg_extension WHERE extname = 'vector'")
    print("pgvector installed:", bool(ext))
    close_connection()


if __name__ == "__main__":
    check_connection()