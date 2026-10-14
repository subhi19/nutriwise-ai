from gemini_client import client
import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# 1. Locate and load backend/.env into environment variables first
BACKEND_DIR = Path(__file__).resolve().parent.parent.parent / "backend"
ENV_PATH = BACKEND_DIR / ".env"
load_dotenv(dotenv_path=ENV_PATH)

# Also ensure GOOGLE_API_KEY is synced if only GEMINI_API_KEY is present
if "GEMINI_API_KEY" in os.environ and "GOOGLE_API_KEY" not in os.environ:
    os.environ["GOOGLE_API_KEY"] = os.environ["GEMINI_API_KEY"]

# 2. Add sibling ai_services/ directory to Python search path
AI_SERVICES_DIR = Path(__file__).resolve().parent.parent / "ai_services"
if str(AI_SERVICES_DIR) not in sys.path:
    sys.path.insert(0, str(AI_SERVICES_DIR))


print("Testing Gemini embedding generation...")

response = client.models.embed_content(
    model="gemini-embedding-001",
    contents=["Chicken curry, an Indian non-vegetarian dish"],
)

# Extract vector values
if hasattr(response, "embeddings") and response.embeddings:
    embedding = response.embeddings[0].values
elif hasattr(response, "embedding") and response.embedding:
    embedding = response.embedding.values
else:
    raise ValueError(f"Unexpected response structure: {response}")

print(f"\nSUCCESS!")
print(f"This model produces embeddings of length: {len(embedding)}")
print(f"Use this number in your SQL: vector({len(embedding)})")
