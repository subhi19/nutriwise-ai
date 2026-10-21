# """
# meal_plan.py

# generate_meal_plan() builds a 7-day meal plan for the family, WITH REAL
# CALCULATED NUTRIENTS per meal and per day (not just ingredient names).

# How the nutrients get calculated (same pattern as meal_analyzer.py):
#   1. Gemini names each dish's ingredients AND estimates a weight in grams
#      for each one — it does NOT estimate calories or nutrients itself.
#   2. For each ingredient, we look it up in the Supabase nutrition table.
#      Found?  -> real numbers, scaled to that weight.
#      Not found? -> a Gemini text estimate, as a fallback (flagged).
#   3. We add up the ingredients to get each meal's total, then add up the
#      meals to get each day's total.

# Two ways it's called:
#   1. From the Weekly Planner tab: inventory=None, plan is based only on
#      the family's profile (allergies, preferences, cuisines).
#   2. From the Fridge screen: inventory is the user-confirmed (and maybe
#      user-edited) FridgeInventory. The plan then prioritizes using up
#      items marked use_soon, and says so in that day's notes.

# Either way, day_preferences lets the user request something specific
# for individual days (meal type, cuisine, or free text) — these apply
# only to that day, on top of the general preferences.
# """

# import json
# from google.genai import types

# from .gemini_client import client, MODEL_NAME
# from .retry_utils import call_with_retry
# from .nutrition_repo import search_food
# from .calculator import calculate_nutrients, add_totals
# # reused fallback, same as meal_analyzer.py
# from .meal_analyzer import estimate_nutrients_with_gemini
# from .schemas import (
#     FamilyMember, FridgeInventory, WeeklyPlan, DayPlan, PlannedMeal,
#     MealIngredient, NutrientTotals, DayPreference,
# )

# DAYS = ["Monday", "Tuesday", "Wednesday",
#         "Thursday", "Friday", "Saturday", "Sunday"]

# # The frontend's 11 meal type dropdown options (IATA-style special meal
# # codes). DayPreference.meal_type receives the short CODE (e.g. "VJML").
# # Gemini doesn't know what "VJML" means, so we translate it into a clear
# # instruction before it goes into the prompt.
# MEAL_TYPE_INFO = {
#     "MOML": ("Muslim Meal", "Halal — no pork, no alcohol"),
#     "HNML": ("Hindu Non-Vegetarian Meal", "Indian-style, no beef or pork"),
#     "VJML": ("Vegetarian Jain Meal", "Strictly plant-based, and NO root vegetables at all (no onion, garlic, potato, carrot, radish)"),
#     "VLML": ("Vegetarian Lacto-Ovo Meal", "Vegetarian, may include eggs and dairy"),
#     "VGML": ("Vegan Meal", "Fully plant-based — no meat, dairy, eggs, or honey"),
#     "KSML": ("Kosher Meal", "Prepared to Jewish dietary laws"),
#     "FPML": ("Fruit Platter Meal", "Fresh seasonal fruit only, no cooked dishes"),
#     "SFML": ("Seafood Meal", "Seafood-based dishes throughout"),
#     "AVML": ("Asian Vegetarian Meal", "Indian-style vegetarian"),
#     "RVML": ("Raw Vegetarian Meal", "Uncooked plant-based ingredients only"),
#     "VOML": ("Vegetarian Oriental Meal", "Asian-style vegetarian"),
# }


# def _summarize_family(family: list[FamilyMember]) -> dict:
#     """Combines the whole family's restrictions into one summary, so the
#     plan is safe for everyone, not just one member."""
#     allergies = set()
#     preferences = set()
#     cuisines = set()

#     for member in family:
#         allergies.update(member.allergies)
#         # free-text allergies, treated the same as the fixed list
#         allergies.update(member.anyother_specific_allergy)
#         preferences.update(member.food_preferences)
#         cuisines.update(member.cuisine_preferences)

#     return {
#         "allergies": sorted(allergies),
#         "preferences": sorted(preferences),
#         "cuisines": sorted(cuisines),  # empty = any cuisine, per the contract
#     }


# def _format_day_preference(dp: DayPreference) -> str:
#     """Combines whichever fields are set into one readable line for the prompt."""
#     parts = []
#     if dp.meal_type:
#         info = MEAL_TYPE_INFO.get(dp.meal_type.upper())
#         if info:
#             name, rule = info
#             parts.append(f"meal type: {name} — STRICTLY: {rule}")
#         else:
#             # Unknown code — pass it through as-is rather than failing
#             parts.append(f"meal type: {dp.meal_type}")
#     if dp.cuisine:
#         parts.append(f"cuisine: {dp.cuisine}")
#     if dp.preference:
#         parts.append(dp.preference)
#     return ", ".join(parts) if parts else "no specific request"


# def _build_prompt(
#     summary: dict,
#     inventory: FridgeInventory | None,
#     day_preferences: list[DayPreference] | None,
#     avoid_dishes: list[str] | None = None,
# ) -> str:
#     lines = [
#         "You are a meal planning assistant. Create a 7-day meal plan",
#         "(Monday to Sunday), each with breakfast, lunch, dinner, and an",
#         "optional snack.",
#         "",
#         f"Allergies to strictly avoid: {', '.join(summary['allergies']) or 'none'}",
#         f"General food preferences (apply unless a day below overrides it): {', '.join(summary['preferences']) or 'none'}",
#     ]

#     if summary["cuisines"]:
#         lines.append(f"Preferred cuisines: {', '.join(summary['cuisines'])}")
#     else:
#         lines.append("No specific cuisine preference — any cuisine is fine.")

#     if inventory and inventory.items:
#         item_names = [item.name for item in inventory.items]
#         use_soon_names = [
#             item.name for item in inventory.items if item.use_soon]
#         lines.append("")
#         lines.append(
#             f"Ingredients already available at home: {', '.join(item_names)}")
#         if use_soon_names:
#             lines.append(
#                 f"IMPORTANT: these are close to spoiling and should be used in the "
#                 f"FIRST 2-3 days of the plan: {', '.join(use_soon_names)}. "
#                 f"Mention this in that day's notes, e.g. 'Uses spinach before it spoils.'"
#             )
#         lines.append(
#             "You may add other common ingredients beyond this list if needed to "
#             "complete a sensible meal — this list is a hint, not a hard limit."
#         )

#     if day_preferences:
#         lines.append("")
#         lines.append(
#             "The user has specific requests for certain days. These OVERRIDE or "
#             "ADD TO the general preferences above, but ONLY for that specific day "
#             "— every other day still follows the general preferences:"
#         )
#         for dp in day_preferences:
#             lines.append(f"  {dp.day}: {_format_day_preference(dp)}")

#     if avoid_dishes:
#         lines.append("")
#         lines.append(
#             "The user already saw a plan and did NOT like it. Do NOT use any of these "
#             "dishes again — suggest clearly different dishes instead: "
#             f"{', '.join(avoid_dishes)}."
#         )

#     lines.append("")
#     lines.append(
#         "For EACH meal (breakfast, lunch, dinner, and snack if included), list its "
#         "ingredients with an estimated weight in grams for each one — this is "
#         "needed to calculate real nutrition, so always include weight_g. Do NOT "
#         "estimate calories or nutrients yourself. Add a short 'notes' field per "
#         "day only when there's something worth mentioning (e.g. using up an "
#         "ingredient soon, or honoring a specific day request)."
#     )
#     lines.append("")
#     lines.append("Return JSON only, no extra text, in this format:")
#     lines.append("""{
#   "days": [
#     {
#       "day": "Monday",
#       "breakfast": {"name": "", "ingredients": [{"name": "", "weight_g": 0}], "notes": null},
#       "lunch": {"name": "", "ingredients": [{"name": "", "weight_g": 0}], "notes": null},
#       "dinner": {"name": "", "ingredients": [{"name": "", "weight_g": 0}], "notes": null},
#       "snack": null
#     }
#   ],
#   "notes": []
# }""")

#     return "\n".join(lines)


# def _resolve_ingredients(raw_ingredients: list[dict]) -> tuple[list[MealIngredient], list[str]]:
#     """
#     Takes Gemini's raw ingredient list (just names + weights) and turns it
#     into real MealIngredient objects with calculated nutrition — exactly
#     the same database-first approach as meal_analyzer.py.

#     Returns (ingredients, unmatched_names).
#     """
#     ingredients = []
#     unmatched = []

#     for raw in raw_ingredients:
#         name = raw["name"]
#         weight_g = raw["weight_g"]
#         food = search_food(name)

#         if food:
#             nutrients = calculate_nutrients(food, weight_g)
#             ingredients.append(MealIngredient(
#                 name=food["name"], food_id=food["id"], weight_g=weight_g,
#                 nutrients=NutrientTotals(**nutrients),
#             ))
#         else:
#             estimated = estimate_nutrients_with_gemini(name, weight_g)
#             ingredients.append(MealIngredient(
#                 name=name, food_id=None, weight_g=weight_g,
#                 nutrients=NutrientTotals(**estimated),
#             ))
#             unmatched.append(name)

#     return ingredients, unmatched


# def _build_meal(raw_meal: dict) -> tuple[PlannedMeal, list[str]]:
#     """Builds one PlannedMeal (breakfast/lunch/dinner/snack) with its total nutrients."""
#     ingredients, unmatched = _resolve_ingredients(raw_meal["ingredients"])
#     totals = add_totals([ing.nutrients.model_dump() for ing in ingredients])

#     meal = PlannedMeal(
#         name=raw_meal["name"],
#         ingredients=ingredients,
#         notes=raw_meal.get("notes"),
#         nutrients=NutrientTotals(**totals),
#     )
#     return meal, unmatched


# def _combine_names(meals: list[PlannedMeal]) -> list[str]:
#     """Combines ingredient names across a day's meals, removing duplicates."""
#     seen = set()
#     combined = []
#     for meal in meals:
#         for ing in meal.ingredients:
#             key = ing.name.strip().lower()
#             if key not in seen:
#                 seen.add(key)
#                 combined.append(ing.name.strip())
#     return combined


# def _basic_allergy_check(plan: WeeklyPlan, allergies: list[str]) -> list[str]:
#     """
#     A simple safety net: scans every ingredient in the plan for allergen
#     keywords that may have slipped through despite the prompt. Doesn't
#     remove anything automatically (that could break a dish), but flags
#     it clearly so it's never silently missed.
#     """
#     warnings = []
#     if not allergies:
#         return warnings

#     for day in plan.days:
#         for item in day.ingredients:
#             for allergen in allergies:
#                 if allergen.lower() in item.lower():
#                     warnings.append(
#                         f"{day.day}: '{item}' may contain '{allergen}' — please check."
#                     )
#     return warnings


# def get_full_week_ingredients(plan: WeeklyPlan) -> list[str]:
#     """
#     Combines every day's ingredient list into one list for the whole week,
#     with duplicates removed. Unchanged by the nutrient update — still reads
#     plan.days[*].ingredients, which stays a plain list of names.

#     This does NOT call Gemini — the ingredients are already sitting inside
#     the WeeklyPlan you already generated.
#     """
#     seen = set()
#     combined = []

#     for day in plan.days:
#         for ingredient in day.ingredients:
#             key = ingredient.strip().lower()
#             if key not in seen:
#                 seen.add(key)
#                 combined.append(ingredient.strip())

#     return sorted(combined)


# def generate_meal_plan(
#     family: list[FamilyMember],
#     inventory: FridgeInventory | None = None,
#     day_preferences: list[DayPreference] | None = None,
#     avoid_dishes: list[str] | None = None,
# ) -> WeeklyPlan:
#     """
#     avoid_dishes: dish names from a plan the user just rejected ("Create new
#     plan"). Pass them back in so the new plan uses different dishes. Leave
#     as None for a first-time plan.
#     """
#     summary = _summarize_family(family)
#     prompt = _build_prompt(summary, inventory, day_preferences, avoid_dishes)

#     def make_request():
#         response = client.models.generate_content(
#             model=MODEL_NAME,
#             contents=[prompt],
#             config=types.GenerateContentConfig(
#                 response_mime_type="application/json"),
#         )
#         return json.loads(response.text)

#     data = call_with_retry(make_request, label="Gemini (meal plan)")

#     days = []
#     for d in data["days"]:
#         breakfast, un1 = _build_meal(d["breakfast"])
#         lunch, un2 = _build_meal(d["lunch"])
#         dinner, un3 = _build_meal(d["dinner"])
#         snack, un4 = (_build_meal(d["snack"])
#                       if d.get("snack") else (None, []))

#         meals = [m for m in [breakfast, lunch, dinner, snack] if m]
#         day_totals = add_totals([m.nutrients.model_dump() for m in meals])
#         day_unmatched = un1 + un2 + un3 + un4

#         days.append(DayPlan(
#             day=d["day"],
#             breakfast=breakfast,
#             lunch=lunch,
#             dinner=dinner,
#             snack=snack,
#             ingredients=_combine_names(meals),
#             nutrients=NutrientTotals(**day_totals),
#             unmatched_ingredients=day_unmatched,
#         ))

#     plan = WeeklyPlan(days=days, notes=data.get("notes", []))

#     # Safety net: flag (don't silently drop) any allergen that slipped through
#     allergy_warnings = _basic_allergy_check(plan, summary["allergies"])
#     plan.notes.extend(allergy_warnings)

#     return plan


# # --- Quick test you can run directly ----------------------------------------
# # python meal_plan.py

# if __name__ == "__main__":
#     from schemas import InventoryItem

#     fake_family = [
#         FamilyMember(
#             name="Test User", age=35, gender="female",
#             allergies=["peanut"],
#             food_preferences=["vegetarian"],
#             cuisine_preferences=["indian"],
#         )
#     ]

#     print("=== Plan without inventory (Weekly Planner, no photo) ===")
#     plan = generate_meal_plan(fake_family, inventory=None)
#     for day in plan.days[:1]:  # just show 1 day to keep it readable
#         print(f"\n{day.day}  —  total: {day.nutrients.calories} kcal")
#         print(
#             f"  Breakfast: {day.breakfast.name} ({day.breakfast.nutrients.calories} kcal)")
#         for ing in day.breakfast.ingredients:
#             print(
#                 f"    - {ing.name}: {ing.weight_g}g, {ing.nutrients.calories} kcal")
#         print(
#             f"  Lunch: {day.lunch.name} ({day.lunch.nutrients.calories} kcal)")
#         print(
#             f"  Dinner: {day.dinner.name} ({day.dinner.nutrients.calories} kcal)")
#     print("\nPlan notes:", plan.notes)

#     print("\n\n=== Plan with fridge inventory (Fridge screen) ===")
#     fake_inventory = FridgeInventory(items=[
#         InventoryItem(name="Spinach", use_soon=True,
#                       expiry_estimate="Use within 2 days"),
#         InventoryItem(name="Paneer", use_soon=False),
#     ])
#     plan2 = generate_meal_plan(fake_family, inventory=fake_inventory)
#     day = plan2.days[0]
#     print(f"\n{day.day}  —  total: {day.nutrients.calories} kcal, "
#           f"protein: {day.nutrients.protein_g}g")
#     print(f"  Breakfast: {day.breakfast.name}")
#     print(f"  Lunch: {day.lunch.name}")
#     print(f"  Dinner: {day.dinner.name}")
#     print("Plan notes:", plan2.notes)
#     if day.unmatched_ingredients:
#         print("Ingredients that used the Gemini fallback (not in our DB):",
#               day.unmatched_ingredients)

#     print("\n\n=== Plan with day-specific preferences ===")
#     day_prefs = [
#         DayPreference(day="Friday", meal_type="Non-Vegetarian",
#                       cuisine="Chinese"),
#         DayPreference(day="Sunday", preference="light dinner, low oil"),
#     ]
#     plan3 = generate_meal_plan(
#         fake_family, inventory=None, day_preferences=day_prefs)
#     for day in plan3.days:
#         if day.day in ("Friday", "Sunday"):
#             print(f"\n{day.day}  —  total: {day.nutrients.calories} kcal")
#             print(f"  Dinner: {day.dinner.name}")

#     print("\n\n=== Whole week's ingredients, combined ===")
#     week_list = get_full_week_ingredients(plan3)
#     print(
#         f"({len(week_list)} unique ingredients): {', '.join(week_list[:10])}...")

"""
meal_plan.py

generate_meal_plan() builds a meal plan for the family, WITH REAL
CALCULATED NUTRIENTS per meal and per day (not just ingredient names).

How the nutrients get calculated (same pattern as meal_analyzer.py):
  1. Gemini names each dish's ingredients AND estimates a weight in grams
     for each one — it does NOT estimate calories or nutrients itself.
  2. For each ingredient, we look it up in the Supabase nutrition table.
     Found?  -> real numbers, scaled to that weight.
     Not found? -> zero nutrients, and the name is listed in
                   unmatched_ingredients so it is never silently missed.
  3. We add up the ingredients to get each meal's total, then add up the
     meals to get each day's total.

Priority of preferences (highest first):
  1. Day-specific request chosen in the app (meal type / cuisine / text)
     -> applies to EVERY meal of that day only.
  2. The user's free-text message ("Ask Gemini AI" box), e.g. a cuisine.
  3. The profile (allergies, food preferences, cuisines).
  Days with no selection simply use the profile.

Scope:
  - Days named in the user's message ("plan for monday") are detected in
    code. Only those days are requested and returned.
  - No days named -> the full week (Monday-Sunday).

Fridge inventory:
  - Fridge items are used first; Gemini may add other ingredients.
  - Every ingredient carries a `from_fridge` flag, so the grocery list
    (build_grocery_list) contains ONLY the ingredients Gemini added.
"""

import json
import logging
import re
from functools import lru_cache

from google.genai import types

from .gemini_client import client, MODEL_NAME
from .retry_utils import call_with_retry
from .nutrition_repo import search_food
from .calculator import calculate_nutrients, add_totals
from .schemas import (
    FamilyMember, FridgeInventory, WeeklyPlan, DayPlan, PlannedMeal,
    MealIngredient, NutrientTotals, DayPreference,
)

logger = logging.getLogger(__name__)

# Set to False once everything works. Prints what the backend receives and
# the exact prompt sent to Gemini, so missing preferences are easy to spot.
DEBUG_PROMPT = True

DAYS = ["Monday", "Tuesday", "Wednesday",
        "Thursday", "Friday", "Saturday", "Sunday"]

MEAL_KEYS = ("breakfast", "lunch", "dinner", "snack")

# The frontend's 11 meal type dropdown options (IATA-style special meal
# codes). Gemini doesn't know what "VJML" means, so we translate it into a
# clear instruction before it goes into the prompt.
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

# label (lower-case) -> code, so "Vegetarian Lacto-Ovo Meal" also works
_LABEL_TO_CODE = {name.lower(): code for code,
                  (name, _) in MEAL_TYPE_INFO.items()}


# ---------------------------------------------------------------------------
# Family summary
# ---------------------------------------------------------------------------

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
        "cuisines": sorted(cuisines),  # empty = any cuisine
    }


# ---------------------------------------------------------------------------
# Day names, scope detection
# ---------------------------------------------------------------------------

def _canonical_day(value) -> str | None:
    """'monday', 'Mon', 'MONDAY' -> 'Monday'. Unknown -> None."""
    if not value:
        return None
    v = str(value).strip().lower()
    if len(v) < 3:
        return None
    for d in DAYS:
        if v == d.lower() or d.lower().startswith(v[:3]):
            return d
    return None


def _days_from_message(message: str | None) -> list[str]:
    """Finds the days the user named in their free-text message.
    'plan for monday' -> ['Monday'].  'weekend' -> ['Saturday', 'Sunday'].
    Empty list = the message doesn't limit the days."""
    if not message:
        return []
    text = message.lower()
    found = set()
    for d in DAYS:
        if re.search(rf"\b{d.lower()}s?\b", text):
            found.add(d)
    if re.search(r"\bweekends?\b", text):
        found.update(["Saturday", "Sunday"])
    if re.search(r"\bweekdays?\b", text):
        found.update(DAYS[:5])
    return [d for d in DAYS if d in found]


# ---------------------------------------------------------------------------
# Day-specific preferences (robust parsing)
# ---------------------------------------------------------------------------

def _first(raw: dict, *keys):
    """First non-empty value among several possible field names."""
    for k in keys:
        v = raw.get(k)
        if v:
            return v
    return None


def _resolve_meal_type(value) -> str | None:
    """Accepts a code ('VLML') or a label ('Vegetarian Lacto-Ovo Meal') and
    returns a clear instruction line for Gemini."""
    if not value:
        return None
    if isinstance(value, (list, tuple, set)):
        parts = [p for p in (_resolve_meal_type(v) for v in value) if p]
        return "; ".join(parts) or None

    v = str(value).strip()
    code = None
    if v.upper() in MEAL_TYPE_INFO:
        code = v.upper()
    elif v.lower() in _LABEL_TO_CODE:
        code = _LABEL_TO_CODE[v.lower()]
    else:
        # partial label match, e.g. "Vegetarian Lacto-Ovo"
        for label, c in _LABEL_TO_CODE.items():
            if v.lower() in label or label in v.lower():
                code = c
                break

    if code:
        name, rule = MEAL_TYPE_INFO[code]
        return f"meal type: {name} — STRICTLY: {rule}"
    # Unknown value — pass it through as-is rather than dropping it
    return f"meal type: {v}"


def _pref_text(dp: DayPreference) -> str:
    """One readable line describing what the user chose for that day.
    Empty string = nothing chosen (that day uses the profile).

    Reads several possible field names, because the frontend's names may
    differ from the schema (and Pydantic silently drops unknown fields
    unless the schema has extra='allow')."""
    raw = dp.model_dump() if hasattr(dp, "model_dump") else dict(dp)

    meal_type = _first(raw, "meal_type", "mealType",
                       "meal_type_code", "meal", "diet", "diet_type")
    cuisine = _first(raw, "cuisine", "cuisines", "cuisine_preferences")
    note = _first(raw, "preference", "preferences",
                  "note", "notes", "text", "request")

    parts = []
    mt = _resolve_meal_type(meal_type)
    if mt:
        parts.append(mt)
    if cuisine:
        if isinstance(cuisine, (list, tuple, set)):
            cuisine = ", ".join(str(c) for c in cuisine)
        parts.append(f"cuisine: {cuisine}")
    if note:
        if isinstance(note, (list, tuple, set)):
            note = ", ".join(str(n) for n in note)
        parts.append(str(note))
    return ", ".join(parts)


def _active_day_prefs(day_preferences: list[DayPreference] | None) -> list[tuple[str, str]]:
    """[(day, request_text)] for days where the user actually chose something.
    The app sends all 7 days, most of them empty — those are dropped so they
    fall back to the profile."""
    active = []
    for dp in day_preferences or []:
        day = _canonical_day(getattr(dp, "day", None))
        text = _pref_text(dp)
        if day and text:
            active.append((day, text))
    return active


# ---------------------------------------------------------------------------
# Prompt
# ---------------------------------------------------------------------------

def _build_prompt(
    summary: dict,
    inventory: FridgeInventory | None,
    day_prefs: list[tuple[str, str]],
    avoid_dishes: list[str] | None = None,
    user_message: str | None = None,
    target_days: list[str] | None = None,
) -> str:
    lines = [
        "Create a detailed family meal plan.",
        "",
        f"User request: {user_message or 'Generate a weekly meal plan (Monday to Sunday)'}",
        "",
        "SCOPE RULE (highest priority):",
    ]

    if target_days:
        lines.append(
            f"- Return ONLY these days in the \"days\" array: {', '.join(target_days)}. "
            "Do not add any other day."
        )
    else:
        lines.append(
            "- Generate all 7 days, Monday to Sunday, unless the user request "
            "clearly limits the plan."
        )
    lines.append(
        "- If the user asks for specific meals only (e.g. 'dinner'), return only "
        "those meals and set the others to null."
    )

    lines += [
        "",
        "SAFETY:",
        f"- Allergies to strictly avoid (never use these or their derivatives): "
        f"{', '.join(summary['allergies']) or 'none'}",
        "",
        "PROFILE PREFERENCES (the default for every day and meal that has no "
        "specific request):",
        f"- General food preferences: {', '.join(summary['preferences']) or 'none'}",
    ]

    # Cuisine priority: day request > user message > profile > any
    if summary["cuisines"]:
        lines.append(
            f"- Profile cuisines: {', '.join(summary['cuisines'])}. "
            "If the user request names a different cuisine, use that cuisine "
            "instead. Otherwise use the profile cuisines. A cuisine in a "
            "day-specific request beats both, for that day only."
        )
    else:
        lines.append(
            "- No profile cuisine. If the user request names a cuisine, use it; "
            "otherwise any cuisine is fine. A cuisine in a day-specific request "
            "applies to that day."
        )

    # Day-specific requests (only days where the user chose something)
    if day_prefs:
        lines.append("")
        lines.append(
            "DAY-SPECIFIC REQUESTS (chosen by the user in the app; these MUST be followed):\n"
            "- Each request applies to EVERY meal of that day (breakfast, lunch, "
            "dinner and snack), unless the request names a specific meal.\n"
            "- It overrides the profile preferences and profile cuisine for that "
            "day ONLY. Allergies still always apply.\n"
            "- Any day not listed here uses the profile preferences above."
        )
        for day, text in day_prefs:
            lines.append(f"  {day}: {text}")

    # Fridge inventory
    lines.append("")
    if inventory and inventory.items:
        item_names = [item.name for item in inventory.items]
        use_soon_names = [i.name for i in inventory.items if i.use_soon]

        lines.append(
            f"FRIDGE INVENTORY (already at home): {', '.join(item_names)}")
        lines.append(
            "- Build meals using these ingredients as much as sensible, as long as "
            "they fit the day's requirements. You may add other common "
            "ingredients to complete a proper dish."
        )
        if use_soon_names:
            lines.append(
                f"- IMPORTANT: these are close to spoiling, so use them in the "
                f"EARLIEST days of the plan: {', '.join(use_soon_names)}. "
                "Mention it in that day's notes, e.g. 'Uses spinach before it spoils.'"
            )
        lines.append(
            "- For every ingredient, set \"from_fridge\": true if it is in the fridge "
            "list above, and false if you added it."
        )
    else:
        lines.append(
            "No fridge inventory provided. Set \"from_fridge\": false for every ingredient."
        )

    # Ingredient sanity (applies to ALL plans)
    lines.append("")
    lines.append(
        "INGREDIENT RULES:\n"
        "- Only list ingredients actually used in the recipe.\n"
        "- Every ingredient must logically belong to the dish "
        "(pancakes have no chicken, a fruit bowl contains fruit, a sandwich has bread "
        "and fillings).\n"
        "- Do not invent unrelated ingredients.\n"
        "- List each ingredient ONCE per dish. If it is used twice, add the "
        "weights together into a single line.\n"
        "- Use plain shop-bought ingredient names (e.g. 'chicken breast', "
        "'spring onion', 'egg', 'rice'), not cooked or ready-made foods like "
        "'fried chicken'. The cooking method belongs in the dish name.\n"
        "- Do not add a separate stock/broth line when the dish already "
        "simmers its main ingredient in water; use 'water' instead.\n"
        "- Weights are for ONE adult serving. Use realistic portions "
        "(for example a soup has roughly 50-100 g of meat, not 300 g).\n"
        "- Skip tiny garnishes under 5 g unless the dish needs them."
    )

    # Regenerate flow
    if avoid_dishes:
        lines.append("")
        lines.append(
            "REGENERATION: the user saw a previous plan and did NOT like it. "
            "Do NOT use any of these dishes again; suggest clearly different dishes: "
            f"{', '.join(avoid_dishes)}."
        )

    # Output rules
    lines.append("")
    lines.append(
        "OUTPUT RULES:\n"
        "- For EACH meal, list its ingredients with an estimated weight in grams "
        "(weight_g). This is required, because nutrition is calculated by the app.\n"
        "- Do NOT estimate calories or nutrients yourself.\n"
        "- Add a short \"notes\" value only when there is something worth mentioning "
        "(using up an ingredient, honoring a day request). Otherwise use null.\n"
        "- Return JSON only, with no extra text and no markdown fences."
    )
    lines.append("")
    lines.append("""Format (this example shows one day; include only the days required by the SCOPE RULE):
{
  "days": [
    {
      "day": "Monday",
      "breakfast": {
        "name": "Spinach Omelette",
        "ingredients": [
          {"name": "eggs", "weight_g": 120, "from_fridge": true},
          {"name": "olive oil", "weight_g": 10, "from_fridge": false}
        ],
        "notes": "Uses spinach before it spoils."
      },
      "lunch": {"name": "", "ingredients": [], "notes": null},
      "dinner": {"name": "", "ingredients": [], "notes": null},
      "snack": null
    }
  ],
  "notes": []
}""")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Ingredient resolving (database lookup + nutrient calculation)
# ---------------------------------------------------------------------------

def normalize_food_name(name: str) -> str:
    name = name.lower().strip()

    replacements = {
        "mixed berries (fresh)": "berries",
        "whole milk": "milk",
        "boiled egg": "egg",
        "chicken breast": "chicken",
        "maple syrup": "syrup",
        "all-purpose flour": "flour",
    }

    return replacements.get(name, name)


def _fridge_name_set(inventory: FridgeInventory | None) -> set[str]:
    """Lower-cased fridge item names, used as a safety net for from_fridge."""
    if not inventory or not inventory.items:
        return set()
    return {item.name.strip().lower() for item in inventory.items}


# --- Ingredient match checking ------------------------------------------------
# search_food() is a fuzzy search, so it can return a row that merely SHARES a
# word with the ingredient: "chicken" -> "Fried chicken (malaysian style)",
# "green onion" -> "Green tea (unsweetened)", "bok choy" -> "Cabbage (green)".
# Every match is checked here before it is accepted. A wrong match is worse
# than no match, because it adds wrong calories to the meal.

# Words that describe size/colour/state, not WHAT the food is.
_GENERIC_WORDS = {
    "fresh", "raw", "large", "small", "medium", "chopped", "sliced", "diced",
    "minced", "ground", "whole", "green", "red", "yellow", "white", "black",
    "dried", "cooked", "boiled", "steamed", "grilled", "baked", "roasted",
    "fried", "plain", "organic", "lean", "boneless", "skinless", "of", "and",
    "with", "the", "style", "a",
}

# If the database row has one of these words and the ingredient does not, it is
# a different product (fried chicken is not chicken, tea is not a vegetable).
_RISKY_EXTRAS = {
    "fried", "battered", "tea", "juice", "drink", "soda", "candy", "cake",
    "pie", "ice", "cookie", "biscuit", "chips", "crisps", "curry", "sauce",
    "soup", "pudding", "jam", "syrup", "powder", "flavoured", "flavored",
    "sweetened", "coffee", "beer", "wine", "chocolate", "noodle", "pastry",
    # prepared dishes and cuisine labels (a recipe, not an ingredient)
    "style", "malaysian", "indian", "chinese", "thai", "western", "local",
    "homemade", "restaurant", "hawker", "recipe", "stew", "salad", "sandwich",
    "burger", "pizza", "goreng", "laksa", "rendang", "satay", "porridge",
    "congee", "dumpling", "omelette", "omelet", "pancake", "kebab", "biryani",
    "pulao", "korma", "masala", "tikka", "gravy", "casserole", "wrap", "nasi",
}


def _tokens(text: str) -> list[str]:
    words = re.findall(r"[a-z]+", (text or "").lower())
    # crude plural fix: eggs -> egg, tomatoes -> tomato
    out = []
    for w in words:
        if len(w) > 4 and w.endswith("oes"):
            w = w[:-2]
        elif len(w) > 3 and w.endswith("s") and not w.endswith("ss"):
            w = w[:-1]
        out.append(w)
    return out


def _is_good_match(query: str, food_name: str) -> bool:
    """True if the database row really is the ingredient we asked for."""
    q_all = _tokens(query)
    m_all = set(_tokens(food_name))
    if not q_all or not m_all:
        return False
    q = [t for t in q_all if t not in _GENERIC_WORDS] or q_all
    head = q[-1]                       # "green onion" -> "onion"
    if head not in m_all:
        return False                   # the main word must be present
    coverage = sum(t in m_all for t in q) / len(q)
    if coverage < 0.5:
        return False
    if (m_all - set(q_all)) & _RISKY_EXTRAS:
        return False                   # e.g. "fried", "tea" the query never asked for
    return True


@lru_cache(maxsize=4096)
def _cached_search(query: str):
    return search_food(query)


def _find_food(name: str, normalized_name: str):
    """Look the ingredient up and only return a row that passes the check.
    Tries a few plain spellings before giving up."""
    base = normalized_name or name
    candidates = [normalized_name, name,
                  f"{base}, raw", f"raw {base}", f"{base} (boiled)", f"boiled {base}"]
    tried = set()
    for query in candidates:
        query = (query or "").strip().lower()
        if not query or query in tried:
            continue
        tried.add(query)
        food = _cached_search(query)
        if not food:
            continue
        if _is_good_match(normalized_name, food["name"]) or _is_good_match(name, food["name"]):
            return food
        logger.info("Rejected weak match: '%s' (searched '%s') -> '%s'",
                    name, query, food["name"])
    return None


def _display_name(name: str) -> str:
    name = name.strip()
    return name[:1].upper() + name[1:]


def _resolve_ingredients(
    raw_ingredients: list[dict],
    fridge_names: set[str] | None = None,
    meal_name: str | None = None,
) -> tuple[list[MealIngredient], list[str]]:
    """
    Takes Gemini's raw ingredient list (names + weights + from_fridge) and
    turns it into real MealIngredient objects with calculated nutrition.

    - Only database rows that pass _is_good_match are used.
    - The same ingredient listed twice in one meal is merged into ONE line
      (weights added up, nutrition recalculated).
    - from_fridge is true if Gemini said so OR the original name matches a
      fridge item (guards against Gemini labelling it wrongly).

    Returns (ingredients, unmatched_names).
    """
    fridge_names = fridge_names or set()
    ingredients: list[MealIngredient] = []
    foods: list[dict | None] = []          # same order as `ingredients`
    index_by_key: dict[str, int] = {}
    unmatched: list[str] = []

    for raw in raw_ingredients:
        name = (raw.get("name") or "").strip()
        if not name:
            continue
        # Gemini sometimes lists the dish itself as an ingredient: skip it
        if meal_name and name.lower() == meal_name.strip().lower():
            continue
        weight_g = raw.get("weight_g") or 0
        normalized_name = normalize_food_name(name)
        from_fridge = (
            bool(raw.get("from_fridge", False))
            or name.lower() in fridge_names
            or normalized_name in fridge_names
        )

        food = _find_food(name, normalized_name)
        logger.debug("Ingredient '%s' -> '%s' | in DB: %s",
                     name, normalized_name, food is not None)

        key = f"id:{food['id']}" if food else f"name:{normalized_name}"
        if key in index_by_key:
            # Duplicate in the same meal: add the weight to the existing line
            i = index_by_key[key]
            ing = ingredients[i]
            ing.weight_g = (ing.weight_g or 0) + weight_g
            try:
                ing.from_fridge = bool(getattr(ing, "from_fridge", False)) or from_fridge
            except (ValueError, AttributeError):
                pass  # older schemas.py without the from_fridge field
            if foods[i]:
                ing.nutrients = NutrientTotals(**calculate_nutrients(foods[i], ing.weight_g))
            continue

        if food:
            nutrients = calculate_nutrients(food, weight_g)
            # Show Gemini's plain ingredient name ("chicken"), not the database
            # row's label, which can read like a recipe. Nutrition still comes
            # from the matched row (food_id).
            ing = MealIngredient(
                name=_display_name(name), food_id=food["id"], weight_g=weight_g,
                nutrients=NutrientTotals(**nutrients),
                from_fridge=from_fridge,
            )
        else:
            # Not in the database: zero nutrients, flagged as unmatched
            ing = MealIngredient(
                name=_display_name(name), food_id=None, weight_g=weight_g,
                nutrients=NutrientTotals(
                    calories=0, protein_g=0, carbs_g=0, fat_g=0,
                ),
                from_fridge=from_fridge,
            )
            if name not in unmatched:
                unmatched.append(name)

        index_by_key[key] = len(ingredients)
        ingredients.append(ing)
        foods.append(food)

    return ingredients, unmatched


def _build_meal(
    raw_meal: dict,
    fridge_names: set[str] | None = None,
) -> tuple[PlannedMeal, list[str]]:
    """Builds one PlannedMeal (breakfast/lunch/dinner/snack) with its total nutrients."""
    ingredients, unmatched = _resolve_ingredients(
        raw_meal["ingredients"], fridge_names, raw_meal.get("name"))
    totals = add_totals([ing.nutrients.model_dump() for ing in ingredients])

    meal = PlannedMeal(
        name=raw_meal["name"],
        ingredients=ingredients,
        notes=raw_meal.get("notes"),
        nutrients=NutrientTotals(**totals),
    )
    return meal, unmatched


def _build_meal_or_none(
    raw_meal: dict | None,
    fridge_names: set[str] | None = None,
) -> tuple[PlannedMeal | None, list[str]]:
    """Meals can be null (user asked for specific meals only) or empty."""
    if not raw_meal or not raw_meal.get("ingredients"):
        return None, []
    return _build_meal(raw_meal, fridge_names)


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


# ---------------------------------------------------------------------------
# Safety net + ingredient / grocery lists
# ---------------------------------------------------------------------------

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
    Every ingredient used across the plan (fridge items included), with
    duplicates removed. For the shopping screen, use build_grocery_list().
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


def build_grocery_list(plan: WeeklyPlan) -> list[dict]:
    """
    Grocery list = ONLY the ingredients Gemini added (from_fridge is False),
    with weights summed across the plan. Fridge items are skipped because
    they are already at home.

    Returns: [{"name": "olive oil", "weight_g": 30}, ...]
    """
    totals: dict[str, float] = {}

    for day in plan.days:
        for meal in (day.breakfast, day.lunch, day.dinner, day.snack):
            if not meal:
                continue
            for ing in meal.ingredients:
                if ing.from_fridge:
                    continue  # already at home
                key = ing.name.strip().lower()
                totals[key] = totals.get(key, 0) + (ing.weight_g or 0)

    return [{"name": n, "weight_g": round(w)} for n, w in sorted(totals.items())]


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def generate_meal_plan(
    family: list[FamilyMember],
    inventory: FridgeInventory | None = None,
    day_preferences: list[DayPreference] | None = None,
    avoid_dishes: list[str] | None = None,
    user_message: str | None = None,
) -> WeeklyPlan:
    """
    avoid_dishes: dish names from a plan the user just rejected ("Create new
    plan"). Pass them back in so the new plan uses different dishes.

    user_message: the user's free-text request, e.g. "plan for monday" or
    "Italian dinners". Controls scope and can override the profile cuisine.
    """
    summary = _summarize_family(family)
    fridge_names = _fridge_name_set(inventory)

    # Which days does the message ask for? (empty -> not limited)
    target_days = _days_from_message(user_message) or None

    # Days where the user actually chose something in the app
    all_prefs = _active_day_prefs(day_preferences)
    if target_days:
        day_prefs = [(d, t) for d, t in all_prefs if d in target_days]
        skipped_days = [d for d, _ in all_prefs if d not in target_days]
    else:
        day_prefs = all_prefs
        skipped_days = []

    prompt = _build_prompt(summary, inventory, day_prefs,
                           avoid_dishes, user_message, target_days)

    if DEBUG_PROMPT:
        print("[meal_plan] user_message:", user_message)
        print("[meal_plan] raw day_preferences:",
              [dp.model_dump() for dp in (day_preferences or [])])
        print("[meal_plan] target_days:", target_days)
        print("[meal_plan] active day prefs:", day_prefs)
        print("[meal_plan] PROMPT:\n" + prompt)

    def make_request():
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=[prompt],
            config=types.GenerateContentConfig(
                response_mime_type="application/json"),
        )
        return json.loads(response.text)

    data = call_with_retry(make_request, label="Gemini (meal plan)")

    raw_days = data.get("days", [])
    for d in raw_days:
        d["day"] = _canonical_day(d.get("day")) or d.get("day")

    # Enforce scope in code, in case Gemini returned extra days
    extra_notes = []
    if target_days:
        filtered = [d for d in raw_days if d["day"] in target_days]
        if filtered:
            raw_days = filtered
        else:
            extra_notes.append(
                "The AI did not return the requested day(s); showing what it produced."
            )
    if skipped_days:
        extra_notes.append(
            f"Your request for {', '.join(skipped_days)} was not applied because "
            f"you asked only for {', '.join(target_days)}."
        )

    days = []
    for d in raw_days:
        breakfast, un1 = _build_meal_or_none(d.get("breakfast"), fridge_names)
        lunch, un2 = _build_meal_or_none(d.get("lunch"), fridge_names)
        dinner, un3 = _build_meal_or_none(d.get("dinner"), fridge_names)
        snack, un4 = _build_meal_or_none(d.get("snack"), fridge_names)

        meals = [m for m in (breakfast, lunch, dinner, snack) if m]
        day_totals = add_totals([m.nutrients.model_dump() for m in meals])

        days.append(DayPlan(
            day=d["day"],
            breakfast=breakfast,
            lunch=lunch,
            dinner=dinner,
            snack=snack,
            ingredients=_combine_names(meals),
            nutrients=NutrientTotals(**day_totals),
            unmatched_ingredients=un1 + un2 + un3 + un4,
        ))

    plan = WeeklyPlan(days=days, notes=data.get("notes", []))
    plan.notes.extend(extra_notes)

    # Safety net: flag (don't silently drop) any allergen that slipped through
    allergy_warnings = _basic_allergy_check(plan, summary["allergies"])
    plan.notes.extend(allergy_warnings)

    return plan


# --- Quick test you can run directly ----------------------------------------
# python -m app.meal_plan   (run from the backend folder)

if __name__ == "__main__":
    from .schemas import InventoryItem

    fake_family = [
        FamilyMember(
            name="Test User", age=35, gender="female",
            allergies=["peanut"],
            food_preferences=["vegetarian"],
            cuisine_preferences=["indian"],
        )
    ]

    print("=== Only Monday via user message, Monday has a day request ===")
    prefs = [
        DayPreference(day="Monday", meal_type="VLML", cuisine="Italian"),
        DayPreference(day="Tuesday"),   # empty -> ignored
    ]
    plan = generate_meal_plan(
        fake_family, day_preferences=prefs, user_message="plan for monday")
    print("Days returned:", [d.day for d in plan.days])
    for day in plan.days:
        for key in MEAL_KEYS:
            meal = getattr(day, key)
            if meal:
                print(f"  {key}: {meal.name}")
    print("Notes:", plan.notes)

    print("\n\n=== Plan with fridge inventory (Fridge screen) ===")
    fake_inventory = FridgeInventory(items=[
        InventoryItem(name="Spinach", use_soon=True,
                      expiry_estimate="Use within 2 days"),
        InventoryItem(name="Paneer", use_soon=False),
    ])
    plan2 = generate_meal_plan(fake_family, inventory=fake_inventory)
    print("Days returned:", [d.day for d in plan2.days])
    print("Grocery list (Gemini-added only):", build_grocery_list(plan2))