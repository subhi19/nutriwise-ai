"""
backfill_embeddings.py  (Google Cloud SQL + Vertex AI version)

Creates an embedding for every food in the foods table and saves it in the
`embedding` column. The search in nutrition_repo.py compares new searches against
these vectors, so the model and size used HERE must be the same ones used there.

Both read the same two settings from backend/.env:
    EMBEDDING_MODEL=text-embedding-004      (default)
    EMBEDDING_DIM=768                       (default; must equal the column size)

Run from the ai-services folder (the one that contains ai_services/ and scripts/):

    python scripts/backfill_embeddings.py            # only foods with NO embedding yet
    python scripts/backfill_embeddings.py --all      # redo every food (after changing the model)
    python scripts/backfill_embeddings.py --pause 1  # slower, if you hit Vertex AI quota (429)

Run it again whenever you add new foods. Use --all after you change
EMBEDDING_MODEL or EMBEDDING_DIM.

No keys are needed: it signs in with your Google Cloud login
(gcloud auth application-default login) and uses the Cloud SQL settings in
backend/.env. There is no service_role key any more.
"""
import argparse
import os
import re
import sys
import time

# This script lives in scripts/, but ai_services/ is its sibling folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from ai_services.cloudsql_db import run_query, run_write, vector_literal, close_connection
from ai_services.gemini_client import client

EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "text-embedding-004")
EMBEDDING_DIM = int(os.environ.get("EMBEDDING_DIM", "768"))


def column_dimension() -> int | None:
    """The size the embedding column was created with, e.g. 768 for vector(768)."""
    rows = run_query(
        "SELECT format_type(atttypid, atttypmod) AS t FROM pg_attribute "
        "WHERE attrelid = 'foods'::regclass AND attname = 'embedding'"
    )
    if not rows:
        return None
    match = re.search(r"\((\d+)\)", rows[0]["t"] or "")
    return int(match.group(1)) if match else None


def food_text(food: dict) -> str:
    """One descriptive text per food, so the embedding carries more context than
    the bare name. Keep this the same between runs."""
    text = food["name"]
    aliases = food.get("aliases")
    if isinstance(aliases, (list, tuple)):
        aliases = ", ".join(str(a) for a in aliases)
    if aliases:
        text += f", also known as {aliases}"
    if food.get("category"):
        text += f", a {food['category']} dish"
    return text


def embed_text(text: str) -> list[float]:
    config = None
    if EMBEDDING_MODEL.startswith("gemini-embedding"):
        # this model returns 3072 numbers by default; ask for the stored size
        from google.genai import types
        config = types.EmbedContentConfig(output_dimensionality=EMBEDDING_DIM)
    response = client.models.embed_content(model=EMBEDDING_MODEL, contents=[text], config=config)
    return list(response.embeddings[0].values)


def embed_with_retry(text: str, tries: int = 4) -> list[float]:
    """Retries with a growing pause, so a temporary rate limit (429) does not stop the run."""
    for attempt in range(1, tries + 1):
        try:
            return embed_text(text)
        except Exception:
            if attempt == tries:
                raise
            time.sleep(2 ** attempt)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true", help="redo every food, not only the missing ones")
    parser.add_argument("--pause", type=float, default=0.5, help="seconds to wait between foods")
    args = parser.parse_args()

    print(f"Embedding model: {EMBEDDING_MODEL}   size: {EMBEDDING_DIM}")

    # Stop early if the column size does not match, instead of failing on every row
    col_dim = column_dimension()
    if col_dim is None:
        raise SystemExit("Could not find the foods.embedding column. Create it first:\n"
                         f"    ALTER TABLE foods ADD COLUMN embedding vector({EMBEDDING_DIM});")
    if col_dim != EMBEDDING_DIM:
        raise SystemExit(
            f"The embedding column is vector({col_dim}) but EMBEDDING_DIM is {EMBEDDING_DIM}.\n"
            f"Either set EMBEDDING_DIM={col_dim} in backend/.env, or recreate the column:\n"
            "    ALTER TABLE foods DROP COLUMN embedding;\n"
            f"    ALTER TABLE foods ADD COLUMN embedding vector({EMBEDDING_DIM});\n"
            "and then run this script with --all."
        )

    where = "" if args.all else "WHERE embedding IS NULL"
    foods = run_query(f"SELECT id, name, aliases, category FROM foods {where} ORDER BY id")
    print(f"Found {len(foods)} foods to process" + ("" if args.all else " (those without an embedding)."))

    failed = []
    for i, food in enumerate(foods, 1):
        try:
            vector = embed_with_retry(food_text(food))
            if len(vector) != EMBEDDING_DIM:
                raise ValueError(f"model returned {len(vector)} numbers, expected {EMBEDDING_DIM}")
            changed = run_write(
                "UPDATE foods SET embedding = CAST(:v AS vector) WHERE id = :id",
                {"v": vector_literal(vector), "id": food["id"]},
            )
            if changed == 0:  # nothing saved, so do not pretend it was
                raise RuntimeError("the row was not updated")
            print(f"  [{i}/{len(foods)}] {food['name']} - done")
        except Exception as e:
            failed.append(food["name"])
            print(f"  [{i}/{len(foods)}] {food['name']} - NOT SAVED ({type(e).__name__}: {str(e)[:100]})")
        time.sleep(args.pause)

    summary = run_query("SELECT count(*) AS total, count(embedding) AS embedded FROM foods")[0]
    print(f"\nTable now has {summary['embedded']} embeddings for {summary['total']} foods.")
    if failed:
        print(f"{len(failed)} foods were NOT saved: {failed}")
        print("Run the script again to retry them.")
    else:
        print("All processed foods are saved.")
    close_connection()


if __name__ == "__main__":
    main()