# import os
# from dotenv import load_dotenv
# from sqlalchemy import create_engine
# from sqlalchemy.orm import declarative_base, sessionmaker

# load_dotenv()

# DATABASE_URL = os.getenv("DATABASE_URL")

# if not DATABASE_URL:
#     raise ValueError("DATABASE_URL is not set in the .env file")

# # 1. Clean query params unsupported by psycopg3
# if "?pgbouncer=true" in DATABASE_URL:
#     DATABASE_URL = DATABASE_URL.replace("?pgbouncer=true", "")
# if "&pgbouncer=true" in DATABASE_URL:
#     DATABASE_URL = DATABASE_URL.replace("&pgbouncer=true", "")

# # 2. Normalize protocol for SQLAlchemy + psycopg
# if DATABASE_URL.startswith("postgres://"):
#     DATABASE_URL = DATABASE_URL.replace(
#         "postgres://", "postgresql+psycopg://", 1)
# elif DATABASE_URL.startswith("postgresql://") and not DATABASE_URL.startswith("postgresql+"):
#     DATABASE_URL = DATABASE_URL.replace(
#         "postgresql://", "postgresql+psycopg://", 1)

# # SQLite fallback compatibility if testing locally
# connect_args = {"check_same_thread": False} if DATABASE_URL.startswith(
#     "sqlite") else {}

# engine = create_engine(
#     DATABASE_URL,
#     connect_args=connect_args,
#     pool_pre_ping=True,
#     pool_recycle=1800,
# )

# SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Base = declarative_base()


# def get_db():
#     db = SessionLocal()
#     try:
#         yield db
#     finally:
#         db.close()
"""
app/database.py  (Google Cloud SQL version)

The engine now connects to Google Cloud SQL through the SAME helper the AI code
uses (ai_services/cloudsql_db.py), so the whole project talks to one database.

Settings in backend/.env (Cloud SQL):
    CLOUDSQL_INSTANCE=your-project:your-region:your-instance
    DB_NAME=postgres
    DB_USER=postgres
    DB_PASSWORD=your-password

Fallback: if CLOUDSQL_INSTANCE and DB_HOST are both unset, DATABASE_URL is used
as before (handy for a local SQLite test, e.g. DATABASE_URL=sqlite:///./test.db).
"""
import os

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# Load backend/.env FIRST, so the settings exist before the engine is built
load_dotenv()

USE_CLOUD_SQL = bool(os.getenv("CLOUDSQL_INSTANCE") or os.getenv("DB_HOST"))

if USE_CLOUD_SQL:
    # Same engine (and connection pool) the AI code uses
    from ai_services.cloudsql_db import get_engine
    engine = get_engine()
    print("[database] Connected through Google Cloud SQL")
else:
    DATABASE_URL = os.getenv("DATABASE_URL")
    if not DATABASE_URL:
        raise ValueError(
            "No database configured. Set CLOUDSQL_INSTANCE, DB_NAME, DB_USER and "
            "DB_PASSWORD in backend/.env (or DATABASE_URL for a local SQLite test)."
        )

    # Normalize the protocol for SQLAlchemy + psycopg
    if DATABASE_URL.startswith("postgres://"):
        DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql+psycopg://", 1)
    elif DATABASE_URL.startswith("postgresql://") and not DATABASE_URL.startswith("postgresql+"):
        DATABASE_URL = DATABASE_URL.replace("postgresql://", "postgresql+psycopg://", 1)

    connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
    engine = create_engine(
        DATABASE_URL,
        connect_args=connect_args,
        pool_pre_ping=True,
        pool_recycle=1800,
    )
    print("[database] Connected through DATABASE_URL")

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()