"""
check_embeddings.py  (put it in ai-services/ai_services/ next to cloudsql_db.py)

Finds which embedding model created the vectors stored in your foods table.

Run from the same folder you ran the other tests:
    python -m check_embeddings

For a few foods it embeds the food's name with each candidate model and
compares it to the vector stored in Cloud SQL:
    - the RIGHT model scores clearly high (about 0.75 to 1.00)
    - a WRONG model scores much lower (about 0.3 to 0.6), or fails with a size error
Then set the winner in backend/.env, for example:
    EMBEDDING_MODEL=text-embedding-004
    EMBEDDING_DIM=768
"""
try:
    from .cloudsql_db import run_query, vector_literal, close_connection
    from .gemini_client import client
except ImportError:
    from cloudsql_db import run_query, vector_literal, close_connection
    from gemini_client import client

from google.genai import types

# (model, output size to request or None for the model's own size)
CANDIDATES = [
    ("text-embedding-004", None),
    ("text-embedding-005", None),
    ("gemini-embedding-001", 768),
]

dims = run_query("SELECT vector_dims(embedding) AS d FROM foods WHERE embedding IS NOT NULL LIMIT 1")
print("Stored embedding size:", dims[0]["d"] if dims else "no embeddings found")

foods = run_query("SELECT id, name FROM foods WHERE embedding IS NOT NULL ORDER BY id LIMIT 6")
if not foods:
    raise SystemExit("No rows with an embedding. Import the foods data first.")

for model, size in CANDIDATES:
    label = f"{model}" + (f" (size {size})" if size else "")
    scores, error = [], None
    for food in foods:
        try:
            cfg = types.EmbedContentConfig(output_dimensionality=size) if size else None
            resp = client.models.embed_content(model=model, contents=[food["name"]], config=cfg)
            vec = list(resp.embeddings[0].values)
            row = run_query(
                "SELECT 1 - (embedding <=> CAST(:v AS vector)) AS sim FROM foods WHERE id = :id",
                {"v": vector_literal(vec), "id": food["id"]})
            scores.append(float(row[0]["sim"]))
        except Exception as e:
            error = f"{type(e).__name__}: {str(e)[:110]}"
            break
    if error:
        print(f"  {label:<40} FAILED  {error}")
    else:
        print(f"  {label:<40} average similarity {sum(scores) / len(scores):.2f}")

close_connection()