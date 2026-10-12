"""
recipes.py

suggest_recipes() is what runs behind the Fridge Analyzer tab's
"Suggest Meal Plan" button. It takes the confirmed fridge inventory and:

  1. Asks Gemini for recipes using ONLY those ingredients (plus common
     pantry staples like salt/oil/spices, which don't need tracking).
  2. Calculates REAL nutrients for each recipe, using the same
     database-first approach as meal_analyzer.py and meal_plan.py:
     Gemini names the ingredient + weight, the database supplies the
     real numbers, and only ingredients missing from the database fall
     back to a Gemini estimate.

This is different from generate_meal_plan() in two ways:
  - It must use ONLY the fridge's ingredients (not freely add extras)
  - It's a single result (one or a few recipe cards), not a 7-day plan
"""

import json
from google.genai import types

from gemini_client import client, MODEL_NAME
from retry_utils import call_with_retry
from nutrition_repo import search_food
from calculator import calculate_nutrients, add_totals
# same fallback used everywhere else
from meal_analyzer import estimate_nutrients_with_gemini
from schemas import (
    FridgeInventory, RecipeSuggestions, Recipe, FamilyMember,
    MealIngredient, NutrientTotals,
)


def suggest_recipes(
    inventory: FridgeInventory,
    family: list[FamilyMember],
    avoid_dishes: list[str] | None = None,
) -> RecipeSuggestions:
    """
    avoid_dishes: recipe names the user just rejected ("suggest another").
    Pass them back in so the new suggestions are different. None for a
    first-time request.
    """
    # Separate the "use soon" items so we can ask Gemini to prioritize them
    expiring = [item.name for item in inventory.items if item.use_soon]
    all_items = [item.name for item in inventory.items]

    all_allergies = set()
    all_preferences = set()
    for member in family:
        all_allergies.update(member.allergies)
        # free-text allergies, treated the same as the fixed list
        all_allergies.update(member.anyother_specific_allergy)
        all_preferences.update(member.food_preferences)

    avoid_text = ""
    if avoid_dishes:
        avoid_text = (
            "The user did NOT like these recipes, so do NOT suggest them again — "
            f"give clearly different ones: {', '.join(avoid_dishes)}.\n\n"
        )

    prompt = f"""You are a kitchen assistant. Here is what's in the fridge:
{', '.join(all_items)}

These items are close to spoiling and should be prioritized: {', '.join(expiring) or 'none'}

Family restrictions — avoid these allergens completely: {', '.join(all_allergies) or 'none'}
Food preferences to respect: {', '.join(all_preferences) or 'none'}

{avoid_text}Suggest 3 simple recipes using ONLY the ingredients listed above. Do NOT
require any ingredient that is not in that list, EXCEPT common pantry
staples (salt, oil, basic spices, water) which can be assumed available —
list those separately as "pantry_staples", not as tracked ingredients.

For each tracked ingredient (from the fridge list) used in a recipe, give
an estimated weight in grams for that recipe — this is needed to calculate
real nutrition, so always include weight_g. Do NOT estimate calories or
nutrients yourself.

Return JSON only, no extra text, in this format:
{{
  "recipes": [
    {{
      "name": "",
      "ingredients": [{{"name": "", "weight_g": 0}}],
      "pantry_staples": [],
      "steps": []
    }}
  ]
}}"""

    def make_request():
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=[prompt],
            config=types.GenerateContentConfig(
                response_mime_type="application/json"),
        )
        return json.loads(response.text)

    data = call_with_retry(make_request, label="Gemini (recipes)")

    recipes = []
    for raw in data["recipes"]:
        ingredients = []
        unmatched = []

        for raw_ing in raw["ingredients"]:
            name = raw_ing["name"]
            weight_g = raw_ing["weight_g"]
            food = search_food(name)

            if food:
                nutrients = calculate_nutrients(food, weight_g)
                ingredients.append(MealIngredient(
                    name=food["name"], food_id=food["id"], weight_g=weight_g,
                    nutrients=NutrientTotals(**nutrients),
                ))
            else:
                estimated = estimate_nutrients_with_gemini(name, weight_g)
                ingredients.append(MealIngredient(
                    name=name, food_id=None, weight_g=weight_g,
                    nutrients=NutrientTotals(**estimated),
                ))
                unmatched.append(name)

        totals = add_totals([ing.nutrients.model_dump()
                            for ing in ingredients])

        recipes.append(Recipe(
            name=raw["name"],
            ingredients=ingredients,
            pantry_staples=raw.get("pantry_staples", []),
            steps=raw["steps"],
            total_nutrients=NutrientTotals(**totals),
            unmatched_ingredients=unmatched,
        ))

    return RecipeSuggestions(recipes=recipes)


# --- Quick test you can run directly ----------------------------------------
# python recipes.py

if __name__ == "__main__":
    from schemas import InventoryItem

    fake_inventory = FridgeInventory(items=[
        InventoryItem(name="Tomatoes", quantity="4", use_soon=False),
        InventoryItem(name="Spinach", quantity="1 bunch",
                      use_soon=True, expiry_estimate="Use within 2 days"),
        InventoryItem(name="Eggs", quantity="6", use_soon=False),
        InventoryItem(name="Paneer", quantity="200g", use_soon=False),
    ])

    fake_family = [
        FamilyMember(name="Test User", age=30, gender="female",
                     food_preferences=["vegetarian"])
    ]

    result = suggest_recipes(fake_inventory, fake_family)

    print("--- Suggested recipes (fridge-only, with real nutrients) ---")
    for recipe in result.recipes:
        print(f"\n{recipe.name}  —  total: {recipe.total_nutrients.calories} kcal, "
              f"protein: {recipe.total_nutrients.protein_g}g")
        for ing in recipe.ingredients:
            print(
                f"  - {ing.name}: {ing.weight_g}g, {ing.nutrients.calories} kcal")
        if recipe.pantry_staples:
            print(f"  Pantry staples: {', '.join(recipe.pantry_staples)}")
        if recipe.unmatched_ingredients:
            print(
                f"  (used Gemini fallback for: {', '.join(recipe.unmatched_ingredients)})")
        for i, step in enumerate(recipe.steps, 1):
            print(f"  {i}. {step}")
