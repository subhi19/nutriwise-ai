"""
nutrition_repo.py (v2 - smarter matching)

Same purpose as before: the ONLY place that talks to Supabase.

What changed: instead of simple substring matching, we now compare foods
by their SHARED WORDS. This fixes cases like:
  - "cooked white rice" matching "Cooked basmati rice" (word order differs)
  - "dry chicken curry" matching "Chicken curry" (extra word "dry")
  - "sliced red onion" matching "Onion (raw)" (extra words, different order)

How it works:
  1. Load all foods once when the program starts (the table is small,
     under 100 rows, so this is fast and simple).
  2. Break both the search term and each food's name into individual words.
  3. Ignore common "filler" words that don't help matching (cooked, raw,
     sliced, fresh, etc.) since they appear in Gemini's descriptions but
     not always in our database names.
  4. Score each food by how many important words it shares with the
     search term, and return the best match.
"""

import os
from supabase import create_client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_KEY"]

client = create_client(SUPABASE_URL, SUPABASE_KEY)


# Words that appear often in Gemini's descriptions but rarely matter for
# matching. Feel free to add more as you notice mismatches.
FILLER_WORDS = {
    "cooked", "raw", "sliced", "fresh", "diced", "chopped", "boiled",
    "fried", "dry", "steamed", "grilled", "roasted", "plain", "small",
    "medium", "large", "piece", "pieces", "bowl", "cup", "serving",
    "with", "and", "of", "the", "a", "an",
}


def _normalize(text: str) -> set[str]:
    """
    Turns a food name into a set of important lowercase words.
    e.g. "Cooked basmati rice" -> {"basmati", "rice"}
    e.g. "sliced red onion" -> {"red", "onion"}
    """
    text = text.lower()
    # remove anything in parentheses, e.g. "Onion (raw)" -> "Onion "
    text = text.split("(")[0]
    words = text.replace(",", " ").split()
    return {w for w in words if w not in FILLER_WORDS}


# --- Load the whole table once, so we don't hit the database every search --

def _load_all_foods() -> list[dict]:
    result = client.table("foods").select("*").execute()
    return result.data


_all_foods = _load_all_foods()

# Pre-compute the normalized word set for every food, once, so searching is fast
_food_word_sets = []
for food in _all_foods:
    words = _normalize(food["name"])
    if food.get("aliases"):
        for alias in food["aliases"].split(","):
            words |= _normalize(alias)
    _food_word_sets.append((food, words))


# --- The main function you will use ----------------------------------------

def search_food(name: str):
    """
    Look up a food by name using word-overlap matching.

    Example:
        search_food("dry chicken curry")  ->  matches "Chicken curry"

    Returns the matching row (a dictionary) or None if nothing matches
    well enough.
    """
    query_words = _normalize(name)
    if not query_words:
        return None

    best_food = None
    best_score = 0

    for food, food_words in _food_word_sets:
        shared = query_words & food_words  # words that appear in both
        if not shared:
            continue
        # Score: how much of the food's own name is covered by the query.
        # This favors a food whose words are mostly matched, over a food
        # that only shares one word out of many.
        score = len(shared) / len(food_words)
        if score > best_score:
            best_score = score
            best_food = food

    # Require at least a reasonable overlap, so unrelated foods don't match
    if best_score >= 0.5:
        return best_food
    return None


def get_food_by_id(food_id: int):
    """Look up a food by its numeric id. Used when re-displaying a saved item."""
    result = client.table("foods").select("*").eq("id", food_id).execute()
    if result.data:
        return result.data[0]
    return None


def refresh_food_cache():
    """
    Call this if you add new rows to the foods table while your program
    is already running, so it picks up the new data without restarting.
    """
    global _all_foods, _food_word_sets
    _all_foods = _load_all_foods()
    _food_word_sets = []
    for food in _all_foods:
        words = _normalize(food["name"])
        if food.get("aliases"):
            for alias in food["aliases"].split(","):
                words |= _normalize(alias)
        _food_word_sets.append((food, words))


# --- Quick test you can run directly -----------------------------------
# python nutrition_repo.py

if __name__ == "__main__":
    test_names = [
        "chicken curry",
        "dry chicken curry",
        "cooked white rice",
        "sliced red onion",
        "sliced tomato",
        "green chili",
        "roti",
        "biryani",
        "something made up",
    ]
    for name in test_names:
        food = search_food(name)
        if food:
            print(f'"{name}" matched -> {food["name"]} ({food["calories"]} kcal per 100g)')
        else:
            print(f'"{name}" -> no match found')