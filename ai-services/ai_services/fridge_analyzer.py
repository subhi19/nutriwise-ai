"""
fridge_analyzer.py

analyze_fridge() looks at a fridge/grocery photo and returns a list of
ingredients found, with a rough quantity and whether each looks like it
should be used soon (wilting vegetables, near-empty containers, etc.).

Unlike meal_analyzer.py, this does NOT need the nutrition database —
we're not calculating calories here, just listing what's available.
That list gets used later by suggest_recipes() and generate_meal_plan().
"""

import json
from google.genai import types

from meal_analyzer import client, MODEL_NAME  # reuse the same Gemini connection
from retry_utils import call_with_retry
from schemas import FridgeInventory, InventoryItem


FRIDGE_PROMPT = """You are a kitchen assistant. Look at this fridge or
grocery photo.

1. Identify every distinct food item you can see (vegetables, fruits,
   dairy, eggs, cooked leftovers, condiments, etc.).
2. Estimate a simple quantity for each (e.g. "6", "1 bunch", "half full").
   If you can't tell, leave it out.
3. Mark "use_soon": true for anything that looks wilting, close to its
   use-by date, near empty, or likely to spoil soon. Otherwise false.
4. For items where use_soon is true, give a short "expiry_estimate"
   (e.g. "Use within 3 days", "Use within 2 days"), based on how the
   item looks and how quickly that type of food typically spoils.
   Leave it out for items that are not close to spoiling.

Return JSON only, no extra text, in this format:
{
  "items": [
    {"name": "", "quantity": "", "use_soon": false, "expiry_estimate": ""}
  ]
}"""


def analyze_fridge(image_bytes: bytes, mime_type: str) -> FridgeInventory:
    def make_request():
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=[
                types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                FRIDGE_PROMPT,
            ],
            config=types.GenerateContentConfig(response_mime_type="application/json"),
        )
        return json.loads(response.text)

    data = call_with_retry(make_request, label="Gemini (fridge analysis)")
    items = [InventoryItem(**item) for item in data["items"]]
    return FridgeInventory(items=items)


# --- Quick test you can run directly ----------------------------------------
# python fridge_analyzer.py

if __name__ == "__main__":
    import os
    image_name = input("Fridge photo file name (e.g. fridge.jpg): ").strip().strip('"')
    image_path = os.path.join("images", image_name)
    with open(image_path, "rb") as f:
        image_bytes = f.read()

    result = analyze_fridge(image_bytes, "image/jpeg")

    print("\n--- Fridge inventory ---")
    for item in result.items:
        qty = f" ({item.quantity})" if item.quantity else ""
        if item.use_soon:
            flag = f" [USE SOON — {item.expiry_estimate}]" if item.expiry_estimate else " [USE SOON]"
        else:
            flag = ""
        print(f"{item.name}{qty}{flag}")