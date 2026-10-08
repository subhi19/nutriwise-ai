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
from google import genai

USE_VERTEX = os.getenv("USE_VERTEX", "false").lower() == "true"
MODEL_NAME = os.getenv("MODEL_NAME", "gemini-3.5-flash")


def _build_client() -> genai.Client:
    if USE_VERTEX:
        project = os.environ["GCP_PROJECT"]  # required if USE_VERTEX is true
        location = os.getenv("GCP_LOCATION", "us-central1")
        return genai.Client(vertexai=True, project=project, location=location)

    # Default: use the free API key, reads GEMINI_API_KEY automatically
    return genai.Client()


# Built once when this file is first imported, then reused everywhere.
client = _build_client()


if __name__ == "__main__":
    # Quick check: run this file directly to confirm your connection works
    # and see which mode it's using.
    mode = "Vertex AI" if USE_VERTEX else "API key (AI Studio)"
    print(f"Connected using: {mode}")
    print(f"Model: {MODEL_NAME}")

    print("\nModels available to this connection:")
    for m in client.models.list():
        print(" -", m.name)