"""
meal_plan.py

generate_meal_plan() builds a 7-day meal plan for the family, WITH REAL
CALCULATED NUTRIENTS per meal and per day (not just ingredient names).

How the nutrients get calculated (same pattern as meal_analyzer.py):
  1. Gemini names each dish's ingredients AND estimates a weight in grams
     for each one — it does NOT estimate calories or nutrients itself.
  2. For each ingredient, we look it up in the Supabase nutrition table.
     Found?  -> real numbers, scaled to that weight.
     Not found? -> a Gemini text estimate, as a fallback (flagged).
  3. We add up the ingredients to get each meal's total, then add up the
     meals to get each day's total.

Two ways it's called:
  1. From the Weekly Planner tab: inventory=None, plan is based only on
     the family's profile (allergies, preferences, cuisines).
  2. From the Fridge screen: inventory is the user-confirmed (and maybe
     user-edited) FridgeInventory. The plan then prioritizes using up
     items marked use_soon, and says so in that day's notes.

Either way, day_preferences lets the user request something specific
for individual days (meal type, cuisine, or free text) — these apply
only to that day, on top of the general preferences.
"""

import json
from google.genai import types

from gemini_client import client, MODEL_NAME
from retry_utils import call_with_retry
from nutrition_repo import search_food
from calculator import calculate_nutrients, add_totals
# reused fallback, same as meal_analyzer.py
from meal_analyzer import estimate_nutrients_with_gemini
from schemas import (
    FamilyMember, FridgeInventory, WeeklyPlan, DayPlan, PlannedMeal,
    MealIngredient, NutrientTotals, DayPreference,
)

DAYS = ["Monday", "Tuesday", "Wednesday",
        "Thursday", "Friday", "Saturday", "Sunday"]

# The frontend's 11 meal type dropdown options (IATA-style special meal
# codes). DayPreference.meal_type receives the short CODE (e.g. "VJML").
# Gemini doesn't know what "VJML" means, so we translate it into a clear
# instruction before it goes into the prompt.
MEAL_TYPE_INFO = {
    "MOML": ("Muslim Meal", "Halal — no pork, no alcohol"),
    "HNML": ("Hindu Non-Vegetarian Meal", "Indian-style, no beef or pork"),
    "VJML": ("Vegetarian Jain Meal", "Strictly plant-based, and NO root vegetables at all (no onion, garlic, potato, carrot, radish)"),
    "VLML": ("Vegetarian Lacto-Ovo Meal", "Vegetarian, may include eggs and dairy"),
    "VGML": ("Vegan Meal", "Fully plant-based — no meat, dairy, eggs, or honey"),
    "KSML": ("Kosher Meal", "Prepared to Jewish dietary laws"),
    "FPML": ("Fruit Platter Meal", "Fresh seasonal fruit only, no cooked dishes"),
    "SFML": ("Seafood Meal", "Seafood-based dishes throughout"),
    "AVML": ("Asian Vegetarian Meal", "Indian-style vegetarian"),
    "RVML": ("Raw Vegetarian Meal", "Uncooked plant-based ingredients only"),
    "VOML": ("Vegetarian Oriental Meal", "Asian-style vegetarian"),
}


def _summarize_family(family: list[FamilyMember]) -> dict:
    """Combines the whole family's restrictions into one summary, so the
    plan is safe for everyone, not just one member."""
    allergies = set()
    preferences = set()
    cuisines = set()

    for member in family:
        allergies.update(member.allergies)
        # free-text allergies, treated the same as the fixed list
        allergies.update(member.anyother_specific_allergy)
        preferences.update(member.food_preferences)
        cuisines.update(member.cuisine_preferences)

    return {
        "allergies": sorted(allergies),
        "preferences": sorted(preferences),
        "cuisines": sorted(cuisines),  # empty = any cuisine, per the contract
    }


def _format_day_preference(dp: DayPreference) -> str:
    """Combines whichever fields are set into one readable line for the prompt."""
    parts = []
    if dp.meal_type:
        info = MEAL_TYPE_INFO.get(dp.meal_type.upper())
        if info:
            name, rule = info
            parts.append(f"meal type: {name} — STRICTLY: {rule}")
        else:
            # Unknown code — pass it through as-is rather than failing
            parts.append(f"meal type: {dp.meal_type}")
    if dp.cuisine:
        parts.append(f"cuisine: {dp.cuisine}")
    if dp.preference:
        parts.append(dp.preference)
    return ", ".join(parts) if parts else "no specific request"


def _build_prompt(
    summary: dict,
    inventory: FridgeInventory | None,
    day_preferences: list[DayPreference] | None,
    avoid_dishes: list[str] | None = None,
) -> str:
    lines = [
        "You are a meal planning assistant. Create a 7-day meal plan",
        "(Monday to Sunday), each with breakfast, lunch, dinner, and an",
        "optional snack.",
        "",
        f"Allergies to strictly avoid: {', '.join(summary['allergies']) or 'none'}",
        f"General food preferences (apply unless a day below overrides it): {', '.join(summary['preferences']) or 'none'}",
    ]

    if summary["cuisines"]:
        lines.append(f"Preferred cuisines: {', '.join(summary['cuisines'])}")
    else:
        lines.append("No specific cuisine preference — any cuisine is fine.")

    if inventory and inventory.items:
        item_names = [item.name for item in inventory.items]
        use_soon_names = [
            item.name for item in inventory.items if item.use_soon]
        lines.append("")
        lines.append(
            f"Ingredients already available at home: {', '.join(item_names)}")
        if use_soon_names:
            lines.append(
                f"IMPORTANT: these are close to spoiling and should be used in the "
                f"FIRST 2-3 days of the plan: {', '.join(use_soon_names)}. "
                f"Mention this in that day's notes, e.g. 'Uses spinach before it spoils.'"
            )
        lines.append(
            "You may add other common ingredients beyond this list if needed to "
            "complete a sensible meal — this list is a hint, not a hard limit."
        )

    if day_preferences:
        lines.append("")
        lines.append(
            "The user has specific requests for certain days. These OVERRIDE or "
            "ADD TO the general preferences above, but ONLY for that specific day "
            "— every other day still follows the general preferences:"
        )
        for dp in day_preferences:
            lines.append(f"  {dp.day}: {_format_day_preference(dp)}")

    if avoid_dishes:
        lines.append("")
        lines.append(
            "The user already saw a plan and did NOT like it. Do NOT use any of these "
            "dishes again — suggest clearly different dishes instead: "
            f"{', '.join(avoid_dishes)}."
        )

    lines.append("")
    lines.append(
        "For EACH meal (breakfast, lunch, dinner, and snack if included), list its "
        "ingredients with an estimated weight in grams for each one — this is "
        "needed to calculate real nutrition, so always include weight_g. Do NOT "
        "estimate calories or nutrients yourself. Add a short 'notes' field per "
        "day only when there's something worth mentioning (e.g. using up an "
        "ingredient soon, or honoring a specific day request)."
    )
    lines.append("")
    lines.append("Return JSON only, no extra text, in this format:")
    lines.append("""{
  "days": [
    {
      "day": "Monday",
      "breakfast": {"name": "", "ingredients": [{"name": "", "weight_g": 0}], "notes": null},
      "lunch": {"name": "", "ingredients": [{"name": "", "weight_g": 0}], "notes": null},
      "dinner": {"name": "", "ingredients": [{"name": "", "weight_g": 0}], "notes": null},
      "snack": null
    }
  ],
  "notes": []
}""")

    return "\n".join(lines)


def _resolve_ingredients(raw_ingredients: list[dict]) -> tuple[list[MealIngredient], list[str]]:
    """
    Takes Gemini's raw ingredient list (just names + weights) and turns it
    into real MealIngredient objects with calculated nutrition — exactly
    the same database-first approach as meal_analyzer.py.

    Returns (ingredients, unmatched_names).
    """
    ingredients = []
    unmatched = []

    for raw in raw_ingredients:
        name = raw["name"]
        weight_g = raw["weight_g"]
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

    return ingredients, unmatched


def _build_meal(raw_meal: dict) -> tuple[PlannedMeal, list[str]]:
    """Builds one PlannedMeal (breakfast/lunch/dinner/snack) with its total nutrients."""
    ingredients, unmatched = _resolve_ingredients(raw_meal["ingredients"])
    totals = add_totals([ing.nutrients.model_dump() for ing in ingredients])

    meal = PlannedMeal(
        name=raw_meal["name"],
        ingredients=ingredients,
        notes=raw_meal.get("notes"),
        nutrients=NutrientTotals(**totals),
    )
    return meal, unmatched


def _combine_names(meals: list[PlannedMeal]) -> list[str]:
    """Combines ingredient names across a day's meals, removing duplicates."""
    seen = set()
    combined = []
    for meal in meals:
        for ing in meal.ingredients:
            key = ing.name.strip().lower()
            if key not in seen:
                seen.add(key)
                combined.append(ing.name.strip())
    return combined


def _basic_allergy_check(plan: WeeklyPlan, allergies: list[str]) -> list[str]:
    """
    A simple safety net: scans every ingredient in the plan for allergen
    keywords that may have slipped through despite the prompt. Doesn't
    remove anything automatically (that could break a dish), but flags
    it clearly so it's never silently missed.
    """
    warnings = []
    if not allergies:
        return warnings

    for day in plan.days:
        for item in day.ingredients:
            for allergen in allergies:
                if allergen.lower() in item.lower():
                    warnings.append(
                        f"{day.day}: '{item}' may contain '{allergen}' — please check."
                    )
    return warnings


def get_full_week_ingredients(plan: WeeklyPlan) -> list[str]:
    """
    Combines every day's ingredient list into one list for the whole week,
    with duplicates removed. Unchanged by the nutrient update — still reads
    plan.days[*].ingredients, which stays a plain list of names.

    This does NOT call Gemini — the ingredients are already sitting inside
    the WeeklyPlan you already generated.
    """
    seen = set()
    combined = []

    for day in plan.days:
        for ingredient in day.ingredients:
            key = ingredient.strip().lower()
            if key not in seen:
                seen.add(key)
                combined.append(ingredient.strip())

    return sorted(combined)


def generate_meal_plan(
    family: list[FamilyMember],
    inventory: FridgeInventory | None = None,
    day_preferences: list[DayPreference] | None = None,
    avoid_dishes: list[str] | None = None,
) -> WeeklyPlan:
    """
    avoid_dishes: dish names from a plan the user just rejected ("Create new
    plan"). Pass them back in so the new plan uses different dishes. Leave
    as None for a first-time plan.
    """
    summary = _summarize_family(family)
    prompt = _build_prompt(summary, inventory, day_preferences, avoid_dishes)

    def make_request():
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=[prompt],
            config=types.GenerateContentConfig(
                response_mime_type="application/json"),
        )
        return json.loads(response.text)

    data = call_with_retry(make_request, label="Gemini (meal plan)")

    days = []
    for d in data["days"]:
        breakfast, un1 = _build_meal(d["breakfast"])
        lunch, un2 = _build_meal(d["lunch"])
        dinner, un3 = _build_meal(d["dinner"])
        snack, un4 = (_build_meal(d["snack"])
                      if d.get("snack") else (None, []))

        meals = [m for m in [breakfast, lunch, dinner, snack] if m]
        day_totals = add_totals([m.nutrients.model_dump() for m in meals])
        day_unmatched = un1 + un2 + un3 + un4

        days.append(DayPlan(
            day=d["day"],
            breakfast=breakfast,
            lunch=lunch,
            dinner=dinner,
            snack=snack,
            ingredients=_combine_names(meals),
            nutrients=NutrientTotals(**day_totals),
            unmatched_ingredients=day_unmatched,
        ))

    plan = WeeklyPlan(days=days, notes=data.get("notes", []))

    # Safety net: flag (don't silently drop) any allergen that slipped through
    allergy_warnings = _basic_allergy_check(plan, summary["allergies"])
    plan.notes.extend(allergy_warnings)

    return plan


# --- Quick test you can run directly ----------------------------------------
# python meal_plan.py

if __name__ == "__main__":
    from schemas import InventoryItem

    fake_family = [
        FamilyMember(
            name="Test User", age=35, gender="female",
            allergies=["peanut"],
            food_preferences=["vegetarian"],
            cuisine_preferences=["indian"],
        )
    ]

    print("=== Plan without inventory (Weekly Planner, no photo) ===")
    plan = generate_meal_plan(fake_family, inventory=None)
    for day in plan.days[:1]:  # just show 1 day to keep it readable
        print(f"\n{day.day}  —  total: {day.nutrients.calories} kcal")
        print(
            f"  Breakfast: {day.breakfast.name} ({day.breakfast.nutrients.calories} kcal)")
        for ing in day.breakfast.ingredients:
            print(
                f"    - {ing.name}: {ing.weight_g}g, {ing.nutrients.calories} kcal")
        print(
            f"  Lunch: {day.lunch.name} ({day.lunch.nutrients.calories} kcal)")
        print(
            f"  Dinner: {day.dinner.name} ({day.dinner.nutrients.calories} kcal)")
    print("\nPlan notes:", plan.notes)

    print("\n\n=== Plan with fridge inventory (Fridge screen) ===")
    fake_inventory = FridgeInventory(items=[
        InventoryItem(name="Spinach", use_soon=True,
                      expiry_estimate="Use within 2 days"),
        InventoryItem(name="Paneer", use_soon=False),
    ])
    plan2 = generate_meal_plan(fake_family, inventory=fake_inventory)
    day = plan2.days[0]
    print(f"\n{day.day}  —  total: {day.nutrients.calories} kcal, "
          f"protein: {day.nutrients.protein_g}g")
    print(f"  Breakfast: {day.breakfast.name}")
    print(f"  Lunch: {day.lunch.name}")
    print(f"  Dinner: {day.dinner.name}")
    print("Plan notes:", plan2.notes)
    if day.unmatched_ingredients:
        print("Ingredients that used the Gemini fallback (not in our DB):",
              day.unmatched_ingredients)

    print("\n\n=== Plan with day-specific preferences ===")
    day_prefs = [
        DayPreference(day="Friday", meal_type="Non-Vegetarian",
                      cuisine="Chinese"),
        DayPreference(day="Sunday", preference="light dinner, low oil"),
    ]
    plan3 = generate_meal_plan(
        fake_family, inventory=None, day_preferences=day_prefs)
    for day in plan3.days:
        if day.day in ("Friday", "Sunday"):
            print(f"\n{day.day}  —  total: {day.nutrients.calories} kcal")
            print(f"  Dinner: {day.dinner.name}")

    print("\n\n=== Whole week's ingredients, combined ===")
    week_list = get_full_week_ingredients(plan3)
    print(
        f"({len(week_list)} unique ingredients): {', '.join(week_list[:10])}...")
