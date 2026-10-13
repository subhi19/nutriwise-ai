"""
test_meal_plan_flow.py

Tests the Weekly Planner flow the way the real screen works — you choose
ONE path, not every scenario at once:

    1) No photo      -> generate_meal_plan(family, inventory=None)
    2) Fridge photo  -> analyze_fridge(photo) -> you add/remove ingredients
                     -> generate_meal_plan(family, inventory)

Then, like the "Create new plan" button, you can rerun and the dishes you
just saw are passed back as avoid_dishes so the new plan is different.

Run:   python test_meal_plan_flow.py
"""

import os
import sys
import mimetypes

# Works whether this file sits in ai_services/ or in a sibling tests/ folder
_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_here, ".."))

from ai_services.fridge_analyzer import analyze_fridge
from ai_services.meal_plan import generate_meal_plan
from ai_services.schemas import FamilyMember, FridgeInventory, InventoryItem
from ai_services.errors import AIServiceError

# Pretend household (until the backend loads real profiles from the database)
HOUSEHOLD = [
    FamilyMember(name="Asha", age=38, gender="female",
                 allergies=["peanut"], food_preferences=["vegetarian"],
                 cuisine_preferences=["indian"]),
    FamilyMember(name="Ravi", age=40, gender="male",
                 food_preferences=["non_vegetarian"],
                 cuisine_preferences=["indian", "chinese"]),
    FamilyMember(name="Meena", age=9, gender="female",
                 allergies=["milk"], cuisine_preferences=["indian"]),
]


def find_image(name: str) -> str | None:
    for path in [name, os.path.join("images", name),
                 os.path.join(_here, name), os.path.join(_here, "images", name),
                 os.path.join(_here, "..", "ai_services", "images", name)]:
        if os.path.isfile(path):
            return path
    return None


def pick_members() -> list[FamilyMember]:
    print("\nWho is eating this week?")
    for i, m in enumerate(HOUSEHOLD, 1):
        extras = []
        if m.allergies:
            extras.append("allergic: " + ", ".join(m.allergies))
        if m.food_preferences:
            extras.append(", ".join(m.food_preferences))
        print(f"  {i}. {m.name} ({m.age})  {'; '.join(extras)}")
    raw = input("Numbers separated by commas (Enter = everyone): ").strip()
    if not raw:
        return list(HOUSEHOLD)
    chosen = []
    for part in raw.split(","):
        part = part.strip()
        if part.isdigit() and 1 <= int(part) <= len(HOUSEHOLD):
            chosen.append(HOUSEHOLD[int(part) - 1])
    return chosen or list(HOUSEHOLD)


def get_inventory() -> FridgeInventory | None:
    print("\nOption 1: skip the photo (AI plans freely)")
    print("Option 2: upload a fridge / vegetable photo")
    if input("Choose 1 or 2: ").strip() != "2":
        return None

    name = input("Photo file name: ").strip().strip('"')
    path = find_image(name)
    if not path:
        print(f"Could not find '{name}'. Continuing WITHOUT a photo.")
        return None

    mime = mimetypes.guess_type(path)[0] or "image/jpeg"
    with open(path, "rb") as f:
        data = f.read()

    print("\nAnalyzing the photo...")
    inventory = analyze_fridge(data, mime)

    # Confirm / edit step, same as the app's ingredient chips
    while True:
        print("\nIngredients found:")
        for i, item in enumerate(inventory.items, 1):
            soon = f"  [USE SOON — {item.expiry_estimate}]" if item.use_soon else ""
            print(f"  {i}. {item.name}{soon}")
        cmd = input("\nType a number to REMOVE it, a name to ADD it, or Enter to confirm: ").strip()
        if not cmd:
            return inventory
        if cmd.isdigit() and 1 <= int(cmd) <= len(inventory.items):
            removed = inventory.items.pop(int(cmd) - 1)
            print(f"  removed {removed.name}")
        elif not cmd.isdigit():
            inventory.items.append(InventoryItem(name=cmd))
            print(f"  added {cmd}")


def show_plan(plan):
    print(f"\n{'=' * 60}\n7-DAY PLAN\n{'=' * 60}")
    for d in plan.days:
        print(f"\n{d.day}  —  {d.nutrients.calories:g} kcal, protein {d.nutrients.protein_g:g} g")
        print(f"  Breakfast: {d.breakfast.name} ({d.breakfast.nutrients.calories:g} kcal)")
        print(f"  Lunch:     {d.lunch.name} ({d.lunch.nutrients.calories:g} kcal)")
        print(f"  Dinner:    {d.dinner.name} ({d.dinner.nutrients.calories:g} kcal)")
        if d.snack:
            print(f"  Snack:     {d.snack.name} ({d.snack.nutrients.calories:g} kcal)")
        if d.unmatched_ingredients:
            print(f"  (AI-estimated, not in database: {', '.join(d.unmatched_ingredients)})")
    if plan.notes:
        print("\nNotes:")
        for n in plan.notes:
            print(f"  - {n}")


def dish_names(plan) -> list[str]:
    names = []
    for d in plan.days:
        for meal in (d.breakfast, d.lunch, d.dinner, d.snack):
            if meal and meal.name not in names:
                names.append(meal.name)
    return names


def main():
    family = pick_members()
    print(f"\nPlanning for: {', '.join(m.name for m in family)}")

    inventory = get_inventory()
    print("\nMode:", "WITH fridge photo ingredients" if inventory else "NO photo (free plan)")

    avoid = None
    while True:
        print("\nGenerating the 7-day plan (this can take a minute)...")
        try:
            plan = generate_meal_plan(family, inventory=inventory, avoid_dishes=avoid)
        except (AIServiceError, RuntimeError) as e:
            print(f"\nPlan failed: {e}")
            return

        show_plan(plan)

        if input("\nLove it? Press Enter to finish, or type n for a different plan: ").strip().lower() != "n":
            print("\nDone.")
            return

        avoid = dish_names(plan)
        print(f"\nRerunning and telling the AI to avoid {len(avoid)} dishes it just showed...")


if __name__ == "__main__":
    main()



#  Who is eating this week?
#   1. Asha (38)  allergic: peanut; vegetarian
#   2. Ravi (40)  non_vegetarian
#   3. Meena (9)  allergic: milk
# Numbers separated by commas (Enter = everyone): 2,3

# Planning for: Ravi, Meena

# Option 1: skip the photo (AI plans freely)
# Option 2: upload a fridge / vegetable photo
# Choose 1 or 2: 1

# Mode: NO photo (free plan)

# Generating the 7-day plan (this can take a minute)...
# Direct use of automatic function calling (AFC) in Models.generate_content is not recommended. Instead, we recommend to use AFC in Chat.send_message. Similarly, direct use of AFC in Models.generate_content_stream is not recommended. Instead, we recommend to use AFC in Chat.send_message_stream.


# ============================================================
# 7-DAY PLAN
# ============================================================

# Monday  —  2363.4 kcal, protein 110.4 g
#   Breakfast: Indian Egg Bhurji with Whole Wheat Roti (370.2 kcal)
#   Lunch:     Chinese Chicken Fried Rice (967.9 kcal)
#   Dinner:    Indian Chicken Curry with Basmati Rice (949.6 kcal)
#   Snack:     Spiced Roasted Chickpeas (75.7 kcal)
#   (AI-estimated, not in database: Whole Wheat Flour, Ginger-Garlic Paste)

# Tuesday  —  2197.6 kcal, protein 92.9 g
#   Breakfast: Indian Potato Masala Dosa with Coconut Chutney (347.6 kcal)
#   Lunch:     Chinese Kung Pao Chicken with Steamed White Rice (968.2 kcal)
#   Dinner:    Indian Mutton Curry with Roti (656.8 kcal)
#   Snack:     Fresh Mango Slices (225 kcal)
#   (AI-estimated, not in database: Whole Wheat Flour)

# Wednesday  —  2028.8 kcal, protein 118.5 g
#   Breakfast: Chinese Steamed Chicken and Chive Dumplings (538.2 kcal)
#   Lunch:     Indian Coconut Fish Curry with Steamed Rice (781 kcal)
#   Dinner:    Chinese Chicken Chow Mein (677.1 kcal)
#   Snack:     Indian Sprouted Moong Salad (32.5 kcal)
#   (AI-estimated, not in database: Shredded Cabbage)

# Thursday  —  1954.7 kcal, protein 82.2 g
#   Breakfast: Indian Poha with Hard-Boiled Eggs (348.5 kcal)
#   Lunch:     Chinese Sweet and Sour Chicken with Rice (983 kcal)
#   Dinner:    Indian Egg Curry with Basmati Rice (588 kcal)
#   Snack:     Smashed Chinese Cucumber Salad (35.2 kcal)
#   (AI-estimated, not in database: Pineapple Chunks, Minced Garlic)

# Friday  —  1085.6 kcal, protein 47.2 g
#   Breakfast: Chinese Savory Chicken Congee (378.9 kcal)
#   Lunch:     Indian Keema Matar with Paratha (46.8 kcal)
#   Dinner:    Chinese Mapo Tofu with Pork and Rice (612.8 kcal)
#   Snack:     Roasted Salted Cashews (47.1 kcal)
#   (AI-estimated, not in database: Fresh Ginger, Minced Chicken/Mutton, Whole Wheat Flour, Ground Pork)

# Saturday  —  1757.4 kcal, protein 75 g
#   Breakfast: Indian Chicken Keema Stuffed Paratha (269 kcal)
#   Lunch:     Chinese Sichuan Garlic Shrimp with Rice (430.2 kcal)
#   Dinner:    Dairy-Free Indian Chicken Biryani (1019.2 kcal)
#   Snack:     Boiled Egg with Black Pepper (39 kcal)
#   (AI-estimated, not in database: Whole Wheat Flour, Peeled Shrimp, Garlic, Sliced Fried Onions)

# Sunday  —  1577.1 kcal, protein 61.1 g
#   Breakfast: Chinese Steamed Pork Baozi (Buns) (154.4 kcal)
#   Lunch:     Indian Prawn Coconut Curry with Rice (485 kcal)
#   Dinner:    Chinese Hainanese Chicken Rice (937.7 kcal)
#   Snack:     Dry Roasted Soybeans (Edamame) (0 kcal)
#   (AI-estimated, not in database: Ground Pork, Raw Prawns, Roasted Soybeans)

# Notes:
#   - All traditional Indian recipes (such as Biryani and Curries) have been prepared using plant-based oils and coconut milk in place of ghee, yogurt, or butter to strictly avoid milk allergens.
#   - Wednesday: 'Milk (whole)' may contain 'milk' — please check.
#   - Saturday: 'Milk (whole)' may contain 'milk' — please check.
#   - Sunday: 'Milk (whole)' may contain 'milk' — please check.

# Love it? Press Enter to finish, or type n for a different plan: 