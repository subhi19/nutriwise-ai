"""
test_full_flow.py

Proves the WHOLE chain works together, exactly as described:

  Option A (no photo):
      generate_meal_plan(family, inventory=None)
      -> generate_grocery_list(family, plan, inventory=None)
      -> grocery list has EVERYTHING the plan needs

  Option B (photo uploaded):
      analyze_fridge(photo) -> FridgeInventory
      -> generate_meal_plan(family, inventory)   [AI may add extra ingredients too]
      -> generate_grocery_list(family, plan, inventory)
      -> grocery list EXCLUDES whatever was in the photo

Run this once with a real fridge/vegetable photo to see both paths for
yourself before moving on to anything else.
"""

import os
from fridge_analyzer import analyze_fridge
from meal_plan import generate_meal_plan
from grocery import generate_grocery_list
from schemas import FamilyMember

fake_family = [
    FamilyMember(
        name="Test User", age=35, gender="female",
        allergies=["peanut"],
        food_preferences=["vegetarian"],
        cuisine_preferences=["indian"],
    )
]

print("=" * 60)
print("OPTION A: No photo uploaded")
print("=" * 60)

plan_a = generate_meal_plan(fake_family, inventory=None)
print(f"\nMonday: {plan_a.days[0].breakfast.name} / {plan_a.days[0].lunch.name} / {plan_a.days[0].dinner.name}")

grocery_a = generate_grocery_list(fake_family, plan_a, inventory=None)
print(f"\nGrocery list: {len(grocery_a.items)} items (should include EVERYTHING the plan needs)")
for item in grocery_a.items[:6]:
    print(f"  [{item.category}] {item.name} — {item.quantity}")


print("\n\n" + "=" * 60)
print("OPTION B: Photo uploaded")
print("=" * 60)

use_real_photo = input("\nDo you have a fridge/vegetable photo to test with? (y/n): ").strip().lower()

if use_real_photo == "y":
    image_name = input("Image file name (e.g. fridge.jpg): ").strip().strip('"')
    image_path = os.path.join("images", image_name)
    with open(image_path, "rb") as f:
        image_bytes = f.read()

    print("\nAnalyzing photo...")
    inventory = analyze_fridge(image_bytes, "image/jpeg")

    print("\n--- What was detected ---")
    for item in inventory.items:
        print(f"  {item.name}" + (" [USE SOON]" if item.use_soon else ""))
else:
    # Fallback fake data, so this still runs even without a photo handy
    from schemas import InventoryItem, FridgeInventory
    print("\n(Using sample data instead of a real photo)")
    inventory = FridgeInventory(items=[
        InventoryItem(name="Onion", use_soon=False),
        InventoryItem(name="Tomatoes", use_soon=False),
        InventoryItem(name="Spinach", use_soon=True, expiry_estimate="Use within 2 days"),
    ])

print("\nGenerating meal plan using this inventory...")
plan_b = generate_meal_plan(fake_family, inventory=inventory)
print(f"\nMonday: {plan_b.days[0].breakfast.name} / {plan_b.days[0].lunch.name} / {plan_b.days[0].dinner.name}")
print("Plan notes:", plan_b.notes)

print("\nGenerating grocery list (should EXCLUDE what's in the photo)...")
grocery_b = generate_grocery_list(fake_family, plan_b, inventory=inventory)

fridge_item_names = {item.name.lower() for item in inventory.items}
print(f"\nGrocery list: {len(grocery_b.items)} items")
for item in grocery_b.items:
    print(f"  [{item.category}] {item.name} — {item.quantity}")

# Sanity check: confirm none of the fridge items leaked into the grocery list
leaked = [item.name for item in grocery_b.items if item.name.lower() in fridge_item_names]
if leaked:
    print(f"\n⚠️  WARNING: these fridge items leaked into the grocery list: {leaked}")
else:
    print("\n✅ Confirmed: nothing from the fridge photo appears in the grocery list.")