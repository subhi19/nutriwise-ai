"""
gemini_client.py

The ONLY file that creates a connection to Gemini. Every other file
(meal_analyzer.py, fridge_analyzer.py, recipes.py, etc.) imports the
`client` and `MODEL_NAME` from here instead of connecting on its own.

Why this matters: when your team gets Google Cloud access and wants to
switch from the free API key to Vertex AI, you only change this ONE
file (and your .env settings) — nothing else in the project needs to
change.

Right now (USE_VERTEX=false or unset): uses your GEMINI_API_KEY, same
as your original working script.

Later (USE_VERTEX=true): uses Vertex AI with your Google Cloud project
instead. Requires `gcloud auth application-default login` to be set up
once on that machine — ask a teammate with Cloud access for help with
that step when you get there.
"""

import os
from pathlib import Path
from dotenv import load_dotenv
from google import genai

# 1. Load backend/.env automatically
_backend_env = Path(__file__).resolve(
).parent.parent.parent / "backend" / ".env"
load_dotenv(dotenv_path=_backend_env)
load_dotenv()

# 2. Export MODEL_NAME and other configurations expected by ai_services
MODEL_NAME = os.environ.get("MODEL_NAME", "gemini-2.5-flash")
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "gemini-embedding-001")


def _build_client():
    api_key = os.environ.get(
        "GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        raise ValueError(
            "GEMINI_API_KEY or GOOGLE_API_KEY is missing from environment. "
            "Please check backend/.env"
        )
    return genai.Client(api_key=api_key)


client = _build_client()
