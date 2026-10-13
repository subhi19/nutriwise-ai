"""
test_fridge_to_recipes.py  (updated)

Tests the Fridge Analyzer tab exactly like the real screen:

    fridge photo -> analyze_fridge() -> you confirm / edit the ingredient list
                 -> suggest_recipes(inventory, family)   [fridge-only, with nutrients]
                 -> "suggest another" -> same call again with avoid_dishes

It also runs two automatic sanity checks on every result:
  1. FRIDGE-ONLY: does any recipe use an ingredient that is not on your
     confirmed list? (pantry staples like salt/oil are allowed)
  2. ALLERGY: does any recipe contain an ingredient the household is
     allergic to?

Run:   python test_fridge_to_recipes.py
"""

import os
import sys
import mimetypes

# Works whether this file sits in ai_services/ or in a sibling tests/ folder
_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_here, ".."))

from ai_services.fridge_analyzer import analyze_fridge
from ai_services.recipes import suggest_recipes
from ai_services.schemas import FamilyMember, FridgeInventory, InventoryItem
from ai_services.errors import AIServiceError

# Pretend household (until the backend loads real profiles from the database)
FAMILY = [
    FamilyMember(name="Asha", age=38, gender="female",
                 allergies=["peanut"], food_preferences=["vegetarian"],
                 cuisine_preferences=["indian"]),
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


def get_confirmed_inventory() -> FridgeInventory | None:
    name = input("Fridge / vegetable photo file name: ").strip().strip('"')
    path = find_image(name)
    if not path:
        print(f"\nCould not find '{name}'. Looked in the current folder and in images/.")
        print(f"You are running from: {os.getcwd()}")
        return None

    mime = mimetypes.guess_type(path)[0] or "image/jpeg"
    with open(path, "rb") as f:
        data = f.read()

    print("\nAnalyzing the photo...")
    inventory = analyze_fridge(data, mime)

    # Same as the app's ingredient chips: remove wrong ones, add missed ones
    while True:
        print("\nIngredients found:")
        if not inventory.items:
            print("  (nothing detected yet)")
        for i, item in enumerate(inventory.items, 1):
            soon = f"  [USE SOON — {item.expiry_estimate}]" if item.expiry_estimate else (
                "  [USE SOON]" if item.use_soon else "")
            print(f"  {i}. {item.name}{soon}")

        cmd = input("\nType a number to REMOVE it, a name to ADD it, or Enter to confirm: ").strip()
        if not cmd:
            if not inventory.items:
                print("  Add at least one ingredient first.")
                continue
            return inventory
        if cmd.isdigit() and 1 <= int(cmd) <= len(inventory.items):
            removed = inventory.items.pop(int(cmd) - 1)
            print(f"  removed {removed.name}")
        elif not cmd.isdigit():
            inventory.items.append(InventoryItem(name=cmd))
            print(f"  added {cmd}")
        else:
            print(f"  Please type a number from 1 to {len(inventory.items)}, or a name.")


def _words(text: str) -> list[str]:
    text = text.lower().split("(")[0]
    return [w for w in text.replace(",", " ").split() if len(w) >= 3]


def on_fridge_list(ingredient_name: str, inventory: FridgeInventory) -> bool:
    """Loose check: does any word of this ingredient match any fridge item
    (either direction)? Loose on purpose, because the database name can
    differ from the fridge name ('Tomato (raw)' vs 'Tomatoes')."""
    fridge_names = [i.name.lower() for i in inventory.items]
    for w in _words(ingredient_name):
        for f in fridge_names:
            if w in f or f in w or any(fw in w or w in fw for fw in _words(f)):
                return True
    return False


def allergy_words() -> list[str]:
    found = []
    for m in FAMILY:
        found.extend(a.lower() for a in m.allergies)
        found.extend(a.lower() for a in m.anyother_specific_allergy)
    return sorted(set(found))


def show_recipes(result, inventory: FridgeInventory):
    allergens = allergy_words()
    print(f"\n{'=' * 60}\nSUGGESTED RECIPES (fridge-only, with nutrients)\n{'=' * 60}")

    for r in result.recipes:
        t = r.total_nutrients
        print(f"\n{r.name}")
        print(f"  Nutrition: {t.calories:g} kcal | protein {t.protein_g:g} g | "
              f"carbs {t.carbs_g:g} g | fat {t.fat_g:g} g | fiber {t.fiber_g:g} g")

        for ing in r.ingredients:
            note = "" if ing.food_id else "  [AI estimate]"
            print(f"    - {ing.name}: {ing.weight_g:g} g, {ing.nutrients.calories:g} kcal{note}")
        if r.pantry_staples:
            print(f"    Pantry staples: {', '.join(r.pantry_staples)}")
        for i, step in enumerate(r.steps, 1):
            print(f"    {i}. {step}")

        # Sanity check 1: fridge-only
        outside = [ing.name for ing in r.ingredients if not on_fridge_list(ing.name, inventory)]
        if outside:
            print(f"  ⚠ FRIDGE-ONLY CHECK: not on your list -> {', '.join(outside)}")
            print("    (could just be a naming difference; check if it's a real extra ingredient)")

        # Sanity check 2: allergies
        names = [ing.name.lower() for ing in r.ingredients] + [s.lower() for s in r.pantry_staples]
        hits = [a for a in allergens if any(a in n for n in names)]
        if hits:
            print(f"  ⚠ ALLERGY CHECK: contains {', '.join(hits)}!")

    print()
    print(f"Household allergies being avoided: {', '.join(allergens) or 'none'}")


def main():
    print("Family used:", ", ".join(m.name for m in FAMILY))

    inventory = get_confirmed_inventory()
    if inventory is None:
        return
    print("\nConfirmed ingredients:", ", ".join(i.name for i in inventory.items))

    avoid = None
    while True:
        print("\nGenerating recipes...")
        try:
            result = suggest_recipes(inventory, FAMILY, avoid_dishes=avoid)
        except (AIServiceError, RuntimeError) as e:
            print(f"\nRecipe generation failed: {e}")
            return

        show_recipes(result, inventory)

        if avoid:
            repeated = [r.name for r in result.recipes if r.name in avoid]
            print("RERUN CHECK:", f"repeated -> {repeated}" if repeated else "all recipes are new ✅")

        if input("\nLove it? Press Enter to finish, or type n for different recipes: ").strip().lower() != "n":
            print("\nDone.")
            return

        avoid = [r.name for r in result.recipes]
        print(f"\nRerunning and telling the AI to avoid {len(avoid)} recipes it just showed...")


if __name__ == "__main__":
    main()