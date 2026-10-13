"""
check_embedding_size.py

Run this FIRST, before creating the embedding column in Supabase, to
confirm how many numbers the embedding model actually produces. Different
models produce different lengths, and the database column must match
exactly or it will reject every embedding you try to save.
"""

import sys
import os
# This script lives in scripts/, but gemini_client.py lives in the sibling
# ai_services/ folder. This line tells Python to also look there.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ai_services"))

from gemini_client import client

response = client.models.embed_content(
    model="gemini-embedding-001",
    contents=["Chicken curry, an Indian non-vegetarian dish"],
)

embedding = response.embeddings[0].values
print(f"This model produces embeddings of length: {len(embedding)}")
print(f"Use this number in your SQL: vector({len(embedding)})")