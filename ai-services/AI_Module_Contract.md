# AI Module Contract

Owner: AI module (Gemini Vision, Nutrition DB with RAG, Gemini Flash recommendations)
Folder in repo: `ai-services/`
Read by: Backend and Frontend developers

This document covers only what the AI module takes in and gives back. The API endpoints and the app screens are owned by the backend and frontend developers.

## 1. What the AI module provides

Six Python functions that the backend imports and calls. The mobile app never calls them directly.

| Function | Purpose |
|---|---|
| `analyze_meal` | Meal photo to foods, grams, nutrients, missing nutrients, suggestions |
| `correct_meal` | Recalculate a meal after the user types a corrected or missing dish name |
| `analyze_fridge` | Fridge photo to an ingredient inventory |
| `suggest_recipes` | Recipes based on the fridge inventory and family profile |
| `generate_meal_plan` | 7-day plan with ingredients, based on the family profile and inventory |
| `generate_grocery_list` | Grocery list from the plan, inventory, preferences, and user-typed requirements |

## 2. How to use it

```bash
cd ai-services
pip install -r requirements.txt
cp .env.example .env
```

```python
from ai_services import analyze_meal
result = analyze_meal(image_bytes, "image/jpeg", member)   # returns a MealAnalysis
```

**Environment variables**

```
GEMINI_API_KEY=your_key_here
MODEL_NAME=gemini-3.8-flash
SUPABASE_URL=your_supabase_url
SUPABASE_READONLY_KEY=your_read_only_key
USE_MOCK=true
```

**Mock switch**
- `USE_MOCK=true`: every function returns sample data from `ai-services/mocks/`. No AI calls, so it works right away.
- `USE_MOCK=false`: real Gemini and database calls.
- The function call is the same in both modes.

**Notes**
- The functions are synchronous. In FastAPI, use a plain `def` endpoint or `run_in_threadpool`.
- Keep the Gemini key on the server only, never in the mobile app.
- Model names change over time. Update `MODEL_NAME` in `.env` if a model is retired.

## 3. Function signatures

```python
analyze_meal(image_bytes: bytes, mime_type: str, member: FamilyMember) -> MealAnalysis

correct_meal(
    previous: MealAnalysis,
    corrections: list[ItemCorrection],
    member: FamilyMember,
) -> MealAnalysis

analyze_fridge(image_bytes: bytes, mime_type: str) -> FridgeInventory

suggest_recipes(inventory: FridgeInventory, family: list[FamilyMember]) -> RecipeSuggestions

generate_meal_plan(family: list[FamilyMember], inventory: FridgeInventory | None) -> WeeklyPlan

generate_grocery_list(
    family: list[FamilyMember],
    plan: WeeklyPlan,
    inventory: FridgeInventory | None,
    user_requirements: list[str],
) -> GroceryList
```

## 4. Data models (`ai-services/schemas.py`)

This file is the single source of truth for the data shapes.

```python
from typing import Literal, Optional
from pydantic import BaseModel

Confidence = Literal["low", "medium", "high"]

class FamilyMember(BaseModel):
    id: Optional[str] = None
    name: str
    age: int
    gender: str
    allergies: list[str] = []           # e.g. "milk", "peanut", "egg"
    health_conditions: list[str] = []   # e.g. "diabetes", "hypertension"
    food_preferences: list[str] = []    # e.g. "vegetarian"

class NutrientTotals(BaseModel):
    calories: float = 0        # kcal
    protein_g: float = 0
    carbs_g: float = 0
    fat_g: float = 0
    fiber_g: float = 0
    iron_mg: float = 0
    calcium_mg: float = 0
    vitamin_a_mcg: float = 0
    vitamin_c_mg: float = 0

class MealItem(BaseModel):
    name: str
    food_id: Optional[int] = None      # null if not matched in the database
    weight_g: float
    nutrients: NutrientTotals
    confidence: Confidence
    needs_review: bool = False         # true if confidence is low or the food was not matched
    user_corrected: bool = False       # true if the name was typed by the user

class MealAnalysis(BaseModel):
    items: list[MealItem]
    total: NutrientTotals
    missing_nutrients: list[str]       # labels: Protein, Fiber, Iron, Calcium, Vitamin A, Vitamin C
    suggestions: list[str]
    unmatched_items: list[str] = []    # foods seen or typed but not in the database

class ItemCorrection(BaseModel):
    item_index: Optional[int] = None   # position in MealAnalysis.items; null = add a dish that was missed
    name: str                          # dish name typed by the user
    weight_g: Optional[float] = None   # optional; if null, keep the old weight (replace) or use a standard serving (add)

class InventoryItem(BaseModel):
    name: str
    quantity: Optional[str] = None     # e.g. "6", "1 bunch"; may be null
    use_soon: bool = False

class FridgeInventory(BaseModel):
    items: list[InventoryItem]

class Recipe(BaseModel):
    name: str
    ingredients_from_fridge: list[str]
    extra_ingredients: list[str] = []
    steps: list[str]

class RecipeSuggestions(BaseModel):
    recipes: list[Recipe]

class PlannedMeal(BaseModel):
    name: str
    ingredients: list[str]
    notes: Optional[str] = None

class DayPlan(BaseModel):
    day: str                           # "Monday" ... "Sunday"
    breakfast: PlannedMeal
    lunch: PlannedMeal
    dinner: PlannedMeal
    snack: Optional[PlannedMeal] = None
    ingredients: list[str] = []        # all ingredients for the day, combined, without duplicates

class WeeklyPlan(BaseModel):
    days: list[DayPlan]                # always 7 items, Monday to Sunday
    notes: list[str] = []

class GroceryItem(BaseModel):
    name: str
    food_id: Optional[int] = None
    quantity: str
    category: str                      # e.g. "Vegetables", "Dairy", "Grains"
    source: Literal["missing_ingredient", "preference", "user_added"]

class GroceryList(BaseModel):
    items: list[GroceryItem]
    not_in_database: list[str] = []
```

## 5. Sample outputs

These values are sample data only. The same examples are in `ai-services/mocks/`.

**`analyze_meal` returns `MealAnalysis`**

```json
{
  "items": [
    {
      "name": "Cooked basmati rice",
      "food_id": 12,
      "weight_g": 150,
      "nutrients": {"calories": 195, "protein_g": 4, "carbs_g": 42, "fat_g": 0.4,
                    "fiber_g": 0.6, "iron_mg": 0.5, "calcium_mg": 15,
                    "vitamin_a_mcg": 0, "vitamin_c_mg": 0},
      "confidence": "high",
      "needs_review": false,
      "user_corrected": false
    },
    {
      "name": "Yellow dal",
      "food_id": 48,
      "weight_g": 100,
      "nutrients": {"calories": 110, "protein_g": 6, "carbs_g": 15, "fat_g": 3,
                    "fiber_g": 3, "iron_mg": 1.6, "calcium_mg": 25,
                    "vitamin_a_mcg": 5, "vitamin_c_mg": 1},
      "confidence": "medium",
      "needs_review": false,
      "user_corrected": false
    }
  ],
  "total": {"calories": 305, "protein_g": 10, "carbs_g": 57, "fat_g": 3.4,
            "fiber_g": 3.6, "iron_mg": 2.1, "calcium_mg": 40,
            "vitamin_a_mcg": 5, "vitamin_c_mg": 1},
  "missing_nutrients": ["Vitamin C", "Fiber"],
  "suggestions": ["Add a cucumber and tomato salad to increase fiber and vitamin C."],
  "unmatched_items": []
}
```

**`correct_meal` input and behavior**

```json
{
  "previous": { "...": "the full MealAnalysis returned earlier" },
  "corrections": [
    {"item_index": 1, "name": "Chana dal", "weight_g": null},
    {"item_index": null, "name": "Cucumber salad", "weight_g": 60}
  ]
}
```

- `item_index` set: that dish is replaced by the typed name. The old weight is kept unless `weight_g` is given.
- `item_index` null: a new dish is added. If `weight_g` is null, a standard serving from the database is used.
- The output is a full `MealAnalysis` with everything recalculated. Corrected items have `user_corrected: true`.
- If a typed dish is not in the database, it stays in the list with zero nutrients, `food_id: null`, `needs_review: true`, and its name is added to `unmatched_items`.
- This function does not use the photo, so it is fast.

**`analyze_fridge` returns `FridgeInventory`, `suggest_recipes` returns `RecipeSuggestions`**

```json
{
  "inventory": {
    "items": [
      {"name": "Spinach", "quantity": "1 bunch", "use_soon": true},
      {"name": "Eggs", "quantity": "6", "use_soon": false},
      {"name": "Milk", "quantity": null, "use_soon": false}
    ]
  },
  "recipes": {
    "recipes": [
      {
        "name": "Spinach omelette",
        "ingredients_from_fridge": ["Spinach", "Eggs"],
        "extra_ingredients": ["Salt"],
        "steps": ["Chop the spinach.", "Beat the eggs and mix in the spinach.", "Cook in a pan for 3 minutes."]
      }
    ]
  }
}
```

**`generate_meal_plan` returns `WeeklyPlan`** (shortened to one day; the real output has 7)

```json
{
  "days": [
    {
      "day": "Monday",
      "breakfast": {"name": "Oats with banana", "ingredients": ["Oats", "Banana", "Milk"], "notes": null},
      "lunch": {"name": "Brown rice with dal", "ingredients": ["Brown rice", "Yellow dal"], "notes": "Low glycemic option"},
      "dinner": {"name": "Vegetable soup", "ingredients": ["Carrot", "Beans", "Tomato"], "notes": null},
      "snack": null,
      "ingredients": ["Oats", "Banana", "Milk", "Brown rice", "Yellow dal", "Carrot", "Beans", "Tomato"]
    }
  ],
  "notes": ["Plan avoids peanuts and is suitable for a diabetic adult."]
}
```

**`generate_grocery_list` returns `GroceryList`**

```json
{
  "items": [
    {"name": "Broccoli", "food_id": 231, "quantity": "500 g", "category": "Vegetables", "source": "missing_ingredient"},
    {"name": "Yogurt", "food_id": 87, "quantity": "1 kg", "category": "Dairy", "source": "preference"},
    {"name": "Almond flour", "food_id": null, "quantity": "1 pack", "category": "Other", "source": "user_added"}
  ],
  "not_in_database": ["Almond flour"]
}
```

## 6. Errors

The functions raise `AIServiceError(code, message, retry)` (from `ai_services.errors`).

| Code | Meaning | Retry |
|---|---|---|
| `INVALID_IMAGE` | Unsupported format, too large, or unreadable | No |
| `NO_FOOD_DETECTED` | The photo has no recognizable food | No, ask for another photo |
| `AI_BUSY` | Gemini is overloaded or rate limited | Yes |
| `AI_INVALID_RESPONSE` | The model returned unusable output after internal retries | Yes |
| `INVALID_INPUT` | A correction has an empty name or a bad item index | No |
| `INTERNAL` | Any other error | No |

`message` is a short text that is safe to show to the user.

## 7. Behavior and limits

**Where the numbers come from**
- The AI identifies foods and estimates weights. All nutrient values come from the nutrition table in Supabase, not from the model.
- Grocery lists are built only from retrieved data (RAG). Items the user typed are marked `user_added`, and anything not found in the database goes to `not_in_database`.

**Safety**
- Items that match a member's allergies are removed in code after generation.
- Suggestions are general nutrition guidance, not medical advice.

**Input limits**
- Images: JPEG or PNG (WebP also works), up to 5 MB. Pass raw bytes and the MIME type, not base64.
- Expected time is about 5 to 30 seconds per call, and the weekly plan is the slowest. Use a 90 second timeout.

**Output format**
- Weights in grams, calories in kcal, iron, calcium, and vitamin C in mg, vitamin A in mcg.
- `suggestions`, `notes`, and recipe `steps` are plain text with no markdown.
- Lists are never `null`. `food_id`, `quantity`, and `notes` can be `null`.

## 8. What the AI module needs from the team

- **Backend:** pass the image as bytes plus the MIME type, and pass the family member data as `FamilyMember` objects loaded from the database.
- **Backend:** provide a read-only Supabase key for the nutrition tables. The backend keeps ownership of profiles, history, and saved plans.
- **Backend and frontend:** for corrections, send back the previous `MealAnalysis` and the list of `ItemCorrection` items.
- **Backend and frontend:** for the grocery list, send the meal plan, the inventory (optional), and any items or requirements the user typed as `user_requirements`.

## 9. Change rule

- Do not rename or remove a field in `schemas.py` without telling the others first.
- Any schema change is announced in the team chat and updated in the repo the same day.
- Send bug reports with the function name, the input, the output you got, and the output you expected.
