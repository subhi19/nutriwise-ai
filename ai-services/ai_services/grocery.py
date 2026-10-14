"""
grocery.py

generate_grocery_list() builds the shopping list, using BOTH approaches:

  1. RAG FIRST (no Gemini call): for any ingredient that's in our nutrition
     table, get its category and quantity straight from the database.
     This is fast, free (no quota used), and the numbers are trustworthy.

  2. GEMINI AS FALLBACK: for anything NOT in our database, ask Gemini to
     guess a reasonable category and quantity, so the item still shows up
     usefully in the list instead of just "Other / as needed". This uses
     a small amount of quota, only for the items that need it.

Steps:
  1. Combine all 7 days' ingredients from the meal plan into one list.
  2. Remove anything already in the fridge inventory (if a photo was
     uploaded). If no photo was uploaded, nothing gets removed — the
     user needs to buy everything the plan calls for.
  3. Add anything the user typed in themselves.
  4. Look up each item in the nutrition table (RAG). If found, use its
     real category and estimate a quantity from it. If NOT found, ask
     Gemini for a best-guess category and quantity (fallback).
  5. Anything that used the Gemini fallback is also listed in
     not_in_database, so your team knows which foods to add next.
"""

import json
from collections import Counter
from google.genai import types

try:
    from nutrition_repo import search_food
except ImportError:
    from ai_services.nutrition_repo import search_food
from .meal_plan import get_full_week_ingredients
from .gemini_client import client, MODEL_NAME
from .retry_utils import call_with_retry
from .schemas import FamilyMember, WeeklyPlan, FridgeInventory, GroceryItem, GroceryList

# Keep this in sync with the "category" values actually used in your
# nutrition CSV / Supabase table, so Gemini's guesses stay consistent
# with your real data.
GROCERY_CATEGORIES = [
    "Grains", "Legumes", "Non-veg", "Dairy", "Fats", "Vegetables",
    "Condiments", "Snacks", "Sweets", "Fruits", "Nuts", "Beverages", "Other",
]


def _normalize_name(name: str) -> str:
    return name.strip().lower()


def _already_have(ingredient: str, inventory: FridgeInventory | None) -> bool:
    """Checks if this ingredient is already in the fridge inventory.
    No inventory at all (user skipped the photo) means nothing is excluded."""
    if not inventory:
        return False
    target = _normalize_name(ingredient)
    for item in inventory.items:
        have = _normalize_name(item.name)
        if target in have or have in target:  # loose match, e.g. "onion" vs "sliced onion"
            return True
    return False


def _format_quantity(food: dict | None, times_used: int) -> str:
    """
    food: the matched row from the nutrition table, or None if not found.
    times_used: how many times this ingredient appears across the week's plan
                (e.g. onion used in 4 different meals this week).
    """
    if food and food.get("typical_serving_g"):
        total_g = food["typical_serving_g"] * times_used
        if total_g >= 1000:
            return f"{total_g / 1000:.1f} kg"
        return f"{total_g:.0f} g"
    return "as needed"  # no serving size on file, so we can't estimate an amount


def _estimate_with_gemini(name: str, times_used: int) -> dict:
    """
    FALLBACK — only called when an ingredient is NOT in our nutrition
    database. Asks Gemini to guess a reasonable category and quantity,
    so the item is still useful in the list instead of blank/generic.
    """
    prompt = f"""A grocery item called "{name}" is needed for a weekly meal
plan (used {times_used} time(s) this week), but it isn't in our food
database yet.

Pick the single best matching category from this exact list: {', '.join(GROCERY_CATEGORIES)}
Also suggest a reasonable quantity to buy for the week (e.g. "500 g", "1 bunch", "2 pieces").

Return JSON only: {{"category": "", "quantity": ""}}"""

    try:
        data = call_with_retry(
            lambda: json.loads(
                client.models.generate_content(
                    model=MODEL_NAME,
                    contents=[prompt],
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json"),
                ).text
            ),
            max_attempts=3,  # shorter than the main calls, this is already a fallback
            label="Gemini (grocery item estimate)",
        )
        category = data.get("category", "Other")
        if category not in GROCERY_CATEGORIES:
            category = "Other"
        return {"category": category, "quantity": data.get("quantity", "as needed")}
    except Exception:
        # If even the fallback fails, use safe generic defaults
        return {"category": "Other", "quantity": "as needed"}


def generate_grocery_list(
    family: list[FamilyMember],
    plan: WeeklyPlan,
    inventory: FridgeInventory | None = None,
    user_requirements: list[str] | None = None,
) -> GroceryList:
    user_requirements = user_requirements or []

    # Step 1: gather everything the week's meals need, counting how many
    # times each ingredient is used (so quantities can scale accordingly)
    all_mentions = []
    for day in plan.days:
        all_mentions.extend(day.ingredients)

    counts = Counter(_normalize_name(i) for i in all_mentions)
    display_name = {}
    for i in all_mentions:
        # keep one nicely-cased name per item
        display_name.setdefault(_normalize_name(i), i)

    # Step 2: drop anything already in the fridge
    needed = [
        display_name[key] for key in counts
        if not _already_have(display_name[key], inventory)
    ]

    items = []
    not_in_database = []

    for ingredient in needed:
        food = search_food(ingredient)
        times_used = counts[_normalize_name(ingredient)]

        if food:
            # RAG path: real data, no Gemini call
            items.append(GroceryItem(
                name=food["name"],
                food_id=food["id"],
                quantity=_format_quantity(food, times_used),
                category=food.get("category", "Other"),
                source="missing_ingredient",
            ))
        else:
            # Gemini fallback path: not in our database
            guess = _estimate_with_gemini(ingredient, times_used)
            items.append(GroceryItem(
                name=ingredient, food_id=None, quantity=guess["quantity"],
                category=guess["category"], source="missing_ingredient",
            ))
            not_in_database.append(ingredient)

    # Step 3: anything the user added manually
    for extra in user_requirements:
        food = search_food(extra)
        if food:
            items.append(GroceryItem(
                name=food["name"], food_id=food["id"], quantity="as needed",
                category=food.get("category", "Other"), source="user_added",
            ))
        else:
            guess = _estimate_with_gemini(extra, times_used=1)
            items.append(GroceryItem(
                name=extra, food_id=None, quantity=guess["quantity"],
                category=guess["category"], source="user_added",
            ))
            not_in_database.append(extra)

    return GroceryList(items=items, not_in_database=not_in_database)


# --- Quick test you can run directly ----------------------------------------
# python grocery.py

if __name__ == "__main__":
    from meal_plan import generate_meal_plan
    from schemas import InventoryItem

    fake_family = [
        FamilyMember(
            name="Test User", age=35, gender="female",
            allergies=["peanut"],
            food_preferences=["vegetarian"],
            cuisine_preferences=["indian"],
        )
    ]

    # --- Case A: user skipped the photo (inventory = None) ------------------
    print("=== CASE A: No photo uploaded — buy everything the plan needs ===")
    plan_a = generate_meal_plan(fake_family, inventory=None)
    grocery_a = generate_grocery_list(fake_family, plan_a, inventory=None)
    print(f"Items to buy: {len(grocery_a.items)}")
    for item in grocery_a.items[:8]:  # just show a few
        print(f"  [{item.category}] {item.name} — {item.quantity}")
    if grocery_a.not_in_database:
        print("Not in our database yet:", grocery_a.not_in_database)

    # --- Case B: user uploaded a photo — exclude what they already have ----
    print("\n\n=== CASE B: Photo uploaded — exclude items already at home ===")
    fake_inventory = FridgeInventory(items=[
        InventoryItem(name="Onion", use_soon=False),
        InventoryItem(name="Tomatoes", use_soon=False),
        InventoryItem(name="Yellow dal", use_soon=True,
                      expiry_estimate="Use within 3 days"),
    ])
    plan_b = generate_meal_plan(fake_family, inventory=fake_inventory)
    grocery_b = generate_grocery_list(
        fake_family, plan_b, inventory=fake_inventory,
        # not in our DB -> Gemini fallback guesses category/quantity
        user_requirements=["Almond flour"],
    )
    print(
        f"Items to buy: {len(grocery_b.items)} (onion, tomatoes, and dal should be MISSING from this list)")
    for item in grocery_b.items:
        print(f"  [{item.category}] {item.name} — {item.quantity} ({item.source})")
    if grocery_b.not_in_database:
        print("Used Gemini fallback for (not in our database yet):",
              grocery_b.not_in_database)
