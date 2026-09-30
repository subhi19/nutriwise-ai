"""
recipes.py

suggest_recipes() takes the fridge inventory (from fridge_analyzer.py) and
the family's preferences, and generates recipe ideas — prioritizing
ingredients that are about to expire, so nothing goes to waste.

No image involved here, no database lookup either — this is a single
Gemini Flash text call. The fridge inventory already has everything
needed as input.
"""

import json
from google.genai import types

from meal_analyzer import client, MODEL_NAME
from retry_utils import call_with_retry
from schemas import FridgeInventory, RecipeSuggestions, Recipe, FamilyMember


def suggest_recipes(inventory: FridgeInventory, family: list[FamilyMember]) -> RecipeSuggestions:
    # Separate the "use soon" items so we can ask Gemini to prioritize them
    expiring = [item.name for item in inventory.items if item.use_soon]
    all_items = [item.name for item in inventory.items]

    # Collect allergies and food preferences across the whole family,
    # so a suggested recipe doesn't include something someone can't eat
    all_allergies = set()
    all_preferences = set()
    for member in family:
        all_allergies.update(member.allergies)
        all_preferences.update(member.food_preferences)

    prompt = f"""You are a kitchen assistant. Here is what's in the fridge:
{', '.join(all_items)}

These items are close to spoiling and should be prioritized: {', '.join(expiring) or 'none'}

Family restrictions — avoid these allergens completely: {', '.join(all_allergies) or 'none'}
Food preferences to respect: {', '.join(all_preferences) or 'none'}

Suggest 3 simple recipes that use these ingredients, prioritizing the
items close to spoiling. Prefer recipes using mostly what's already
available; a few common pantry staples (salt, oil, spices) are fine to
assume. Give short, clear steps.

Return JSON only, no extra text, in this format:
{{
  "recipes": [
    {{
      "name": "",
      "ingredients_from_fridge": [],
      "extra_ingredients": [],
      "steps": []
    }}
  ]
}}"""

    def make_request():
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=[prompt],
            config=types.GenerateContentConfig(response_mime_type="application/json"),
        )
        return json.loads(response.text)

    data = call_with_retry(make_request, label="Gemini (recipes)")
    recipes = [Recipe(**r) for r in data["recipes"]]
    return RecipeSuggestions(recipes=recipes)


# --- Quick test you can run directly ----------------------------------------
# python recipes.py

if __name__ == "__main__":
    from schemas import InventoryItem

    # A fake fridge inventory, so you don't need to run fridge_analyzer.py
    # first just to test this
    fake_inventory = FridgeInventory(items=[
        InventoryItem(name="Tomatoes", quantity="4", use_soon=False),
        InventoryItem(name="Spinach", quantity="1 bunch", use_soon=True, expiry_estimate="Use within 2 days"),
        InventoryItem(name="Eggs", quantity="6", use_soon=False),
        InventoryItem(name="Milk", quantity="half full", use_soon=True, expiry_estimate="Use within 3 days"),
        InventoryItem(name="Carrots", quantity="5", use_soon=False),
    ])

    fake_family = [
        FamilyMember(name="Test User", age=30, gender="female", allergies=[], food_preferences=["vegetarian"])
    ]

    result = suggest_recipes(fake_inventory, fake_family)

    print("--- Suggested recipes ---")
    for recipe in result.recipes:
        print(f"\n{recipe.name}")
        print("  Uses from fridge:", ", ".join(recipe.ingredients_from_fridge))
        if recipe.extra_ingredients:
            print("  Also needs:", ", ".join(recipe.extra_ingredients))
        for i, step in enumerate(recipe.steps, 1):
            print(f"  {i}. {step}")