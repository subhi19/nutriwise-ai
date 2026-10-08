"""
test_fridge_to_recipes.py

This shows the REAL connection between fridge_analyzer.py and recipes.py:
  1. Take a real fridge photo
  2. analyze_fridge() looks at it and lists what's inside
  3. That exact list gets handed directly to suggest_recipes()
     (no database, no storage — just passed straight from one
     function to the next, in memory)

Run this to see the whole chain work together.
"""

import os
from fridge_analyzer import analyze_fridge
from recipes import suggest_recipes
from schemas import FamilyMember

# --- Step 1: Load a real fridge photo ---------------------------------------

image_name = input("Fridge photo file name (e.g. fridge.jpg): ").strip().strip('"')
image_path = os.path.join("images", image_name)

with open(image_path, "rb") as f:
    image_bytes = f.read()

# --- Step 2: Analyze the fridge ---------------------------------------------

print("\nAnalyzing fridge photo...")
inventory = analyze_fridge(image_bytes, "image/jpeg")

print("\n--- What was found in the fridge ---")
for item in inventory.items:
    flag = f" [USE SOON — {item.expiry_estimate}]" if item.use_soon else ""
    print(f"  {item.name}{flag}")

# --- Step 3: Pass that SAME inventory object straight into suggest_recipes --

fake_family = [
    FamilyMember(name="Test User", age=30, gender="female",
                 food_preferences=["vegetarian"])
]

print("\nGenerating recipes from what's in the fridge...")
recipes_result = suggest_recipes(inventory, fake_family)

print("\n--- Suggested recipes ---")
for recipe in recipes_result.recipes:
    print(f"\n{recipe.name}")
    print("  Uses from fridge:", ", ".join(recipe.ingredients_from_fridge))
    if recipe.extra_ingredients:
        print("  Also needs:", ", ".join(recipe.extra_ingredients))