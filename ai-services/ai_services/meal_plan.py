"""
meal_plan.py

generate_meal_plan() builds a 7-day meal plan for the family.

Two ways it's called:
  1. From the Weekly Planner tab: inventory=None, plan is based only on
     the family's profile (allergies, preferences, cuisines).
  2. From the Fridge screen: inventory is the user-confirmed (and maybe
     user-edited) FridgeInventory. The plan then prioritizes using up
     items marked use_soon, and says so in that day's notes.

Either way, day_preferences lets the user request something specific
for individual days (e.g. "Monday: vegetarian only", "Friday: light
dinner") — these apply only to that day, on top of the general
preferences.

No image, no database lookup — one Gemini Flash text call, same pattern
as recipes.py.
"""

import json
from google.genai import types

from gemini_client import client, MODEL_NAME
from retry_utils import call_with_retry
from schemas import FamilyMember, FridgeInventory, WeeklyPlan, DayPlan, PlannedMeal, DayPreference

DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def _summarize_family(family: list[FamilyMember]) -> dict:
    """Combines the whole family's restrictions into one summary, so the
    plan is safe for everyone, not just one member."""
    allergies = set()
    preferences = set()
    cuisines = set()

    for member in family:
        allergies.update(member.allergies)
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
        parts.append(f"meal type: {dp.meal_type}")
    if dp.cuisine:
        parts.append(f"cuisine: {dp.cuisine}")
    if dp.preference:
        parts.append(dp.preference)
    return ", ".join(parts) if parts else "no specific request"


def _build_prompt(summary: dict, inventory: FridgeInventory | None, day_preferences: list[DayPreference] | None) -> str:
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
        use_soon_names = [item.name for item in inventory.items if item.use_soon]
        lines.append("")
        lines.append(f"Ingredients already available at home: {', '.join(item_names)}")
        if use_soon_names:
            lines.append(
                f"IMPORTANT: these are close to spoiling and should be used in the "
                f"FIRST 2-3 days of the plan: {', '.join(use_soon_names)}. "
                f"Mention this in that day's notes, e.g. 'Uses spinach before it spoils.'"
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

    lines.append("")
    lines.append(
        "For each day, list the ingredients needed for each meal, and a combined "
        "'ingredients' list for the whole day (no duplicates). Add a short 'notes' "
        "field per day only when there's something worth mentioning (e.g. using up "
        "an ingredient soon, or honoring a specific day request)."
    )
    lines.append("")
    lines.append("Return JSON only, no extra text, in this format:")
    lines.append("""{
  "days": [
    {
      "day": "Monday",
      "breakfast": {"name": "", "ingredients": [], "notes": null},
      "lunch": {"name": "", "ingredients": [], "notes": null},
      "dinner": {"name": "", "ingredients": [], "notes": null},
      "snack": null,
      "ingredients": [],
      "day_notes": null
    }
  ],
  "notes": []
}""")

    return "\n".join(lines)


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
    with duplicates removed (so "onion" doesn't show up 5 times just
    because 5 different days use it).

    This does NOT call Gemini — the ingredients are already sitting inside
    the WeeklyPlan you already generated. This just gathers them together.

    Example:
        plan = generate_meal_plan(family)
        week_ingredients = get_full_week_ingredients(plan)
        # ['Basmati rice', 'Onion', 'Spinach', 'Paneer', ...]
    """
    seen = set()
    combined = []

    for day in plan.days:
        for ingredient in day.ingredients:
            key = ingredient.strip().lower()  # so "Onion" and "onion" count as the same
            if key not in seen:
                seen.add(key)
                combined.append(ingredient.strip())

    return sorted(combined)


def generate_meal_plan(
    family: list[FamilyMember],
    inventory: FridgeInventory | None = None,
    day_preferences: list[DayPreference] | None = None,
) -> WeeklyPlan:
    summary = _summarize_family(family)
    prompt = _build_prompt(summary, inventory, day_preferences)

    def make_request():
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=[prompt],
            config=types.GenerateContentConfig(response_mime_type="application/json"),
        )
        return json.loads(response.text)

    data = call_with_retry(make_request, label="Gemini (meal plan)")

    days = []
    for d in data["days"]:
        days.append(DayPlan(
            day=d["day"],
            breakfast=PlannedMeal(**d["breakfast"]),
            lunch=PlannedMeal(**d["lunch"]),
            dinner=PlannedMeal(**d["dinner"]),
            snack=PlannedMeal(**d["snack"]) if d.get("snack") else None,
            ingredients=d.get("ingredients", []),
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

    # Try WITHOUT inventory first (Weekly Planner tab)
    print("=== Plan without inventory ===")
    plan = generate_meal_plan(fake_family, inventory=None)
    for day in plan.days[:2]:  # just show 2 days to keep it short
        print(f"\n{day.day}")
        print(f"  Breakfast: {day.breakfast.name}")
        print(f"  Lunch: {day.lunch.name}")
        print(f"  Dinner: {day.dinner.name}")
        print(f"  Ingredients: {', '.join(day.ingredients)}")
    print("\nPlan notes:", plan.notes)

    # Try WITH inventory (Fridge screen), including a use-soon item
    print("\n\n=== Plan with fridge inventory (spinach expiring) ===")
    fake_inventory = FridgeInventory(items=[
        InventoryItem(name="Spinach", use_soon=True, expiry_estimate="Use within 2 days"),
        InventoryItem(name="Paneer", use_soon=False),
        InventoryItem(name="Tomatoes", use_soon=False),
    ])
    plan2 = generate_meal_plan(fake_family, inventory=fake_inventory)
    print(f"\n{plan2.days[0].day}")
    print(f"  Breakfast: {plan2.days[0].breakfast.name}")
    print(f"  Lunch: {plan2.days[0].lunch.name}")
    print(f"  Dinner: {plan2.days[0].dinner.name}")
    print("\nPlan notes:", plan2.notes)

    # Try with only SOME family members (e.g. "just the kids tonight")
    # No code change needed — just pass a shorter list.
    print("\n\n=== Plan for a SUBSET of the family (2 out of 5, say) ===")
    grandmother = FamilyMember(
        name="Grandmother", age=68, gender="female",
        food_preferences=["vegetarian"],
        cuisine_preferences=["indian"],
    )
    child = FamilyMember(
        name="Child", age=8, gender="male",
        allergies=["peanut"],
        cuisine_preferences=["indian"],
    )
    selected_members = [grandmother, child]  # the other 3 members simply left out

    plan3 = generate_meal_plan(selected_members, inventory=None)
    print(f"\n{plan3.days[0].day}")
    print(f"  Lunch: {plan3.days[0].lunch.name}")
    print(f"  Ingredients: {', '.join(plan3.days[0].ingredients)}")

    # Try WITH day-specific preferences — the new feature.
    # General preference is vegetarian, but Friday and Sunday get overrides.
    print("\n\n=== Plan with day-specific preferences ===")
    day_prefs = [
        DayPreference(day="Friday", meal_type="Non-Vegetarian", cuisine="Chinese"),
        DayPreference(day="Sunday", preference="light dinner, low oil"),
    ]
    plan4 = generate_meal_plan(fake_family, inventory=None, day_preferences=day_prefs)
    for day in plan4.days:
        if day.day in ("Friday", "Sunday"):
            requested = [_format_day_preference(dp) for dp in day_prefs if dp.day == day.day][0]
            print(f"\n{day.day} (requested: {requested})")
            print(f"  Dinner: {day.dinner.name}")
            if day.ingredients:
                print(f"  Ingredients: {', '.join(day.ingredients)}")
    print("\nPlan notes:", plan4.notes)

    # Show the whole week's ingredients combined (e.g. "show me everything I need")
    print("\n\n=== Whole week's ingredients, combined ===")
    week_list = get_full_week_ingredients(plan4)
    print(f"({len(week_list)} unique ingredients)")
    for ingredient in week_list:
        print(f"  - {ingredient}")