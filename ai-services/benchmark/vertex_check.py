"""
Quick check that Vertex AI works for your project, BEFORE you rerun the benchmark.

PowerShell, from the ai-services folder:
    $env:GCP_PROJECT="your-project-id"
    $env:GCP_LOCATION="us-central1"          # or "global"
    $env:MODEL_NAME="your-model-name"        # the same model name your app uses
    python benchmark/vertex_check.py

It runs one text call and one embedding call, then prints timings and the embedding size.
The embedding size must be 3072 to match your foods table.
"""
import os
import sys
import time

try:
    from google import genai
except ImportError:
    print("Install the SDK first:  pip install --upgrade google-genai")
    sys.exit(1)

project = os.getenv("GCP_PROJECT")
location = os.getenv("GCP_LOCATION", "us-central1")
model = os.getenv("MODEL_NAME")
if not project or not model:
    print("Set GCP_PROJECT and MODEL_NAME first (see the top of this file).")
    sys.exit(1)

client = genai.Client(vertexai=True, project=project, location=location)
print(f"Vertex AI | project={project} | location={location} | model={model}\n")

t0 = time.perf_counter()
try:
    r = client.models.generate_content(model=model, contents="Reply with the single word: ready")
    print(f"Text call OK in {time.perf_counter() - t0:.1f}s -> {r.text.strip()[:60]!r}")
except Exception as e:
    print(f"Text call FAILED: {type(e).__name__}: {str(e)[:300]}")
    print("Common causes: Vertex AI API not enabled, billing off, no 'Vertex AI User' role, "
          "wrong location, or this model name is not available in that location.")
    sys.exit(1)

t0 = time.perf_counter()
try:
    e = client.models.embed_content(model="gemini-embedding-001", contents=["paneer tikka"])
    dim = len(e.embeddings[0].values)
    print(f"Embedding call OK in {time.perf_counter() - t0:.1f}s -> {dim} dimensions "
          + ("(matches your table)" if dim == 3072 else "(DOES NOT match 3072: do not use until fixed)"))
except Exception as ex:
    print(f"Embedding call FAILED: {type(ex).__name__}: {str(ex)[:300]}")
    sys.exit(1)