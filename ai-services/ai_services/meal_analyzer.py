"""
meal_analyzer.py

This is the main function your backend will call: analyze_meal().

What it does, step by step:
  1. Sends the photo to Gemini, asking ONLY for food names and estimated
     weights (not calories — Gemini is bad at guessing those consistently).
  2. Looks up each food name in our Supabase nutrition table.
  3. Calculates the real nutrition based on the estimated weight.
  4. Checks which nutrients are low for this meal.
  5. Asks Gemini (text only, fast) to write 1-2 short suggestions.
  6. Returns everything as a MealAnalysis object, matching schemas.py.
"""

import json
from google.genai import types

from .nutrition_repo import is_weak_match, search_food
from .calculator import calculate_nutrients, add_totals
from .schemas import MealAnalysis, MealItem, NutrientTotals
from .retry_utils import call_with_retry
from .gemini_client import client, MODEL_NAME  # the one shared Gemini connection


# --- Step 1: Ask Gemini what's on the plate ---------------------------------

VISION_PROMPT = """You are a nutrition assistant. Look at the food in this image.

1. Identify every distinct food item and drink you can see.
2. IMPORTANT: If a dish is a mix of protein and clearly visible vegetables
   (for example a stir-fry, chili chicken, or chicken with capsicum and
   onion), list the protein and each main vegetable as SEPARATE items,
   with their own estimated weight. Do not merge them into one generic
   dish name. Only keep a dish as ONE item if it is a smooth, blended
   preparation where ingredients cannot be visually separated (like a
   dal, a gravy curry, or a soup).
3. For each item, give a simple search-friendly name (e.g. "chicken",
   "capsicum", "roti", "boiled egg") rather than a fancy restaurant name.
4. Estimate its weight in grams, using the plate, bowls, and cutlery as
   size references.
5. Give a confidence level: low, medium, or high.

Do NOT estimate calories or nutrients. Only identify the food and its weight.

Return JSON only, no extra text, in this format:
{
  "items": [
    {"search_term": "", "weight_g": 0, "confidence": "low/medium/high"}
  ]
}"""


def _call_gemini_vision(image_bytes: bytes, mime_type: str) -> list[dict]:
    """Sends the photo to Gemini and returns the raw list of detected items."""
    def make_request():
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=[
                types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                VISION_PROMPT,
            ],
            config=types.GenerateContentConfig(response_mime_type="application/json"),
        )
        return json.loads(response.text)

    data = call_with_retry(make_request, label="Gemini (meal vision)")
    return data["items"]


NUTRIENT_KEYS = [
    "calories", "protein_g", "carbs_g", "fat_g", "fiber_g",
    "iron_mg", "calcium_mg", "vitamin_a_mcg", "vitamin_c_mg",
]


def estimate_nutrients_with_gemini(name: str, weight_g: float) -> dict:
    """
    Fallback for foods that are NOT in our database.

    This is less reliable than the database (the numbers can vary between
    calls, same as your very first test), so anything using this path
    should stay marked as "needs review" in the result. We use it only
    so the user sees a reasonable number instead of a flat 0.
    """
    prompt = f"""Estimate the nutrition for {weight_g}g of "{name}".
If this is a home-style Indian dish, estimate accordingly, including
typical cooking oil or ghee.

Return JSON only, no extra text, in this exact format:
{{"calories": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0, "fiber_g": 0,
  "iron_mg": 0, "calcium_mg": 0, "vitamin_a_mcg": 0, "vitamin_c_mg": 0}}"""

    try:
        data = call_with_retry(
            lambda: json.loads(
                client.models.generate_content(
                    model=MODEL_NAME,
                    contents=[prompt],
                    config=types.GenerateContentConfig(response_mime_type="application/json"),
                ).text
            ),
            max_attempts=3,  # shorter than the main call, this is already a fallback
            label="Gemini (nutrition estimate)",
        )
        # Make sure every expected key is present, even if Gemini misses one
        return {key: data.get(key, 0) for key in NUTRIENT_KEYS}
    except Exception:
        # If even the fallback fails, this is the only case that stays at 0
        return {key: 0 for key in NUTRIENT_KEYS}


# --- Step 2 and 3: Look up each food and calculate real nutrients ----------

# A basic set of "how much of this nutrient a meal should reasonably have"
# This is a simplified check, not exact medical guidance.
LOW_MEAL_THRESHOLDS = {
    "protein_g": 15,
    "fiber_g": 4,
    "iron_mg": 2,
    "calcium_mg": 100,
    "vitamin_a_mcg": 100,
    "vitamin_c_mg": 15,
}

NUTRIENT_LABELS = {
    "protein_g": "Protein",
    "fiber_g": "Fiber",
    "iron_mg": "Iron",
    "calcium_mg": "Calcium",
    "vitamin_a_mcg": "Vitamin A",
    "vitamin_c_mg": "Vitamin C",
}


def _build_items(detected_items: list[dict]) -> tuple[list[MealItem], list[str]]:
    """
    Matches each detected food to the database and calculates its nutrients.
    Returns the list of MealItem objects, and a list of names that had no match.
    """
    meal_items = []
    unmatched = []

    for item in detected_items:
        search_term = item["search_term"]
        weight_g = item["weight_g"]
        confidence = item["confidence"]

        food = search_food(search_term)

        if food is None:
            # No match in our database — fall back to a Gemini estimate,
            # so the user sees a reasonable number instead of 0 kcal.
            # This is still flagged for review because it's not verified
            # against our nutrition table.
            estimated = estimate_nutrients_with_gemini(search_term, weight_g)
            meal_items.append(MealItem(
                name=search_term,
                food_id=None,
                weight_g=weight_g,
                nutrients=NutrientTotals(**estimated),
                confidence="low",  # downgraded: this number is an AI estimate, not verified
                needs_review=True,
                user_corrected=False,
            ))
            unmatched.append(search_term)
        else:
            nutrients = calculate_nutrients(food, weight_g)
            meal_items.append(MealItem(
                name=food["name"],
                food_id=food["id"],
                weight_g=weight_g,
                nutrients=NutrientTotals(**nutrients),
                confidence=confidence,
                needs_review=(confidence == "low" or is_weak_match(food)),
                user_corrected=False,
            ))

    return meal_items, unmatched


# --- Step 4: Check which nutrients are low for this meal -------------------

def _find_missing_nutrients(total: dict) -> list[str]:
    missing = []
    for key, threshold in LOW_MEAL_THRESHOLDS.items():
        if total[key] < threshold:
            missing.append(NUTRIENT_LABELS[key])
    return missing


# --- Step 5: Ask Gemini for short suggestions (text only, fast) ------------

def _get_suggestions(total: dict, missing_nutrients: list[str]) -> list[str]:
    if not missing_nutrients:
        return ["This meal looks well balanced."]

    prompt = f"""A meal has these totals: {total}.
It is low in: {', '.join(missing_nutrients)}.

Give 1 to 2 short, practical suggestions for what to add to this meal or
the next one. Each suggestion MUST name specific vegetables, fruits, or
common foods (for example "add orange or amla for vitamin C", not just
"add foods rich in vitamin C"). Prefer foods commonly available in Indian
kitchens. No medical advice, just food ideas.

Return JSON only: {{"suggestions": ["", ""]}}"""

    try:
        data = call_with_retry(
            lambda: json.loads(
                client.models.generate_content(
                    model=MODEL_NAME,
                    contents=[prompt],
                    config=types.GenerateContentConfig(response_mime_type="application/json"),
                ).text
            ),
            max_attempts=3,
            label="Gemini (suggestions)",
        )
        return data["suggestions"]
    except Exception:
        # If this fails for any reason, fall back to a simple food-name lookup
        # instead of a vague message
        fallback_foods = {
            "Protein": "dal, eggs, or paneer",
            "Fiber": "salad, spinach, or whole fruits like guava",
            "Iron": "spinach, chana, or jaggery",
            "Calcium": "curd, milk, or paneer",
            "Vitamin A": "carrot, spinach, or mango",
            "Vitamin C": "orange, lemon, amla, or tomato",
        }
        return [
            f"Add {fallback_foods.get(nutrient, 'a variety of vegetables and fruits')} for {nutrient}."
            for nutrient in missing_nutrients
        ]


# --- The main function ------------------------------------------------------

def analyze_meal(image_bytes: bytes, mime_type: str, member=None) -> MealAnalysis:
    """
    The main function. Call this with the photo bytes and its MIME type.
    'member' (the FamilyMember) is accepted for future use (e.g. allergy
    filtering) but not required yet.
    """
    detected_items = _call_gemini_vision(image_bytes, mime_type)

    print("\n--- What Gemini detected (before database matching) ---")
    for d in detected_items:
        print(f"  {d['search_term']} ({d['weight_g']}g, {d['confidence']} confidence)")

    meal_items, unmatched = _build_items(detected_items)

    total_dict = add_totals([item.nutrients.model_dump() for item in meal_items])
    total = NutrientTotals(**total_dict)

    missing = _find_missing_nutrients(total_dict)
    suggestions = _get_suggestions(total_dict, missing)

    return MealAnalysis(
        items=meal_items,
        total=total,
        missing_nutrients=missing,
        suggestions=suggestions,
        unmatched_items=unmatched,
    )


# --- Quick test you can run directly ----------------------------------------
# python meal_analyzer.py

if __name__ == "__main__":
    import os
    image_name = input("Image file name (e.g. meal.jpg): ").strip().strip('"')
    image_path = os.path.join("images", image_name)
    with open(image_path, "rb") as f:
        image_bytes = f.read()

    result = analyze_meal(image_bytes, "image/jpeg")

    print("\n--- Items ---")
    for item in result.items:
        flag = " [NEEDS REVIEW]" if item.needs_review else ""
        print(f"{item.name} ({item.weight_g}g): {item.nutrients.calories} kcal{flag}")

    print("\n--- Total ---")
    print(result.total.model_dump())

    print("\n--- Missing nutrients ---")
    print(result.missing_nutrients)

    print("\n--- Suggestions ---")
    for s in result.suggestions:
        print("-", s)

    if result.unmatched_items:
        print("\n--- Not found in database ---")
        print(result.unmatched_items)