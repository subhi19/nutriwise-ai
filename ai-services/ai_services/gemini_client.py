"""
gemini_client.py

The ONLY file that creates a connection to Gemini. Every other file
(meal_analyzer.py, fridge_analyzer.py, recipes.py, etc.) imports the
`client` and `MODEL_NAME` from here instead of connecting on its own.
"""

import os
from pathlib import Path
from dotenv import load_dotenv
from google import genai

# 1. Load backend/.env automatically
_backend_env = Path(__file__).resolve().parent.parent.parent / "backend" / ".env"
load_dotenv(dotenv_path=_backend_env)
load_dotenv()

# 2. Export MODEL_NAME and EMBEDDING_MODEL
_raw_model = os.environ.get("MODEL_NAME", "gemini-2.5-flash")
# Guard against invalid 'gemini-3.5-flash' setting in .env
MODEL_NAME = "gemini-2.5-flash" if _raw_model == "gemini-3.5-flash" else _raw_model
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "text-embedding-004")


def _build_client() -> genai.Client:
    use_vertex = os.environ.get("USE_VERTEX", "false").lower() in ("true", "1", "yes")

    if use_vertex:
        # Remove API keys from env so google-genai uses ADC / IAM strictly
        os.environ.pop("GOOGLE_API_KEY", None)
        os.environ.pop("GEMINI_API_KEY", None)

        project = os.environ.get("GOOGLE_CLOUD_PROJECT", "nutriwise-ai-511608")
        location = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")
        print(f"[GeminiClient] Initializing Vertex AI client (project={project}, location={location}, model={MODEL_NAME})")
        return genai.Client(vertexai=True, project=project, location=location)

    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        raise ValueError(
            "GEMINI_API_KEY is missing and USE_VERTEX is not enabled. "
            "Set USE_VERTEX=true for Google Cloud Vertex AI or provide GEMINI_API_KEY."
        )
    print(f"[GeminiClient] Initializing Gemini Developer API client (model={MODEL_NAME})")
    return genai.Client(api_key=api_key)


client = _build_client()