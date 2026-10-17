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

import sys
import os
# This script lives in scripts/, but gemini_client.py lives in the
# sibling ai_services/ folder. This line tells Python to also look there.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import time
from supabase import create_client
from ai_services.gemini_client import client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SERVICE_KEY = os.environ.get("SUPABASE_KEY")

if not SERVICE_KEY:
    raise SystemExit(
        "SUPABASE_SERVICE_KEY is not set. Get it from Supabase -> Project Settings -> API "
        "(the service_role key), then run:\n"
        '    $env:SUPABASE_SERVICE_KEY="your_service_role_key"\n'
        "Use it only in your own terminal, never commit it anywhere."
    )

supabase_client = create_client(SUPABASE_URL, SERVICE_KEY)


def embed_text(text: str) -> list[float]:
    response = client.models.embed_content(
        model="gemini-embedding-001",
        contents=[text],
    )
    return response.embeddings[0].values


def main():
    result = supabase_client.table("foods").select("id, name, aliases, category").execute()
    foods = result.data

    print(f"Found {len(foods)} foods to process.")
    failed = []

    for i, food in enumerate(foods):
        # Combine name + aliases + category into one descriptive text,
        # so the embedding captures more context than the bare name alone
        text = food["name"]
        if food.get("aliases"):
            text += f", also known as {food['aliases']}"
        if food.get("category"):
            text += f", a {food['category']} dish"

        embedding = embed_text(text)

        update = supabase_client.table("foods").update({"embedding": embedding}).eq("id", food["id"]).execute()

        # If nothing came back, the save didn't actually happen — don't pretend it did
        if not update.data:
            failed.append(food["name"])
            print(f"  [{i + 1}/{len(foods)}] {food['name']} — NOT SAVED")
        else:
            print(f"  [{i + 1}/{len(foods)}] {food['name']} — done")

        time.sleep(0.5)  # small pause, be gentle on the free-tier rate limit

    if failed:
        print(f"\n{len(failed)} foods were NOT saved: {failed}")
        print("Check that you used the service_role key, not the anon key.")
    else:
        print("\nAll foods now have embeddings.")


if __name__ == "__main__":
    main()