"""
backfill_embeddings.py

Run this ONCE, after Steps 1-4 are done, to generate an embedding for
every food already in your table. Run it again any time you add new
foods, so they get embeddings too.

This uses the Gemini embedding model, not your normal flash model —
embeddings have their own separate quota, so this won't eat into your
meal-analysis/meal-plan quota.
"""

import sys
import os
# This script lives in scripts/, but gemini_client.py and nutrition_repo.py
# live in the sibling ai_services/ folder. This line tells Python to also
# look there.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ai_services"))

import time
from gemini_client import client
from nutrition_repo import client as supabase_client  # the Supabase connection


def embed_text(text: str) -> list[float]:
    response = client.models.embed_content(
        model="gemini-embedding-001",
        contents=[text],
    )
    return response.embeddings[0].values


def main():
    # Get every food that doesn't have an embedding yet
    result = supabase_client.table("foods").select("id, name, aliases, category").execute()
    foods = result.data

    print(f"Found {len(foods)} foods to process.")

    for i, food in enumerate(foods):
        # Combine name + aliases + category into one descriptive text,
        # so the embedding captures more context than the bare name alone
        text = food["name"]
        if food.get("aliases"):
            text += f", also known as {food['aliases']}"
        if food.get("category"):
            text += f", a {food['category']} dish"

        embedding = embed_text(text)

        supabase_client.table("foods").update({"embedding": embedding}).eq("id", food["id"]).execute()

        print(f"  [{i + 1}/{len(foods)}] {food['name']} — done")
        time.sleep(0.5)  # small pause, be gentle on the free-tier rate limit

    print("\nAll foods now have embeddings.")


if __name__ == "__main__":
    main()