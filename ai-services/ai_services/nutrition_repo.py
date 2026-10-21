# """
# nutrition_repo.py (v3 - Google Cloud SQL)

# The ONLY place that reads the foods table. It now talks to Google Cloud SQL
# (PostgreSQL + pgvector) through cloudsql_db.py instead of Supabase.

# Matching works the same way as v2:
#   1. Load all foods once (the table is small), lazily on first search.
#   2. Compare the search term and each food name by SHARED important words.
#   3. If nothing matches well, fall back to vector (meaning) search with pgvector.

# What changed from v2:
#   - Supabase client removed; no SUPABASE_URL / SUPABASE_KEY needed.
#   - The foods table is loaded on first use, not at import, so importing this
#     file never needs a database connection.
#   - The match_foods() RPC became a normal SQL query using pgvector's <=>.
#   - Each food's name and aliases are scored separately, and ties go to the food
#     that shares the most exact words and has the fewest EXTRA words. So "chicken"
#     prefers "Chicken (raw)" over "Fried chicken (malaysian style)", while
#     "fried chicken" still finds the fried one.
# """
# import os
# import threading
# from pathlib import Path

# try:
#     from dotenv import load_dotenv
#     load_dotenv()
#     load_dotenv(dotenv_path=Path(__file__).resolve().parent.parent.parent / "backend" / ".env")
# except ImportError:
#     pass

# try:
#     from .cloudsql_db import run_query, vector_literal
# except ImportError:  # running this file directly
#     from cloudsql_db import run_query, vector_literal


# # Words that appear often in Gemini's descriptions but rarely matter for matching.
# FILLER_WORDS = {
#     "cooked", "raw", "sliced", "fresh", "diced", "chopped", "boiled",
#     "fried", "dry", "steamed", "grilled", "roasted", "plain", "small",
#     "medium", "large", "piece", "pieces", "bowl", "cup", "serving",
#     "with", "and", "of", "the", "a", "an",
#     # cuts and parts: "chicken breast" is still chicken
#     "breast", "thigh", "leg", "wing", "wings", "fillet", "drumstick",
#     "boneless", "skinless", "whole",
# }

# # Only the columns the app uses. Never select the embedding column here.
# FOOD_COLUMNS = (
#     "id, name, aliases, category, typical_serving_g, calories, protein_g, "
#     "carbs_g, fat_g, fiber_g, iron_mg, calcium_mg, vitamin_a_mcg, vitamin_c_mg"
# )

# # Vector matches at or above STRONG_MATCH are trusted like a normal match.
# # Matches between the minimum and this are accepted but flagged "needs review".
# VECTOR_MIN_SIMILARITY = 0.7
# STRONG_MATCH = 0.85

# # Must be the SAME model and size that created the embeddings stored in the foods
# # table (your column is vector(768)). Set EMBEDDING_MODEL / EMBEDDING_DIM in
# # backend/.env if different. Run check_embeddings.py to find the right model.
# EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "text-embedding-004")
# EMBEDDING_DIM = int(os.environ.get("EMBEDDING_DIM", "768"))

# # Words in a search that may be left unmatched. Any OTHER search word that the
# # food does not have means it is a different food ("coconut milk" is not "Milk").
# SOFT_WORDS = {
#     "red", "green", "white", "black", "yellow", "brown", "baby", "young",
#     "organic", "ripe", "unripe", "hot", "cold", "mixed", "mix", "local",
#     "homemade", "indian", "malaysian", "chinese", "thai",
# }

# # If the search term has one of these words, the food MUST have it too.
# # Otherwise "chicken curry" would match plain "Chicken (whole, raw)".
# DEFINING_WORDS = {
#     "curry", "soup", "stew", "salad", "sandwich", "burger", "pizza", "pasta",
#     "noodle", "noodles", "biryani", "pulao", "porridge", "omelette", "omelet",
#     "juice", "milk", "oil", "powder", "sauce", "paste", "butter", "tea",
#     "coffee", "bread", "flour", "cake", "chutney", "dumpling", "kebab",
#     "cheese", "yogurt", "curd", "ghee", "cream", "jam", "pickle",
# }


# def _words(text: str, drop_fillers: bool = True) -> set[str]:
#     """'Cooked basmati rice' -> {'basmati', 'rice'}; text in brackets is ignored."""
#     text = (text or "").lower().split("(")[0]
#     words = text.replace(",", " ").split()
#     return {w for w in words if not (drop_fillers and w in FILLER_WORDS)}


# def _normalize(text: str) -> set[str]:
#     return _words(text, drop_fillers=True)


# def _head_word(text: str) -> str | None:
#     """The main word of a food name: its last important word.
#     'dry chicken curry' -> 'curry', 'sliced red onion' -> 'onion'."""
#     text = (text or "").lower().split("(")[0].replace(",", " ")
#     important = [w for w in text.split() if w not in FILLER_WORDS]
#     return important[-1] if important else None


# def _alias_list(aliases) -> list[str]:
#     """aliases can be 'a, b' text (old table) or a Postgres text[] (list)."""
#     if not aliases:
#         return []
#     if isinstance(aliases, (list, tuple)):
#         return [str(a) for a in aliases]
#     return str(aliases).split(",")


# def is_weak_match(food: dict | None) -> bool:
#     """True if this food came from a medium-confidence vector match."""
#     if not food:
#         return False
#     similarity = food.get("similarity")
#     return similarity is not None and similarity < STRONG_MATCH


# # --- Foods table, loaded once on first use ----------------------------------

# _lock = threading.Lock()
# _all_foods: list[dict] | None = None
# # (food, [(important words, all words), ...]) - one entry per name or alias
# _food_index: list[tuple[dict, list[tuple[set[str], set[str]]]]] = []


# def _load_all_foods() -> list[dict]:
#     return run_query(f"SELECT {FOOD_COLUMNS} FROM foods")


# def _build_index(foods: list[dict]):
#     index = []
#     for food in foods:
#         # The name and each alias are scored SEPARATELY. (Merging them into one
#         # word set makes a food with aliases look like a worse match.)
#         variants = [(_normalize(food["name"]), _words(food["name"], drop_fillers=False))]
#         for alias in _alias_list(food.get("aliases")):
#             variants.append((_normalize(alias), _words(alias, drop_fillers=False)))
#         index.append((food, [v for v in variants if v[0]]))
#     return index


# def _ensure_loaded():
#     global _all_foods, _food_index
#     if _all_foods is not None:
#         return
#     with _lock:
#         if _all_foods is None:
#             foods = _load_all_foods()
#             _food_index = _build_index(foods)
#             _all_foods = foods


# def refresh_food_cache():
#     """Call after adding rows to the foods table while the program is running."""
#     global _all_foods, _food_index
#     with _lock:
#         foods = _load_all_foods()
#         _food_index = _build_index(foods)
#         _all_foods = foods


# # --- Search -------------------------------------------------------------------

# def search_food(name: str):
#     """
#     Look up a food by name using word overlap, then vector search as a fallback.
#     Returns the matching row (a dict) or None.
#     """
#     _ensure_loaded()
#     query_words = _normalize(name)
#     if not query_words:
#         return None
#     query_all = _words(name, drop_fillers=False)

#     query_defining = query_words & DEFINING_WORDS
#     query_head = _head_word(name)
#     best_food, best_key = None, None
#     for food, variants in _food_index:
#         for food_words, food_all in variants:
#             shared = query_words & food_words
#             if not shared:
#                 continue
#             # Dish-defining words must agree both ways. "chicken curry" must not match
#             # plain "Chicken", and must not match "Curry powder" (extra word "powder").
#             if (food_words & DEFINING_WORDS) != query_defining:
#                 continue
#             # The main word of the search must be in the food:
#             # "butter chicken" must not match "Butter".
#             if query_head and query_head not in food_words:
#                 continue
#             # Every other search word must be in the food too, except harmless
#             # descriptions. "coconut milk" must not match plain "Milk".
#             if query_words - food_words - SOFT_WORDS:
#                 continue
#             score = len(shared) / len(food_words)       # how much of the food's name is covered
#             shared_raw = len(query_all & food_all)       # exact words in common, fillers included
#             extra = len(food_all - query_all)            # words the food has that the query never asked for
#             key = (score, shared_raw, -extra)
#             if best_key is None or key > best_key:
#                 best_food, best_key = food, key

#     if best_key is not None and best_key[0] >= 0.5:
#         return best_food

#     return vector_search_food(name)


# def vector_search_food(name: str):
#     """
#     Meaning-based search with pgvector. Only used when word matching finds nothing.
#     Returns a row that includes a 'similarity' value, or None.
#     """
#     try:
#         try:
#             from .gemini_client import client as gemini_client
#         except ImportError:
#             from gemini_client import client as gemini_client

#         config = None
#         if EMBEDDING_MODEL.startswith("gemini-embedding"):
#             # this model returns 3072 numbers by default; ask for the stored size
#             from google.genai import types
#             config = types.EmbedContentConfig(output_dimensionality=EMBEDDING_DIM)
#         response = gemini_client.models.embed_content(
#             model=EMBEDDING_MODEL, contents=[name], config=config)
#         embedding = response.embeddings[0].values
#         if len(embedding) != EMBEDDING_DIM:
#             print(f"[nutrition_repo] embedding has {len(embedding)} numbers but the table "
#                   f"expects {EMBEDDING_DIM}. Set EMBEDDING_MODEL / EMBEDDING_DIM in backend/.env.")
#             return None

#         rows = run_query(
#             f"""
#             SELECT {FOOD_COLUMNS},
#                    1 - (embedding <=> CAST(:v AS vector)) AS similarity
#             FROM foods
#             WHERE embedding IS NOT NULL
#             ORDER BY embedding <=> CAST(:v AS vector)
#             LIMIT 1
#             """,
#             {"v": vector_literal(list(embedding))},
#         )
#     except Exception as e:
#         # A failed fallback must never break a whole meal plan
#         print(f"[nutrition_repo] vector search failed for {name!r}: {type(e).__name__}: {e}")
#         return None

#     if rows and rows[0]["similarity"] is not None and rows[0]["similarity"] >= VECTOR_MIN_SIMILARITY:
#         return rows[0]
#     return None


# def get_food_by_id(food_id: int):
#     """Look up a food by its numeric id. Used when re-displaying a saved item."""
#     rows = run_query(f"SELECT {FOOD_COLUMNS} FROM foods WHERE id = :id", {"id": food_id})
#     return rows[0] if rows else None


# # --- Quick test:  python -m ai_services.nutrition_repo -----------------------

# if __name__ == "__main__":
#     for test in ["chicken curry", "dry chicken curry", "cooked white rice", "sliced red onion",
#                  "sliced tomato", "green chili", "roti", "biryani", "chicken", "something made up"]:
#         food = search_food(test)
#         if food:
#             print(f'"{test}" matched -> {food["name"]} ({food["calories"]} kcal per 100g)')
#         else:
#             print(f'"{test}" -> no match found')
#     try:
#         from .cloudsql_db import close_connection
#     except ImportError:
#         from cloudsql_db import close_connection
#     close_connection()

"""
nutrition_repo.py (v3 - Google Cloud SQL)

The ONLY place that reads the foods table. It now talks to Google Cloud SQL
(PostgreSQL + pgvector) through cloudsql_db.py instead of Supabase.

Matching works the same way as v2:
  1. Load all foods once (the table is small), lazily on first search.
  2. Compare the search term and each food name by SHARED important words.
  3. If nothing matches well, fall back to vector (meaning) search with pgvector.

What changed from v2:
  - Supabase client removed; no SUPABASE_URL / SUPABASE_KEY needed.
  - The foods table is loaded on first use, not at import, so importing this
    file never needs a database connection.
  - The match_foods() RPC became a normal SQL query using pgvector's <=>.
  - Each food's name and aliases are scored separately, and ties go to the food
    that shares the most exact words and has the fewest EXTRA words. So "chicken"
    prefers "Chicken (raw)" over "Fried chicken (malaysian style)", while
    "fried chicken" still finds the fried one.
"""
import os
import threading
from pathlib import Path

try:
    from dotenv import load_dotenv
    load_dotenv()
    load_dotenv(dotenv_path=Path(__file__).resolve().parent.parent.parent / "backend" / ".env")
except ImportError:
    pass

try:
    from .cloudsql_db import run_query, vector_literal
except ImportError:  # running this file directly
    from cloudsql_db import run_query, vector_literal


# Words that appear often in Gemini's descriptions but rarely matter for matching.
FILLER_WORDS = {
    "cooked", "raw", "sliced", "fresh", "diced", "chopped", "boiled",
    "fried", "dry", "steamed", "grilled", "roasted", "plain", "small",
    "medium", "large", "piece", "pieces", "bowl", "cup", "serving",
    "with", "and", "of", "the", "a", "an",
    # cuts and parts: "chicken breast" is still chicken
    "breast", "thigh", "leg", "wing", "wings", "fillet", "drumstick",
    "boneless", "skinless", "whole",
}

# Only the columns the app uses. Never select the embedding column here.
FOOD_COLUMNS = (
    "id, name, aliases, category, typical_serving_g, calories, protein_g, "
    "carbs_g, fat_g, fiber_g, iron_mg, calcium_mg, vitamin_a_mcg, vitamin_c_mg"
)

# Vector matches at or above STRONG_MATCH are trusted like a normal match.
# Matches between the minimum and this are accepted but flagged "needs review".
VECTOR_MIN_SIMILARITY = 0.7
STRONG_MATCH = 0.85

# Must be the SAME model and size that created the embeddings stored in the foods
# table (your column is vector(768)). Set EMBEDDING_MODEL / EMBEDDING_DIM in
# backend/.env if different. Run check_embeddings.py to find the right model.
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "text-embedding-004")
EMBEDDING_DIM = int(os.environ.get("EMBEDDING_DIM", "768"))

# Words in a search that may be left unmatched. Any OTHER search word that the
# food does not have means it is a different food ("coconut milk" is not "Milk").
SOFT_WORDS = {
    "red", "green", "white", "black", "yellow", "brown", "baby", "young",
    "organic", "ripe", "unripe", "hot", "cold", "mixed", "mix", "local",
    "homemade", "indian", "malaysian", "chinese", "thai",
}

# If the search term has one of these words, the food MUST have it too.
# Otherwise "chicken curry" would match plain "Chicken (whole, raw)".
DEFINING_WORDS = {
    "curry", "soup", "stew", "salad", "sandwich", "burger", "pizza", "pasta",
    "noodle", "noodles", "biryani", "pulao", "porridge", "omelette", "omelet",
    "juice", "milk", "oil", "powder", "sauce", "paste", "butter", "tea",
    "coffee", "bread", "flour", "cake", "chutney", "dumpling", "kebab",
    "cheese", "yogurt", "curd", "ghee", "cream", "jam", "pickle",
}


def _words(text: str, drop_fillers: bool = True) -> set[str]:
    """'Cooked basmati rice' -> {'basmati', 'rice'}; text in brackets is ignored."""
    text = (text or "").lower().split("(")[0]
    words = text.replace(",", " ").split()
    return {w for w in words if not (drop_fillers and w in FILLER_WORDS)}


def _normalize(text: str) -> set[str]:
    return _words(text, drop_fillers=True)


def _head_word(text: str) -> str | None:
    """The main word of a food name: its last important word.
    'dry chicken curry' -> 'curry', 'sliced red onion' -> 'onion'."""
    text = (text or "").lower().split("(")[0].replace(",", " ")
    important = [w for w in text.split() if w not in FILLER_WORDS]
    return important[-1] if important else None


def _alias_list(aliases) -> list[str]:
    """aliases can be 'a, b' text (old table) or a Postgres text[] (list)."""
    if not aliases:
        return []
    if isinstance(aliases, (list, tuple)):
        return [str(a) for a in aliases]
    return str(aliases).split(",")


def is_weak_match(food: dict | None) -> bool:
    """True if this food came from a medium-confidence vector match."""
    if not food:
        return False
    similarity = food.get("similarity")
    return similarity is not None and similarity < STRONG_MATCH


# --- Foods table, loaded once on first use ----------------------------------

_lock = threading.Lock()
_all_foods: list[dict] | None = None
# (food, [(important words, all words), ...]) - one entry per name or alias
_food_index: list[tuple[dict, list[tuple[set[str], set[str]]]]] = []


def _load_all_foods() -> list[dict]:
    return run_query(f"SELECT {FOOD_COLUMNS} FROM foods")


def _build_index(foods: list[dict]):
    index = []
    for food in foods:
        # The name and each alias are scored SEPARATELY. (Merging them into one
        # word set makes a food with aliases look like a worse match.)
        variants = [(_normalize(food["name"]), _words(food["name"], drop_fillers=False))]
        for alias in _alias_list(food.get("aliases")):
            variants.append((_normalize(alias), _words(alias, drop_fillers=False)))
        index.append((food, [v for v in variants if v[0]]))
    return index


def _ensure_loaded():
    global _all_foods, _food_index
    if _all_foods is not None:
        return
    with _lock:
        if _all_foods is None:
            foods = _load_all_foods()
            _food_index = _build_index(foods)
            _all_foods = foods


def refresh_food_cache():
    """Call after adding rows to the foods table while the program is running."""
    global _all_foods, _food_index
    with _lock:
        foods = _load_all_foods()
        _food_index = _build_index(foods)
        _all_foods = foods


# --- Search -------------------------------------------------------------------

def search_food(name: str):
    """
    Look up a food by name using word overlap, then vector search as a fallback.
    Returns the matching row (a dict) or None.
    """
    _ensure_loaded()
    query_words = _normalize(name)
    if not query_words:
        return None
    query_all = _words(name, drop_fillers=False)

    query_defining = query_words & DEFINING_WORDS
    query_head = _head_word(name)
    best_food, best_key = None, None
    for food, variants in _food_index:
        for food_words, food_all in variants:
            shared = query_words & food_words
            if not shared:
                continue
            # Dish-defining words must agree both ways. "chicken curry" must not match
            # plain "Chicken", and must not match "Curry powder" (extra word "powder").
            if (food_words & DEFINING_WORDS) != query_defining:
                continue
            # The main word of the search must be in the food:
            # "butter chicken" must not match "Butter".
            if query_head and query_head not in food_words:
                continue
            # Every other search word must be in the food too, except harmless
            # descriptions. "coconut milk" must not match plain "Milk".
            if query_words - food_words - SOFT_WORDS:
                continue
            score = len(shared) / len(food_words)       # how much of the food's name is covered
            shared_raw = len(query_all & food_all)       # exact words in common, fillers included
            extra = len(food_all - query_all)            # words the food has that the query never asked for
            key = (score, shared_raw, -extra)
            if best_key is None or key > best_key:
                best_food, best_key = food, key

    if best_key is not None and best_key[0] >= 0.5:
        return best_food

    return vector_search_food(name)


def vector_search_food(name: str):
    """
    Meaning-based search with pgvector. Only used when word matching finds nothing.
    Returns a row that includes a 'similarity' value, or None.
    """
    try:
        try:
            from .gemini_client import client as gemini_client
        except ImportError:
            from gemini_client import client as gemini_client

        config = None
        if EMBEDDING_MODEL.startswith("gemini-embedding"):
            # this model returns 3072 numbers by default; ask for the stored size
            from google.genai import types
            config = types.EmbedContentConfig(output_dimensionality=EMBEDDING_DIM)
        response = gemini_client.models.embed_content(
            model=EMBEDDING_MODEL, contents=[name], config=config)
        embedding = response.embeddings[0].values
        if len(embedding) != EMBEDDING_DIM:
            print(f"[nutrition_repo] embedding has {len(embedding)} numbers but the table "
                  f"expects {EMBEDDING_DIM}. Set EMBEDDING_MODEL / EMBEDDING_DIM in backend/.env.")
            return None

        rows = run_query(
            f"""
            SELECT {FOOD_COLUMNS},
                   1 - (embedding <=> CAST(:v AS vector)) AS similarity
            FROM foods
            WHERE embedding IS NOT NULL
            ORDER BY embedding <=> CAST(:v AS vector)
            LIMIT 1
            """,
            {"v": vector_literal(list(embedding))},
        )
    except Exception as e:
        # A failed fallback must never break a whole meal plan
        print(f"[nutrition_repo] vector search failed for {name!r}: {type(e).__name__}: {e}")
        return None

    if rows and rows[0]["similarity"] is not None and rows[0]["similarity"] >= VECTOR_MIN_SIMILARITY:
        return rows[0]
    return None


def get_food_by_id(food_id: int):
    """Look up a food by its numeric id. Used when re-displaying a saved item."""
    rows = run_query(f"SELECT {FOOD_COLUMNS} FROM foods WHERE id = :id", {"id": food_id})
    return rows[0] if rows else None


# --- Quick test:  python -m ai_services.nutrition_repo -----------------------

if __name__ == "__main__":
    for test in ["chicken curry", "dry chicken curry", "cooked white rice", "sliced red onion",
                 "sliced tomato", "green chili", "roti", "biryani", "chicken", "something made up"]:
        food = search_food(test)
        if food:
            print(f'"{test}" matched -> {food["name"]} ({food["calories"]} kcal per 100g)')
        else:
            print(f'"{test}" -> no match found')
    try:
        from .cloudsql_db import close_connection
    except ImportError:
        from cloudsql_db import close_connection
    close_connection()