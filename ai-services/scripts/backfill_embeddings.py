"""
backfill_embeddings.py

Run this ONCE, after Steps 1-4 are done, to generate an embedding for
every food already in your table. Run it again any time you add new
foods, so they get embeddings too.

IMPORTANT — why this needs a different Supabase key:
Your normal SUPABASE_KEY (the "anon" key) is read-only because of the
security rule (RLS) we set up earlier. Saving embeddings is a WRITE, so
with the anon key Supabase would quietly save nothing and show no error.
This script therefore uses the "service_role" key instead.

  - Find it in Supabase: Project Settings -> API -> service_role key
  - Set it ONLY in your own terminal, only for this script:
        $env:SUPABASE_SERVICE_KEY="your_service_role_key"
  - NEVER put it in the repo, the .env file that gets committed, the
    backend, or the Flutter app. It can read and change everything.

This uses the Gemini embedding model, not your normal flash model —
embeddings have their own separate quota.
"""

from gemini_client import client
from supabase import create_client
import os
import sys
import time
from pathlib import Path
from dotenv import load_dotenv

# 1. Load backend/.env into environment variables first
BACKEND_DIR = Path(__file__).resolve().parent.parent.parent / "backend"
load_dotenv(dotenv_path=BACKEND_DIR / ".env")
load_dotenv()

# 2. Add ai_services to search path
AI_SERVICES_DIR = Path(__file__).resolve().parent.parent / "ai_services"
if str(AI_SERVICES_DIR) not in sys.path:
    sys.path.insert(0, str(AI_SERVICES_DIR))


EMBEDDING_MODEL = "gemini-embedding-001"

SUPABASE_URL = os.environ["SUPABASE_URL"]
# Fallback to SUPABASE_KEY since your .env has the service_role key there
SERVICE_KEY = os.environ.get(
    "SUPABASE_SERVICE_KEY") or os.environ.get("SUPABASE_KEY")

if not SERVICE_KEY:
    raise SystemExit(
        "Neither SUPABASE_SERVICE_KEY nor SUPABASE_KEY was found in environment or backend/.env."
    )

supabase_client = create_client(SUPABASE_URL, SERVICE_KEY)


def embed_text(text: str) -> list[float]:
    response = client.models.embed_content(
        model=EMBEDDING_MODEL,
        contents=[text],
    )
    if hasattr(response, "embeddings") and response.embeddings:
        return response.embeddings[0].values
    elif hasattr(response, "embedding") and response.embedding:
        return response.embedding.values
    else:
        raise ValueError(f"Unexpected response: {response}")


def main():
    print("Fetching food items from Supabase...")
    result = supabase_client.table("foods").select(
        "id, name, aliases, category").execute()
    foods = result.data

    print(f"Found {len(foods)} foods to process.")
    failed = []

    for i, food in enumerate(foods):
        text = food["name"]
        if food.get("aliases"):
            text += f", also known as {food['aliases']}"
        if food.get("category"):
            text += f", a {food['category']} dish"

        try:
            embedding = embed_text(text)
            update = (
                supabase_client.table("foods")
                .update({"embedding": embedding})
                .eq("id", food["id"])
                .execute()
            )

            if not update.data:
                failed.append(food["name"])
                print(f"  [{i + 1}/{len(foods)}] {food['name']} — NOT SAVED")
            else:
                print(f"  [{i + 1}/{len(foods)}] {food['name']} — done")

        except Exception as e:
            failed.append(food["name"])
            print(f"  [{i + 1}/{len(foods)}] {food['name']} — ERROR: {e}")

        time.sleep(0.5)  # Pause to respect Gemini rate limits

    if failed:
        print(f"\n{len(failed)} foods were NOT saved: {failed}")
    else:
        print("\nAll foods now have embeddings!")


if __name__ == "__main__":
    main()
